import 'dart:convert';
import 'dart:io';

import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/novel_packer.dart';
import 'package:bili_novel_packer/pack_argument.dart';
import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:bili_novel_packer/web/bark_message.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:bili_novel_packer/web/volume_selector.dart';
import 'package:path/path.dart' as path;

class AutoUpdateRunResult {
  final int checked;
  final int updated;
  final List<AutoUpdateItemResult> items;

  const AutoUpdateRunResult({
    required this.checked,
    required this.updated,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    "checked": checked,
    "updated": updated,
    "items": items.map((item) => item.toJson()).toList(),
  };
}

class AutoUpdateItemResult {
  final String jobId;
  final String status;
  final String message;

  const AutoUpdateItemResult({
    required this.jobId,
    required this.status,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    "jobId": jobId,
    "status": status,
    "message": message,
  };
}

class AutoUpdateService {
  final AutoUpdateConfigStore configStore;
  final JobStore store;
  final JobQueue queue;
  final WebDavConfigStore webDavConfigStore;
  final WebDavClient webDavClient;

  bool _running = false;

  AutoUpdateService({
    required this.configStore,
    required this.store,
    required this.queue,
    required this.webDavConfigStore,
    required this.webDavClient,
  });

  Future<AutoUpdateRunResult> runOnce({
    DateTime? now,
    bool markRun = false,
  }) async {
    if (_running) {
      return const AutoUpdateRunResult(checked: 0, updated: 0, items: []);
    }
    _running = true;
    final checkedAt = now ?? DateTime.now();
    try {
      var config = await configStore.load();
      if (!config.enabled && markRun) {
        return const AutoUpdateRunResult(checked: 0, updated: 0, items: []);
      }
      var updated = 0;
      final results = <AutoUpdateItemResult>[];
      var items = config.items;
      for (final item in config.items.where((item) => item.enabled)) {
        final job = store.find(item.jobId);
        if (job == null) {
          final next = item.copyWith(
            lastCheckedAt: checkedAt,
            lastStatus: "missing",
            lastMessage: "任务不存在",
          );
          items = _replaceItem(items, next);
          results.add(
            AutoUpdateItemResult(
              jobId: item.jobId,
              status: "missing",
              message: "任务不存在",
            ),
          );
          continue;
        }
        if (job.status != "succeeded") {
          final next = item.copyWith(
            lastCheckedAt: checkedAt,
            lastStatus: "skipped",
            lastMessage: "任务未完成，已跳过",
          );
          items = _replaceItem(items, next);
          results.add(
            AutoUpdateItemResult(
              jobId: item.jobId,
              status: "skipped",
              message: "任务未完成，已跳过",
            ),
          );
          continue;
        }

        try {
          final snapshot = await _loadSnapshot(job);
          if (item.baselineFingerprint == null ||
              item.baselineFingerprint!.isEmpty) {
            final next = item.copyWith(
              baselineFingerprint: snapshot.fingerprint,
              lastCheckedAt: checkedAt,
              lastStatus: "baseline",
              lastMessage: "已记录更新基线",
            );
            items = _replaceItem(items, next);
            results.add(
              AutoUpdateItemResult(
                jobId: item.jobId,
                status: "baseline",
                message: "已记录更新基线",
              ),
            );
            continue;
          }
          if (item.baselineFingerprint == snapshot.fingerprint) {
            final next = item.copyWith(
              lastCheckedAt: checkedAt,
              lastStatus: "unchanged",
              lastMessage: "暂无更新",
            );
            items = _replaceItem(items, next);
            results.add(
              AutoUpdateItemResult(
                jobId: item.jobId,
                status: "unchanged",
                message: "暂无更新",
              ),
            );
            continue;
          }

          await queue.runExclusive(() => _replaceJob(job, snapshot));
          updated++;
          final next = item.copyWith(
            baselineFingerprint: snapshot.fingerprint,
            lastCheckedAt: checkedAt,
            lastUpdatedAt: checkedAt,
            lastStatus: "updated",
            lastMessage: "已更新 ${snapshot.chapterCount} 章",
          );
          items = _replaceItem(items, next);
          results.add(
            AutoUpdateItemResult(
              jobId: item.jobId,
              status: "updated",
              message: "已更新 ${snapshot.chapterCount} 章",
            ),
          );
        } catch (e) {
          job.addLog("自动更新失败：$e");
          await store.save();
          queue.publishJobSnapshot(job);
          await queue.barkClient.notify(
            config: job.request.barkConfig,
            event: "failure",
            title: barkTitle(job, "自动更新失败"),
            body: barkBody(job, "更新失败：$e"),
          );
          final next = item.copyWith(
            lastCheckedAt: checkedAt,
            lastStatus: "failed",
            lastMessage: e.toString(),
          );
          items = _replaceItem(items, next);
          results.add(
            AutoUpdateItemResult(
              jobId: item.jobId,
              status: "failed",
              message: e.toString(),
            ),
          );
        }
        config = config.copyWith(items: items);
        await configStore.save(config);
      }
      final nextConfig = config.copyWith(
        items: items,
        lastRunAt: markRun ? checkedAt : config.lastRunAt,
      );
      await configStore.save(nextConfig);
      return AutoUpdateRunResult(
        checked: results.length,
        updated: updated,
        items: results,
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _replaceJob(
    DownloadJob job,
    _CatalogSnapshot snapshot,
  ) async {
    final previousStatus = job.status;
    final previousProgress = job.progress;
    final previousError = job.error;
    final previousStartedAt = job.startedAt;
    final previousFinishedAt = job.finishedAt;
    final previousOutputFiles = List<String>.from(job.outputFiles);
    final previousUploadStatus = job.uploadStatus;
    final previousUploadedFiles = List<String>.from(job.uploadedFiles);
    final previousUploadError = job.uploadError;
    final outputDir = Directory(store.outputDirFor(job.id));
    final updatesRoot = Directory(path.join(store.outputsDir, ".updates"));
    final updateId = DateTime.now().microsecondsSinceEpoch.toString();
    final tempDir = Directory(
      path.join(updatesRoot.path, "${job.id}-$updateId"),
    );
    final backupDir = Directory(
      path.join(updatesRoot.path, "${job.id}-$updateId.backup"),
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    var localReplaced = false;
    try {
      job.status = "running";
      job.progress = 0.05;
      job.error = null;
      job.startedAt = DateTime.now();
      job.addLog("自动更新开始");
      await store.save();
      queue.publishJobSnapshot(job);

      final files = await _packSnapshot(job, snapshot, tempDir.path);
      if (await outputDir.exists()) {
        await outputDir.rename(backupDir.path);
      }
      await Directory(path.dirname(outputDir.path)).create(recursive: true);
      await tempDir.rename(outputDir.path);
      localReplaced = true;
      if (await backupDir.exists()) {
        try {
          await backupDir.delete(recursive: true);
        } catch (e) {
          job.addLog("自动更新旧本地备份清理失败：$e");
        }
      }

      job.title = snapshot.novel.title;
      job.author = snapshot.novel.author;
      job.sourceName = snapshot.sourceName;
      job.volumeSummary = volumeSummary(snapshot.volumes);
      job.outputFiles = files.map(path.basename).toList();
      job.status = "succeeded";
      job.progress = 0.97;
      job.finishedAt = DateTime.now();
      job.addLog("自动更新已替换本地输出：${job.outputFiles.length} 个 EPUB 文件");
      await store.save();
      queue.publishJobSnapshot(job);

      await _replaceWebDav(
        job,
        previousUploadedFiles,
        previousUploadStatus,
      );
      job.progress = 1;
      job.addLog("自动更新完成");
      await store.save();
      queue.publishJobSnapshot(job);
      await queue.barkClient.notify(
        config: job.request.barkConfig,
        event: "update",
        title: barkTitle(job, "发现更新"),
        body: barkBody(job, "已自动更新，生成 ${job.outputFiles.length} 个 EPUB 文件"),
      );
    } catch (_) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (!localReplaced) {
        if (await outputDir.exists()) {
          await outputDir.delete(recursive: true);
        }
        if (await backupDir.exists()) {
          await backupDir.rename(outputDir.path);
        }
        job.status = previousStatus;
        job.progress = previousProgress;
        job.error = previousError;
        job.startedAt = previousStartedAt;
        job.finishedAt = previousFinishedAt;
        job.outputFiles = previousOutputFiles;
        job.uploadStatus = previousUploadStatus;
        job.uploadedFiles = previousUploadedFiles;
        job.uploadError = previousUploadError;
      }
      await store.save();
      queue.publishJobSnapshot(job);
      rethrow;
    }
  }

  Future<List<String>> _packSnapshot(
    DownloadJob job,
    _CatalogSnapshot snapshot,
    String outputDirectory,
  ) async {
    final packer = snapshot.packer;
    return packer.pack(
      PackArgument.all(
        addChapterTitle: job.request.addChapterTitle,
        combineVolume: job.request.combineVolume,
        packVolumes: snapshot.volumes,
        outputDirectory: outputDirectory,
        onProgress: (event) {
          final ratio = event.ratio;
          if (ratio != null) {
            job.progress = 0.1 + ratio.clamp(0.0, 1.0).toDouble() * 0.82;
          }
          job.addLog(event.message);
          queue.publishJobSnapshot(job);
        },
      ),
    );
  }

  Future<void> _replaceWebDav(
    DownloadJob job,
    List<String> previousUploadedFiles,
    String previousUploadStatus,
  ) async {
    final config = await _webDavConfigForUpdate(
      job,
      previousUploadedFiles,
      previousUploadStatus,
    );
    if (config == null || !config.enabled) {
      job.uploadStatus = "disabled";
      job.uploadedFiles = [];
      job.uploadError = null;
      job.addLog("WebDAV 未启用，自动更新未替换远端文件");
      return;
    }
    job.uploadStatus = "uploading";
    job.uploadedFiles = [];
    job.uploadError = null;
    job.addLog("自动更新 WebDAV 上传开始");
    await store.save();
    queue.publishJobSnapshot(job);

    final files = job.outputFiles
        .map((fileName) => File(store.outputFileFor(job.id, fileName).path))
        .toList();
    late final WebDavUploadResult result;
    try {
      result = await webDavClient.uploadFiles(
        config: config,
        sourceId: job.sourceId,
        jobId: job.id,
        title: job.title,
        files: files,
      );
    } catch (e) {
      job.uploadStatus = "failed";
      job.uploadedFiles = [];
      job.uploadError = e.toString();
      job.addLog("自动更新 WebDAV 上传失败：$e");
      await store.save();
      queue.publishJobSnapshot(job);
      rethrow;
    }
    final newRemoteFiles = result.remoteFiles.toSet();
    final oldFolders = <String>{};
    for (final oldPath in previousUploadedFiles) {
      if (newRemoteFiles.contains(oldPath)) {
        continue;
      }
      try {
        await webDavClient.deleteDisplayPath(config, oldPath);
      } catch (e) {
        job.addLog("WebDAV 旧文件删除失败：$e");
      }
      final folder = _parentDisplayPath(oldPath);
      if (folder != null &&
          !newRemoteFiles.any((file) => file.startsWith("$folder/"))) {
        oldFolders.add(folder);
      }
    }
    for (final folder in oldFolders) {
      try {
        await webDavClient.deleteDisplayPath(config, folder);
      } catch (e) {
        job.addLog("WebDAV 旧目录删除失败：$e");
      }
    }
    job.uploadStatus = "succeeded";
    job.uploadedFiles = result.remoteFiles;
    job.uploadError = null;
    job.addLog("自动更新 WebDAV 上传完成：${result.remoteFiles.length} 个文件");
  }

  Future<WebDavConfig?> _webDavConfigForUpdate(
    DownloadJob job,
    List<String> previousUploadedFiles,
    String previousUploadStatus,
  ) async {
    final snapshot = job.webDavConfig;
    if (snapshot != null) {
      return snapshot;
    }
    if (previousUploadedFiles.isEmpty && previousUploadStatus == "disabled") {
      return null;
    }
    final config = await webDavConfigStore.load();
    job.webDavConfig = config;
    return config;
  }

  Future<_CatalogSnapshot> _loadSnapshot(DownloadJob job) async {
    final packer = NovelPacker.fromUrl(job.url);
    final novel = await packer.getNovel();
    final catalog = await packer.getCatalog();
    final volumes = selectVolumes(catalog, job.request.volumeRangeText);
    final payload = {
      "volumes": volumes
          .map(
            (volume) => {
              "name": volume.volumeName,
              "chapters": volume.chapters
                  .map(
                    (chapter) => {
                      "name": chapter.chapterName,
                      "url": chapter.chapterUrl ?? "",
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
    final chapterCount = volumes.fold<int>(
      0,
      (sum, volume) => sum + volume.chapters.length,
    );
    return _CatalogSnapshot(
      packer: packer,
      novel: novel,
      sourceName: packer.lightNovelSource.name,
      volumes: volumes,
      chapterCount: chapterCount,
      fingerprint: jsonEncode(payload),
    );
  }

  List<AutoUpdateItem> _replaceItem(
    List<AutoUpdateItem> items,
    AutoUpdateItem next,
  ) {
    var found = false;
    final replaced = items.map((item) {
      if (item.jobId != next.jobId) {
        return item;
      }
      found = true;
      return next;
    }).toList();
    return found ? replaced : [...replaced, next];
  }
}

class _CatalogSnapshot {
  final NovelPacker packer;
  final Novel novel;
  final String sourceName;
  final List<Volume> volumes;
  final int chapterCount;
  final String fingerprint;

  const _CatalogSnapshot({
    required this.packer,
    required this.novel,
    required this.sourceName,
    required this.volumes,
    required this.chapterCount,
    required this.fingerprint,
  });
}

String? _parentDisplayPath(String value) {
  final parts = value.split("/").where((part) => part.isNotEmpty).toList();
  if (parts.length <= 1) {
    return null;
  }
  return "/${parts.take(parts.length - 1).join("/")}";
}
