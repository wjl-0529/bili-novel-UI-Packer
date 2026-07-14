import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/light_novel/bili_novel/bili_novel_source.dart';
import 'package:bili_novel_packer/light_novel/wenku_novel/wenku_novel_source.dart';
import 'package:bili_novel_packer/novel_packer.dart';
import 'package:bili_novel_packer/util/http_util.dart';
import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:bili_novel_packer/web/auto_update_service.dart';
import 'package:bili_novel_packer/web/cleanup_config.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/range_parser.dart';
import 'package:bili_novel_packer/web/session_store.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

class WebApp {
  static const int _previewConcurrency = 4;
  static const int _previewAttempts = 3;

  final JobStore store;
  final JobQueue queue;
  final EventBus events;
  final SessionStore sessions;
  final String webRoot;
  final WebDavConfigStore webDavConfigStore;
  final WebDavClient webDavClient;
  final CleanupConfigStore cleanupConfigStore;
  final AutoUpdateConfigStore autoUpdateConfigStore;
  final AutoUpdateService autoUpdateService;
  final String? embeddedPlatform;
  final String? nativeBootstrapToken;
  final DateTime? nativeBootstrapExpiresAt;
  bool _nativeBootstrapConsumed = false;
  final Map<String, _NativeExport> _nativeExports = {};
  final Map<String, _NovelCover> _novelCovers = {};
  final Random _nativeExportRandom = Random.secure();

  WebApp({
    required this.store,
    required this.queue,
    required this.events,
    required this.sessions,
    required this.webRoot,
    required this.webDavConfigStore,
    required this.webDavClient,
    required this.cleanupConfigStore,
    required this.autoUpdateConfigStore,
    required this.autoUpdateService,
    this.embeddedPlatform,
    this.nativeBootstrapToken,
    this.nativeBootstrapExpiresAt,
  });

