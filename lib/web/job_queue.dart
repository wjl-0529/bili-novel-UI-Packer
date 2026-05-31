import 'dart:async';
import 'dart:io';

import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/novel_packer.dart';
import 'package:bili_novel_packer/pack_argument.dart';
import 'package:bili_novel_packer/pack_progress.dart';
import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/bark_message.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/range_parser.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class JobCanceledException implements Exception {
  final String jobId;

  JobCanceledException(this.jobId);

  @override
  String toString() => "任务 $jobId 已取消";
}

class JobQueue {
  final JobStore store;
  final EventBus events;
  final BarkClient barkClient;
  final WebDavConfigStore webDavConfigStore;
  final WebDavClient webDavClient;
  final int maxBatchSize;
  final List<String> _queue = [];
  final Set<String> _cancelRequested = {};
  final Set<String> _deletedJobs = {};
  final Map<String, DateTime> _lastProgressBarkAt = {};
  String? _activeJobId;

  JobQueue({
    required this.store,
    required this.events,
    required this.barkClient,
    required this.webDavConfigStore,
    required this.webDavClient,
    required this.maxBatchSize,
  });

  Future<void> resumeQueuedJobs() async {
    for (final job in store.jobs) {
      if (job.status == "running") {
        job.status = "queued";
        job.progress = 0;
        job.addLog("服务已重启，任务已放回队列");
      }
      if (job.status == "canceling") {
        job.status = "canceled";
        job.finishedAt = DateTime.now();
        job.addLog("服务已重启，取消中的任务已标记为已取消");
      }
      if (job.status == "queued" && !_queue.contains(job.id)) {
        _queue.add(job.id);
      }
    }
    await store.save();
    _publishJobs();
    _pump();
  }

  Future<List<DownloadJob>> submit(JobRequest request) async {
    final ids = parseIntegerRange(
      request.rangeText,
      maxCount: maxBatchSize,
    );
    final urls = buildUrlsFromTemplate(request.urlTemplate, ids);
    final uuid = Uuid();
    final webDavConfig = await webDavConfigStore.load();
    final uploadStatus = _initialUploadStatus(webDavConfig);
    final jobs = <DownloadJob>[];
    for (var i = 0; i < ids.length; i++) {
      jobs.add(DownloadJob(
        id: uuid.v4(),
        sourceId: ids[i],
        url: urls[i],
        request: request,
        webDavConfig: webDavConfig,
        uploadStatus: uploadStatus,
        logs: ["已加入队列：${urls[i]}"],
      ));
    }
    await store.addAll(jobs);
    _queue.addAll(jobs.map((job) => job.id));
    _publishJobs();
    _pump();
    return jobs;
  }

  Future<bool> retry(String jobId) async {
    final job = store.find(jobId);
    if (job == null ||
        job.status == "running" ||
        job.status == "canceling" ||
        job.status == "queued") {
      return false;
    }
    job.status = "queued";
    job.progress = 0;
    job.error = null;
    job.finishedAt = null;
    job.outputFiles = [];
    job.webDavConfig = await webDavConfigStore.load();
    job.uploadStatus = _initialUploadStatus(job.webDavConfig!);
    job.uploadedFiles = [];
    job.uploadError = null;
    job.addLog("已重新加入队列");
    _deletedJobs.remove(jobId);
    _cancelRequested.remove(jobId);
    if (!_queue.contains(jobId)) {
      _queue.add(jobId);
    }
    await store.save();
    _publishJob(job);
    _pump();
    return true;
  }

  Future<bool> cancel(String jobId) async {
    final job = store.find(jobId);
    if (job == null || _isTerminal(job.status)) {
      return false;
    }
    final wasActive = _activeJobId == jobId;
    _cancelRequested.add(jobId);
    if (job.status == "queued") {
      _queue.remove(jobId);
      await _finishCanceled(job, "任务开始前已取消");
    } else {
      await _finishCanceled(job, "任务已取消，后台正在停止当前请求");
    }
    if (wasActive) {
      _releaseActiveSlot(jobId);
    }
    return true;
  }

