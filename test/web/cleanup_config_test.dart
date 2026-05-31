import 'dart:io';

import 'package:bili_novel_packer/web/cleanup_config.dart';
import 'package:test/test.dart';

void main() {
  test("cleanup config defaults to disabled with seven day retention",
      () async {
    final dir = await Directory.systemTemp.createTemp("bnp_cleanup_config_");
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final store = CleanupConfigStore(dir.path);
    final config = await store.load();

    expect(config.enabled, isFalse);
    expect(config.retentionDays, 7);
  });

  test("cleanup config saves and clamps retention days", () async {
    final dir = await Directory.systemTemp.createTemp("bnp_cleanup_config_");
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final store = CleanupConfigStore(dir.path);
    final saved = await store.saveFromPayload({
      "enabled": true,
      "retentionDays": 0,
    });
    final loaded = await store.load();

    expect(saved.enabled, isTrue);
    expect(saved.retentionDays, 1);
    expect(loaded.enabled, isTrue);
    expect(loaded.retentionDays, 1);
  });
}
