import 'dart:io';

import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:bili_novel_packer/web/auto_update_scheduler.dart';
import 'package:bili_novel_packer/web/auto_update_service.dart';
import 'package:bili_novel_packer/web/cleanup_config.dart';
import 'package:bili_novel_packer/web/cleanup_scheduler.dart';
import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/session_store.dart';
import 'package:bili_novel_packer/web/web_app.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final env = Platform.environment;
  final dataDir = env["DATA_DIR"] ?? "data";
  final webRoot = env["WEB_ROOT"] ?? "web/dist";
  final port = int.tryParse(env["PORT"] ?? "") ?? 8080;
  final host = env["HOST"] ?? "0.0.0.0";
  final adminPassword = env["ADMIN_PASSWORD"] ?? "admin";
  final secureCookies =
      (env["COOKIE_SECURE"] ?? "false").toLowerCase() == "true";
  final maxBatchSize = int.tryParse(env["MAX_BATCH_SIZE"] ?? "") ?? 100;

  final store = JobStore(dataDir);
  await store.load();
  final webDavConfigStore = WebDavConfigStore(dataDir);
  final cleanupConfigStore = CleanupConfigStore(dataDir);
  final autoUpdateConfigStore = AutoUpdateConfigStore(dataDir);
  final webDavClient = WebDavClient();
  final events = EventBus();
  final queue = JobQueue(
    store: store,
    events: events,
    barkClient: BarkClient(),
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

  final server = await shelf_io.serve(app.handler, host, port);
  print("轻小说打包器 Web 控制台已启动：${server.address.host}:${server.port}");
  if (adminPassword == "admin") {
    print("警告：ADMIN_PASSWORD 正在使用开发默认值。");
  }
}