  Future<bool> delete(String jobId) async {
    final job = store.find(jobId);
    if (job == null) {
      return false;
    }
    final wasActive = _activeJobId == jobId;
    _deletedJobs.add(jobId);
    _cancelRequested.add(jobId);
    _queue.remove(jobId);
    final deleted = await store.delete(jobId);
    if (!deleted) {
      return false;
    }
    events.publish("jobDeleted", {"id": jobId});
    _publishJobs();
    if (wasActive) {
      _releaseActiveSlot(jobId);
    }
    return true;
  }

  Future<DownloadJob?> deleteOutputs(String jobId) async {
    final job = store.find(jobId);
    if (job == null || !_isTerminal(job.status)) {
      return null;
    }
    await store.deleteOutputs(jobId);
    job.outputFiles = [];
    job.addLog("输出文件已清理");
    await store.save();
    _publishJob(job);
    return job;
  }

  Future<int> cleanupCompleted() async {
    final deletableJobs =
        store.jobs.where((job) => _isTerminal(job.status)).toList();
    return _deleteJobs(deletableJobs);
  }

  Future<int> cleanupCompletedOlderThan(DateTime cutoff) async {
    final deletableJobs = store.jobs
        .where((job) =>
            _isTerminal(job.status) &&
            _cleanupReferenceAt(job).isBefore(cutoff))
        .toList();
    return _deleteJobs(deletableJobs);
  }

