import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_novel_packer/logger.dart';
import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:bili_novel_packer/web/auto_update_scheduler.dart';
import 'package:bili_novel_packer/web/auto_update_service.dart';
import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/cleanup_config.dart';
import 'package:bili_novel_packer/web/cleanup_scheduler.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/session_store.dart';
import 'package:bili_novel_packer/web/web_app.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Owns the complete Shelf service lifecycle for both the standalone server
/// and native shells. Native callers should bind to loopback and request port 0.
class WebServerRuntime {
  final HttpServer server;
  final JobStore store;
  final JobQueue queue;
  final EventBus events;
  final String? embeddedPlatform;
  final String? bootstrapToken;
  final CleanupScheduler _cleanupScheduler;
  final AutoUpdateScheduler _autoUpdateScheduler;
  final BarkClient _barkClient;
  final WebDavClient _webDavClient;
  bool _closed = false;

  WebServerRuntime._({
    required this.server,
    required this.store,
    required this.queue,
    required this.events,
    required this.embeddedPlatform,
    required this.bootstrapToken,
    required CleanupScheduler cleanupScheduler,
    required AutoUpdateScheduler autoUpdateScheduler,
    required BarkClient barkClient,
    required WebDavClient webDavClient,
  }) : _cleanupScheduler = cleanupScheduler,
       _autoUpdateScheduler = autoUpdateScheduler,
       _barkClient = barkClient,
       _webDavClient = webDavClient;

  Uri get baseUri {
    final address = server.address;
    final host = address.isLoopback || address.type == InternetAddressType.IPv6
        ? InternetAddress.loopbackIPv4.address
        : address.address;
    return Uri(scheme: 'http', host: host, port: server.port);
  }

  Uri? get bootstrapUri =>
      bootstrapToken == null ? null : baseUri.resolve('/api/native/bootstrap');

  static Future<WebServerRuntime> start({
    required String dataDir,
    required String webRoot,
    String host = '127.0.0.1',
    int port = 0,
    String adminPassword = 'admin',
    bool secureCookies = false,
    int maxBatchSize = 100,
    String? embeddedPlatform,
    Duration bootstrapTtl = const Duration(seconds: 60),
  }) async {
    configureLogger(dataDir: dataDir);
    final store = JobStore(dataDir);
    await store.load();
    final webDavConfigStore = WebDavConfigStore(dataDir);
    final cleanupConfigStore = CleanupConfigStore(dataDir);
    final autoUpdateConfigStore = AutoUpdateConfigStore(dataDir);
    final webDavClient = WebDavClient();
    final barkClient = BarkClient();
    final events = EventBus();
    final queue = JobQueue(
      store: store,
      events: events,
      barkClient: barkClient,
      webDavConfigStore: webDavConfigStore,
      webDavClient: webDavClient,
      maxBatchSize: maxBatchSize,
    );
    final sessions = SessionStore(
      adminPassword: adminPassword,
      secureCookies: secureCookies,
    );
    final autoUpdateService = AutoUpdateService(
      configStore: autoUpdateConfigStore,
      store: store,
      queue: queue,
      webDavConfigStore: webDavConfigStore,
      webDavClient: webDavClient,
    );
    final bootstrapToken = embeddedPlatform == null ? null : _randomToken();
    final app = WebApp(
      store: store,
      queue: queue,
      events: events,
      sessions: sessions,
      webRoot: webRoot,
      webDavConfigStore: webDavConfigStore,
      webDavClient: webDavClient,
      cleanupConfigStore: cleanupConfigStore,
      autoUpdateConfigStore: autoUpdateConfigStore,
      autoUpdateService: autoUpdateService,
      embeddedPlatform: embeddedPlatform,
      nativeBootstrapToken: bootstrapToken,
      nativeBootstrapExpiresAt: embeddedPlatform == null
          ? null
          : DateTime.now().add(bootstrapTtl),
    );
    final cleanupScheduler = CleanupScheduler(
      configStore: cleanupConfigStore,
      queue: queue,
    );
    final autoUpdateScheduler = AutoUpdateScheduler(
      configStore: autoUpdateConfigStore,
      service: autoUpdateService,
    );

    await queue.resumeQueuedJobs();
    cleanupScheduler.start();
    autoUpdateScheduler.start();
    try {
      final server = await shelf_io.serve(app.handler, host, port);
      return WebServerRuntime._(
        server: server,
        store: store,
        queue: queue,
        events: events,
        embeddedPlatform: embeddedPlatform,
        bootstrapToken: bootstrapToken,
        cleanupScheduler: cleanupScheduler,
        autoUpdateScheduler: autoUpdateScheduler,
        barkClient: barkClient,
        webDavClient: webDavClient,
      );
    } catch (_) {
      cleanupScheduler.stop();
      autoUpdateScheduler.stop();
      barkClient.close();
      webDavClient.close();
      await events.close();
      closeLogger();
      rethrow;
    }
  }

  /// Returns an output only when [uri] belongs to this runtime and exactly
  /// matches `/api/jobs/{id}/files/{file}`.
  File? resolveOutputFileFromUri(Uri uri) {
    if (!isOutputDownloadUri(uri)) {
      return null;
    }
    final segments = uri.pathSegments;
    return resolveOutputFile(segments[2], segments[4]);
  }

  bool isOutputDownloadUri(Uri uri) {
    if (uri.scheme != baseUri.scheme ||
        uri.host != baseUri.host ||
        uri.port != baseUri.port) {
      return false;
    }
    final segments = uri.pathSegments;
    if (segments.length != 5 ||
        segments[0] != 'api' ||
        segments[1] != 'jobs' ||
        segments[3] != 'files') {
      return false;
    }
    return true;
  }

  File? resolveOutputFile(String jobId, String fileName) {
    if (jobId.isEmpty ||
        fileName.isEmpty ||
        fileName != path.basename(fileName) ||
        fileName.contains('/') ||
        fileName.contains('\\')) {
      return null;
    }
    final job = store.find(jobId);
    if (job == null || !job.outputFiles.contains(fileName)) {
      return null;
    }
    final file = store.outputFileFor(jobId, fileName);
    return file.existsSync() ? file : null;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _cleanupScheduler.stop();
    _autoUpdateScheduler.stop();
    await server.close(force: true);
    await store.save();
    _barkClient.close();
    _webDavClient.close();
    await events.close();
    closeLogger();
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
