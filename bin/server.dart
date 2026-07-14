import 'dart:io';

import 'package:bili_novel_packer/web/server_runtime.dart';

Future<void> main() async {
  final env = Platform.environment;
  final dataDir = env['DATA_DIR'] ?? 'data';
  final webRoot = env['WEB_ROOT'] ?? 'web/dist';
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final host = env['HOST'] ?? '0.0.0.0';
  final adminPassword = env['ADMIN_PASSWORD'] ?? 'admin';
  final secureCookies =
      (env['COOKIE_SECURE'] ?? 'false').toLowerCase() == 'true';
  final maxBatchSize = int.tryParse(env['MAX_BATCH_SIZE'] ?? '') ?? 100;

  final runtime = await WebServerRuntime.start(
    dataDir: dataDir,
    webRoot: webRoot,
    host: host,
    port: port,
    adminPassword: adminPassword,
    secureCookies: secureCookies,
    maxBatchSize: maxBatchSize,
  );
  stdout.writeln('轻小说打包器 Web 控制台已启动：${runtime.baseUri}');
  if (adminPassword == 'admin') {
    stdout.writeln('警告：ADMIN_PASSWORD 正在使用开发默认值。');
  }
}