  Future<T> runExclusive<T>(Future<T> Function() action) async {
    while (_activeJobId != null || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _activeJobId = "__maintenance__";
    try {
      return await action();
    } finally {
      if (_activeJobId == "__maintenance__") {
        _activeJobId = null;
      }
      _pump();
    }
  }

  void publishJobSnapshot(DownloadJob job) {
    _publishJob(job);
  }

  void publishJobsSnapshot() {
    _publishJobs();
  }

  Future<int> _deleteJobs(List<DownloadJob> deletableJobs) async {
    if (deletableJobs.isEmpty) {
      return 0;
    }
    final deletedIds = deletableJobs.map((job) => job.id).toList();
    for (final id in deletedIds) {
      _deletedJobs.add(id);
      _cancelRequested.add(id);
      _queue.remove(id);
    }
    final deleted = await store.deleteMany(deletedIds);
    for (final id in deletedIds) {
      events.publish("jobDeleted", {"id": id});
    }
    _publishJobs();
    return deleted;
  }

  DateTime _cleanupReferenceAt(DownloadJob job) =>
      job.finishedAt ?? job.createdAt;

  void _pump() {
    if (_activeJobId != null) {
      return;
    }
    while (_queue.isNotEmpty) {
      final jobId = _queue.removeAt(0);
      final job = store.find(jobId);
      if (job == null || job.status != "queued") {
        continue;
      }
      _activeJobId = jobId;
      unawaited(_runActiveJob(job));
      return;
    }
  }

  Future<void> _runActiveJob(DownloadJob job) async {
    try {
      await _runJob(job);
    } finally {
      if (_deletedJobs.contains(job.id)) {
        await store.deleteOutputs(job.id);
      }
      if (_activeJobId == job.id) {
        _activeJobId = null;
        _pump();
      }
    }
  }

  Future<void> _runJob(DownloadJob job) async {
    try {
      _throwIfCanceled(job.id);
      job.status = "running";
      job.startedAt = DateTime.now();
      job.finishedAt = null;
      job.progress = 0.02;
      job.addLog("正在加载小说信息");
      await store.save();
      _publishJob(job);

      final packer = NovelPacker.fromUrl(job.url);
      await packer.init(
        novelCallback: (novel) {
          if (_cancelRequested.contains(job.id)) {
            return;
          }
          job.title = novel.title;
          job.author = novel.author;
          job.sourceName = packer.lightNovelSource.name;
          job.progress = 0.12;
          job.addLog("已加载《${novel.title}》");
          _publishJob(job);
        },
        catalogCallback: (catalog) {
          if (_cancelRequested.contains(job.id)) {
            return;
          }
          job.progress = 0.18;
          job.addLog("目录已加载：${catalog.volumes.length} 个分卷");
          _publishJob(job);
        },
      );
      _throwIfCanceled(job.id);
      await _sendBark(job, "start", "下载开始", "已开始下载");

      final selectedVolumes = _selectVolumes(
        packer.catalog,
        job.request.volumeRangeText,
      );
      job.volumeSummary = _volumeSummary(selectedVolumes);
      job.progress = 0.22;
      job.webDavConfig ??= await webDavConfigStore.load();
      job.uploadStatus = _initialUploadStatus(job.webDavConfig);
      job.uploadedFiles = [];
      job.uploadError = null;
      job.addLog("已选择 ${selectedVolumes.length} 个分卷");
      await store.save();
      _publishJob(job);

      final outputDir = store.outputDirFor(job.id);
      await Directory(outputDir).create(recursive: true);
      final files = await packer.pack(PackArgument.all(
        addChapterTitle: job.request.addChapterTitle,
        combineVolume: job.request.combineVolume,
        packVolumes: selectedVolumes,
        outputDirectory: outputDir,
        onProgress: (event) => _onPackProgress(job, event),
      ));
      _throwIfCanceled(job.id);

      job.outputFiles = files.map(path.basename).toList();
      await _uploadOutputsIfEnabled(job, files);
      job.status = "succeeded";
      job.progress = 1;
      job.finishedAt = DateTime.now();
      job.addLog("已完成，生成 ${job.outputFiles.length} 个 EPUB 文件");
      await store.save();
      _publishJob(job);
      await _sendBark(
        job,
        "success",
        "下载完成",
        "已完成，生成 ${job.outputFiles.length} 个 EPUB 文件",
      );
    } on JobCanceledException {
      await _finishCanceled(job, "任务已取消");
    } catch (e, stackTrace) {
      if (_cancelRequested.contains(job.id) || job.status == "canceled") {
        await _finishCanceled(job, "任务已取消");
        return;
      }
      job.status = "failed";
      job.error = e.toString();
      job.finishedAt = DateTime.now();
      job.addLog("任务失败：$e");
      job.logs.add(stackTrace.toString().split("\n").take(8).join("\n"));
      await store.save();
      _publishJob(job);
      await _sendBark(
        job,
        "failure",
        "下载失败",
        "失败原因：$e",
      );
    } finally {
      _cancelRequested.remove(job.id);
      _lastProgressBarkAt.remove(job.id);
    }
  }

  void _onPackProgress(DownloadJob job, PackProgressEvent event) {
    _throwIfCanceled(job.id);
    if (_isDeleted(job.id)) {
      return;
    }
    final ratio = event.ratio;
    if (ratio != null) {
      final boundedRatio = ratio.clamp(0.0, 1.0).toDouble();
      job.progress = 0.22 + boundedRatio * 0.74;
    }
    job.addLog(event.message);
    unawaited(store.save());
    _publishJob(job);
    if ((event.type == "chapter-downloaded" ||
            event.type == "chapter-packed") &&
        ratio != null) {
      unawaited(_maybeSendProgressBark(job, ratio));
    }
  }

  List<Volume> _selectVolumes(Catalog catalog, String rangeText) {
    if (rangeText.trim().isEmpty || rangeText.trim() == "0") {
      return catalog.volumes;
    }
    final indexes = parseIntegerRange(
      rangeText,
      maxValue: catalog.volumes.length,
    );
    return indexes.map((index) => catalog.volumes[index - 1]).toList();
  }

  String _volumeSummary(List<Volume> volumes) {
    if (volumes.isEmpty) {
      return "未选择分卷";
    }
    if (volumes.length <= 3) {
      return volumes.map((volume) => volume.toString()).join(", ");
    }
    return "${volumes.length} 个分卷";
  }

  Future<void> _sendBark(
    DownloadJob job,
    String event,
    String title,
    String body,
  ) async {
    final sent = await barkClient.notify(
      config: job.request.barkConfig,
      event: event,
      title: barkTitle(job, title),
      body: barkBody(job, body),
    );
    if (sent) {
      job.addLog("Bark 通知已发送：$event");
      await store.save();
      _publishJob(job);
    }
  }

  Future<void> _maybeSendProgressBark(DownloadJob job, double ratio) async {
    final now = DateTime.now();
    final last = _lastProgressBarkAt[job.id];
    final throttle = Duration(
      seconds: job.request.barkConfig.progressThrottleSeconds,
    );
    if (last != null && now.difference(last) < throttle) {
      return;
    }
    _lastProgressBarkAt[job.id] = now;
    await _sendBark(
      job,
      "progress",
      "下载进度",
      "当前进度 ${(ratio * 100).round()}%",
    );
  }

  String _initialUploadStatus(WebDavConfig? config) {
    return config?.enabled == true ? "pending" : "disabled";
  }

  Future<void> _uploadOutputsIfEnabled(
    DownloadJob job,
    List<String> outputPaths,
  ) async {
    final config = job.webDavConfig ?? await webDavConfigStore.load();
    job.webDavConfig = config;
    if (!config.enabled) {
      job.uploadStatus = "disabled";
      job.uploadedFiles = [];
      job.uploadError = null;
      return;
    }

    job.uploadStatus = "uploading";
    job.uploadedFiles = [];
    job.uploadError = null;
    job.progress = 0.97;
    job.addLog("WebDAV 上传开始");
    await store.save();
    _publishJob(job);

    try {
      final result = await webDavClient.uploadFiles(
        config: config,
        sourceId: job.sourceId,
        jobId: job.id,
        title: job.title,
        files: outputPaths.map((filePath) => File(filePath)).toList(),
      );
      job.uploadStatus = "succeeded";
      job.uploadedFiles = result.remoteFiles;
      job.uploadError = null;
      job.progress = 0.99;
      job.addLog("WebDAV 上传完成：${result.remoteFiles.length} 个文件");
      await store.save();
      _publishJob(job);
    } catch (e) {
      job.uploadStatus = "failed";
      job.uploadError = e.toString();
      job.addLog("WebDAV 上传失败：$e");
      await store.save();
      _publishJob(job);
      rethrow;
    }
  }

  void _throwIfCanceled(String jobId) {
    if (_cancelRequested.contains(jobId)) {
      throw JobCanceledException(jobId);
    }
  }

  bool _isTerminal(String status) {
    return status == "succeeded" || status == "failed" || status == "canceled";
  }

  Future<void> _finishCanceled(DownloadJob job, String message) async {
    if (_isDeleted(job.id)) {
      return;
    }
    job.status = "canceled";
    job.finishedAt = DateTime.now();
    job.outputFiles = [];
    job.uploadStatus = "disabled";
    job.uploadedFiles = [];
    job.uploadError = null;
    job.addLog(message);
    await store.deleteOutputs(job.id);
    await store.save();
    _publishJob(job);
  }

  void _releaseActiveSlot(String jobId) {
    if (_activeJobId != jobId) {
      return;
    }
    _activeJobId = null;
    _pump();
  }

  void _publishJob(DownloadJob job) {
    if (_isDeleted(job.id)) {
      return;
    }
    events.publish("job", store.jobToJson(job));
  }

  void _publishJobs() {
    events.publish("jobs", store.jobsToJson());
  }

  bool _isDeleted(String jobId) {
    return _deletedJobs.contains(jobId) || store.find(jobId) == null;
  }
}