  Handler get handler {
    final router = Router()
      ..get("/api/runtime", _runtime)
      ..post("/api/native/bootstrap", _nativeBootstrap)
      ..post("/api/native/exports", _createNativeExport)
      ..get("/api/native/exports/<token>", _downloadNativeExport)
      ..post("/api/login", _login)
      ..post("/api/logout", _logout)
      ..get("/api/me", _me)
      ..get("/api/jobs", _jobs)
      ..post("/api/jobs", _createJobs)
      ..post("/api/novel/preview", _previewNovel)
      ..get("/api/novel/covers/<token>", _downloadNovelCover)
      ..get("/api/webdav/config", _webDavConfig)
      ..put("/api/webdav/config", _saveWebDavConfig)
      ..post("/api/webdav/test", _testWebDavConfig)
      ..get("/api/cleanup/config", _cleanupConfig)
      ..put("/api/cleanup/config", _saveCleanupConfig)
      ..get("/api/auto-update/config", _autoUpdateConfig)
      ..put("/api/auto-update/config", _saveAutoUpdateConfig)
      ..post("/api/auto-update/run", _runAutoUpdate)
      ..post("/api/jobs/cleanup", _cleanupCompletedJobs)
      ..get("/api/jobs/<id>", _job)
      ..post("/api/jobs/<id>/cancel", _cancelJob)
      ..post("/api/jobs/<id>/retry", _retryJob)
      ..delete("/api/jobs/<id>/outputs", _deleteJobOutputs)
      ..delete("/api/jobs/<id>", _deleteJob)
      ..get("/api/jobs/<id>/files/<file|.*>", _downloadFile)
      ..get("/api/events", _eventStream);

    final staticDir = Directory(webRoot);
    final staticHandler = staticDir.existsSync()
        ? createStaticHandler(webRoot, defaultDocument: "index.html")
        : (Request request) => Response.notFound(
            "Web 控制台还没有构建，请先运行 npm install && npm run build。",
          );
    router.mount("/", staticHandler);

    return const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_authMiddleware)
        .addHandler(router.call);
  }

  Response _runtime(Request request) {
    return _json({
      "embedded": embeddedPlatform != null,
      "platform": embeddedPlatform,
    });
  }

  Response _nativeBootstrap(Request request) {
    if (embeddedPlatform == null || nativeBootstrapToken == null) {
      return _json({"message": "Native bootstrap is unavailable"}, status: 404);
    }
    final authorization = request.headers["authorization"] ?? "";
    final expected = "Bearer $nativeBootstrapToken";
    final expired =
        nativeBootstrapExpiresAt == null ||
        DateTime.now().isAfter(nativeBootstrapExpiresAt!);
    if (_nativeBootstrapConsumed || expired || authorization != expected) {
      return _json({
        "message": "Native bootstrap token is invalid",
      }, status: 401);
    }
    _nativeBootstrapConsumed = true;
    final sessionToken = sessions.create();
    return Response.found(
      "/",
      headers: {"set-cookie": sessions.loginCookie(sessionToken)},
    );
  }

  Future<Response> _createNativeExport(Request request) async {
    final payload = await _readJson(request);
    final jobId = (payload["jobId"] as String?)?.trim() ?? "";
    final fileName = (payload["fileName"] as String?)?.trim() ?? "";
    final output = _resolveOutputFile(jobId, fileName);
    if (output == null) {
      return _json({"message": "文件不存在或已被清理"}, status: 404);
    }
    _removeExpiredNativeExports();
    final token = _randomNativeExportToken();
    _nativeExports[token] = _NativeExport(
      jobId: jobId,
      fileName: fileName,
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    return _json({
      "url": "/api/native/exports/$token",
      "fileName": fileName,
      "expiresIn": 60,
    }, status: 201);
  }

  Response _downloadNativeExport(Request request, String token) {
    final export = _nativeExports.remove(token);
    if (export == null || DateTime.now().isAfter(export.expiresAt)) {
      return _json({"message": "导出链接已失效"}, status: 404);
    }
    final output = _resolveOutputFile(export.jobId, export.fileName);
    if (output == null) {
      return _json({"message": "文件不存在或已被清理"}, status: 404);
    }
    return _outputFileResponse(output, export.fileName);
  }

  Future<Response> _login(Request request) async {
    final payload = await _readJson(request);
    final password = (payload["password"] as String?) ?? "";
    if (!sessions.verifyPassword(password)) {
      return _json({"ok": false, "message": "管理密码错误"}, status: 401);
    }
    final token = sessions.create();
    return _json(
      {"ok": true},
      headers: {"set-cookie": sessions.loginCookie(token)},
    );
  }

  Response _logout(Request request) {
    sessions.destroy(sessions.readToken(request.headers));
    return _json(
      {"ok": true},
      headers: {"set-cookie": sessions.logoutCookie()},
    );
  }

  Response _me(Request request) {
    final token = sessions.readToken(request.headers);
    return _json({"authenticated": sessions.isValid(token)});
  }

  Response _jobs(Request request) {
    return _json({
      "jobs": store.jobsToJson(),
    });
  }

  Future<Response> _createJobs(Request request) async {
    try {
      final payload = await _readJson(request);
      final jobRequest = JobRequest.fromJson(payload);
      final jobs = await queue.submit(jobRequest);
      return _json({
        "jobs": jobs.map((job) => store.jobToJson(job)).toList(),
      }, status: 201);
    } on RangeParseException catch (e) {
      return _json({"message": e.message}, status: 400);
    } catch (e) {
      return _json({"message": e.toString()}, status: 400);
    }
  }

  Future<Response> _previewNovel(Request request) async {
    try {
      final payload = await _readJson(request);
      final jobRequest = JobRequest.fromJson(payload);
      final ids = parseIntegerRange(
        jobRequest.rangeText,
        maxCount: queue.maxBatchSize,
      );
      final urls = buildUrlsFromTemplate(jobRequest.urlTemplate, ids);
      final results = await _loadNovelPreviews(ids, urls);
      final previews = results
          .where((result) => result.preview != null)
          .map((result) => result.preview!)
          .toList();
      final failures = results
          .where((result) => result.preview == null)
          .map((result) => result.failureToJson())
          .toList();
      if (previews.isEmpty) {
        return _json({
          "message": failures.isEmpty ? "未找到可预览的小说" : "搜索失败，未找到可预览的小说",
          "previewFailures": failures,
        }, status: 400);
      }
      return _json({
        "previews": previews,
        "preview": previews.first,
        "previewFailures": failures,
      });
    } on RangeParseException catch (e) {
      return _json({"message": e.message}, status: 400);
    } catch (e) {
      return _json({"message": "搜索失败：$e"}, status: 400);
    }
  }

  Future<Response> _downloadNovelCover(Request request, String token) async {
    _removeExpiredNovelCovers();
    final cover = _novelCovers[token];
    if (cover == null || DateTime.now().isAfter(cover.expiresAt)) {
      return _json({"message": "封面链接已失效"}, status: 404);
    }
    try {
      final pageHost = Uri.tryParse(cover.referer)?.host.toLowerCase() ?? "";
      final userAgent = pageHost.contains("wenku8")
          ? WenkuNovelSource.userAgent
          : BiliNovelSource.userAgent;
      final upstream = await httpGetResponse(
        cover.url,
        headers: {
          "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
          "Referer": cover.referer,
          "User-Agent": userAgent,
        },
        timeout: const Duration(seconds: 30),
      );
      if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
        return _json({"message": "封面下载失败"}, status: 502);
      }
      final contentType = upstream.headers["content-type"] ?? "image/jpeg";
      return Response.ok(
        upstream.bodyBytes,
        headers: {
          "content-type": contentType,
          "cache-control": "private, max-age=900",
        },
      );
    } catch (_) {
      return _json({"message": "封面下载失败"}, status: 502);
    }
  }

  Future<Response> _webDavConfig(Request request) async {
    final config = await webDavConfigStore.load();
    return _json({"config": config.toSafeJson()});
  }

  Future<Response> _saveWebDavConfig(Request request) async {
    try {
      final payload = await _readJson(request);
      final config = await webDavConfigStore.saveFromPayload(payload);
      return _json({"ok": true, "config": config.toSafeJson()});
    } catch (e) {
      return _json({"message": "WebDAV 配置保存失败：$e"}, status: 400);
    }
  }

  Future<Response> _testWebDavConfig(Request request) async {
    try {
      final payload = await _readJson(request);
      final current = await webDavConfigStore.load();
      final config = WebDavConfig.fromJson({
        ...current.toJson(),
        ...payload,
        if ((payload["password"] as String?)?.isEmpty == true)
          "password": current.password,
      }).copyWith(enabled: true);
      await webDavClient.test(config);
      return _json({"ok": true});
    } catch (e) {
      return _json({"message": "WebDAV 测试失败：$e"}, status: 400);
    }
  }

  Future<Response> _cleanupConfig(Request request) async {
    final config = await cleanupConfigStore.load();
    return _json({"config": config.toJson()});
  }

  Future<Response> _saveCleanupConfig(Request request) async {
    try {
      final payload = await _readJson(request);
      final config = await cleanupConfigStore.saveFromPayload(payload);
      return _json({"ok": true, "config": config.toJson()});
    } catch (e) {
      return _json({"message": "自动清理设置保存失败：$e"}, status: 400);
    }
  }

  Future<Response> _autoUpdateConfig(Request request) async {
    final config = await autoUpdateConfigStore.load();
    return _json({"config": config.toJson()});
  }

  Future<Response> _saveAutoUpdateConfig(Request request) async {
    try {
      final payload = await _readJson(request);
      final allowedJobIds = store.jobs
          .where((job) => job.status == "succeeded")
          .map((job) => job.id)
          .toSet();
      final config = await autoUpdateConfigStore.saveFromPayload(
        payload,
        allowedJobIds: allowedJobIds,
      );
      return _json({"ok": true, "config": config.toJson()});
    } catch (e) {
      return _json({"message": "自动更新设置保存失败：$e"}, status: 400);
    }
  }

  Future<Response> _runAutoUpdate(Request request) async {
    final result = await autoUpdateService.runOnce();
    final config = await autoUpdateConfigStore.load();
    return _json({
      "ok": true,
      "result": result.toJson(),
      "config": config.toJson(),
    });
  }

  Future<List<_PreviewResult>> _loadNovelPreviews(
    List<int> ids,
    List<String> urls,
  ) async {
    final results = List<_PreviewResult?>.filled(ids.length, null);
    var nextIndex = 0;
    final workerCount = ids.length < _previewConcurrency
        ? ids.length
        : _previewConcurrency;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        nextIndex++;
        if (index >= ids.length) {
          return;
        }
        results[index] = await _loadNovelPreviewWithRetry(
          ids[index],
          urls[index],
        );
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<_PreviewResult>();
  }

  Future<_PreviewResult> _loadNovelPreviewWithRetry(
    int sourceId,
    String url,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _previewAttempts; attempt++) {
      try {
        final preview = await _loadNovelPreview(sourceId, url);
        return _PreviewResult.success(sourceId, url, preview);
      } catch (e) {
        lastError = e;
        if (attempt < _previewAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    return _PreviewResult.failure(sourceId, url, lastError.toString());
  }

  Future<Map<String, dynamic>> _loadNovelPreview(
    int sourceId,
    String url,
  ) async {
    final packer = NovelPacker.fromUrl(url);
    final novel = await packer.getNovel();

    Catalog? catalog;
    try {
      catalog = await packer.getCatalog();
    } catch (_) {
      catalog = null;
    }

    return _novelPreviewToJson(
      novel,
      sourceId,
      url,
      packer.lightNovelSource.name,
      catalog,
    );
  }

  Response _job(Request request, String id) {
    final job = store.find(id);
    if (job == null) {
      return _json({"message": "任务不存在"}, status: 404);
    }
    return _json({"job": store.jobToJson(job)});
  }

  Future<Response> _cancelJob(Request request, String id) async {
    final ok = await queue.cancel(id);
    if (!ok) {
      return _json({"message": "任务无法取消"}, status: 404);
    }
    return _json({"ok": true});
  }

  Future<Response> _retryJob(Request request, String id) async {
    final ok = await queue.retry(id);
    if (!ok) {
      return _json({"message": "任务无法重试"}, status: 400);
    }
    return _json({"ok": true});
  }

  Future<Response> _deleteJob(Request request, String id) async {
    final ok = await queue.delete(id);
    if (!ok) {
      return _json({"message": "任务不存在"}, status: 404);
    }
    return _json({"ok": true});
  }

  Future<Response> _deleteJobOutputs(Request request, String id) async {
    final job = store.find(id);
    if (job == null) {
      return _json({"message": "任务不存在"}, status: 404);
    }
    if (job.status == "running" ||
        job.status == "queued" ||
        job.status == "canceling") {
      return _json({"message": "任务未结束，不能清理输出文件"}, status: 400);
    }
    final nextJob = await queue.deleteOutputs(id);
    if (nextJob == null) {
      return _json({"message": "输出文件无法清理"}, status: 400);
    }
    return _json({"ok": true, "job": store.jobToJson(nextJob)});
  }

  Future<Response> _cleanupCompletedJobs(Request request) async {
    final deleted = await queue.cleanupCompleted();
    return _json({
      "ok": true,
      "deleted": deleted,
      "jobs": store.jobsToJson(),
    });
  }

  Response _downloadFile(Request request, String id, String file) {
    final fileName = Uri.decodeComponent(file).split("/").last;
    final outputFile = _resolveOutputFile(id, fileName);
    if (outputFile == null) {
      return _json({"message": "文件不存在"}, status: 404);
    }
    return _outputFileResponse(outputFile, fileName);
  }

  File? _resolveOutputFile(String jobId, String fileName) {
    if (jobId.isEmpty ||
        fileName.isEmpty ||
        fileName != path.basename(fileName) ||
        fileName.contains("/") ||
        fileName.contains("\\")) {
      return null;
    }
    final job = store.find(jobId);
    if (job == null || !job.outputFiles.contains(fileName)) {
      return null;
    }
    final outputFile = store.outputFileFor(jobId, fileName);
    return outputFile.existsSync() ? outputFile : null;
  }

  Response _outputFileResponse(File outputFile, String fileName) {
    final fallbackName = fileName.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
    final encodedName = Uri.encodeComponent(fileName);
    return Response.ok(
      outputFile.openRead(),
      headers: {
        "content-type": "application/epub+zip",
        "content-length": outputFile.lengthSync().toString(),
        "content-disposition":
            'attachment; filename="$fallbackName"; filename*=UTF-8\'\'$encodedName',
      },
    );
  }

  Response _eventStream(Request request) {
    final stream = _createEventStream();
    return Response.ok(
      stream,
      context: {"shelf.io.buffer_output": false},
      headers: {
        "content-type": "text/event-stream",
        "cache-control": "no-cache, no-transform",
        "connection": "keep-alive",
        "x-accel-buffering": "no",
      },
    );
  }

  Stream<List<int>> _createEventStream() {
    // The Shelf response subscriber owns this stream and triggers onCancel.
    // ignore: close_sinks
    late StreamController<List<int>> controller;
    StreamSubscription<String>? subscription;
    Timer? heartbeat;

    void addEvent(String event) {
      if (!controller.isClosed) {
        controller.add(_sseData(event));
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        subscription = events.subscribe().listen(
          addEvent,
          onError: controller.addError,
        );
        if (!controller.isClosed) {
          controller.add(utf8.encode("retry: 1000\n\n"));
        }
        addEvent(
          events.formatEvent(
            "jobs",
            store.jobsToJson(),
          ),
        );
        heartbeat = Timer.periodic(
          const Duration(seconds: 5),
          (_) {
            addEvent(
              events.formatEvent(
                "heartbeat",
                {"message": "keepalive"},
              ),
            );
          },
        );
      },
      onCancel: () async {
        heartbeat?.cancel();
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  Middleware get _authMiddleware {
    return (Handler inner) {
      return (Request request) {
        if (!_requiresAuth(request)) {
          return inner(request);
        }
        final token = sessions.readToken(request.headers);
        if (!sessions.isValid(token)) {
          return _json({"message": "请先登录"}, status: 401);
        }
        return inner(request);
      };
    };
  }

  bool _requiresAuth(Request request) {
    final path = request.url.path;
    if (!path.startsWith("api/")) {
      return false;
    }
    if (request.method == "GET" && path.startsWith("api/native/exports/")) {
      return false;
    }
    return path != "api/login" &&
        path != "api/me" &&
        path != "api/runtime" &&
        path != "api/native/bootstrap";
  }

  String _randomNativeExportToken() {
    final bytes = List<int>.generate(
      32,
      (_) => _nativeExportRandom.nextInt(256),
    );
    return base64UrlEncode(bytes).replaceAll("=", "");
  }

  void _removeExpiredNativeExports() {
    final now = DateTime.now();
    _nativeExports.removeWhere((_, export) => now.isAfter(export.expiresAt));
  }

  List<int> _sseData(String event) => utf8.encode("data: $event\n\n");

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) {
      return {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException("请求体必须是 JSON 对象");
  }

  Response _json(
    Object body, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    return shelf.Response(
      status,
      body: jsonEncode(body),
      headers: {
        "content-type": "application/json; charset=utf-8",
        ...?headers,
      },
    );
  }

  Map<String, dynamic> _novelPreviewToJson(
    Novel novel,
    int sourceId,
    String url,
    String sourceName,
    Catalog? catalog,
  ) {
    final chapterCount = catalog?.volumes.fold<int>(
      0,
      (sum, volume) => sum + volume.chapters.length,
    );
    return {
      "sourceId": sourceId,
      "id": novel.id,
      "url": url,
      "sourceName": sourceName,
      "title": novel.title,
      "alias": novel.alias,
      "author": novel.author,
      "status": novel.status,
      "coverUrl": _registerNovelCover(novel.coverUrl, url),
      "tags": novel.tags ?? [],
      "publisher": novel.publisher,
      "description": novel.description,
      "volumeCount": catalog?.volumes.length,
      "chapterCount": chapterCount,
    };
  }

  String? _normalizeCoverUrl(String? coverUrl, String pageUrl) {
    if (coverUrl == null || coverUrl.trim().isEmpty) {
      return null;
    }
    final value = coverUrl.trim();
    if (value.startsWith("//")) {
      return "https:$value";
    }
    if (value.startsWith("http://") || value.startsWith("https://")) {
      return value;
    }
    final page = Uri.parse(pageUrl);
    if (value.startsWith("/")) {
      return "${page.scheme}://${page.host}$value";
    }
    return page.resolve(value).toString();
  }

  String? _registerNovelCover(String? coverUrl, String pageUrl) {
    final normalized = _normalizeCoverUrl(coverUrl, pageUrl);
    if (normalized == null) {
      return null;
    }
    _removeExpiredNovelCovers();
    final token = _randomNativeExportToken();
    _novelCovers[token] = _NovelCover(
      url: normalized,
      referer: pageUrl,
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    );
    return "/api/novel/covers/$token";
  }

  void _removeExpiredNovelCovers() {
    final now = DateTime.now();
    _novelCovers.removeWhere((_, cover) => now.isAfter(cover.expiresAt));
  }
}

class _NativeExport {
  final String jobId;
  final String fileName;
  final DateTime expiresAt;

  const _NativeExport({
    required this.jobId,
    required this.fileName,
    required this.expiresAt,
  });
}

class _NovelCover {
  final String url;
  final String referer;
  final DateTime expiresAt;

  const _NovelCover({
    required this.url,
    required this.referer,
    required this.expiresAt,
  });
}

class _PreviewResult {
  final int sourceId;
  final String url;
  final Map<String, dynamic>? preview;
  final String? message;

  const _PreviewResult.success(this.sourceId, this.url, this.preview)
    : message = null;

  const _PreviewResult.failure(this.sourceId, this.url, this.message)
    : preview = null;

  Map<String, dynamic> failureToJson() => {
    "sourceId": sourceId,
    "url": url,
    "message": message ?? "搜索失败",
  };
}
