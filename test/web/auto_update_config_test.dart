import 'dart:io';

import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:test/test.dart';

void main() {
  test("auto update config defaults to disabled daily at 03:00", () async {
    final dir =
        await Directory.systemTemp.createTemp("bnp_auto_update_config_");
    addTearDown(() => dir.delete(recursive: true));
    final store = AutoUpdateConfigStore(dir.path);

    final config = await store.load();

    expect(config.enabled, isFalse);
    expect(config.dailyTime, "03:00");
    expect(config.lastRunAt, isNull);
    expect(config.items, isEmpty);
  });

  test("saveFromPayload filters jobs and preserves runtime fields", () async {
    final dir =
        await Directory.systemTemp.createTemp("bnp_auto_update_config_");
    addTearDown(() => dir.delete(recursive: true));
    final store = AutoUpdateConfigStore(dir.path);
    final checkedAt = DateTime(2026, 5, 31, 4);
    await store.save(AutoUpdateConfig(
      enabled: true,
      dailyTime: "02:30",
      lastRunAt: checkedAt,
      items: [
        AutoUpdateItem(
          jobId: "job-1",
          baselineFingerprint: "baseline",
          lastCheckedAt: checkedAt,
          lastStatus: "unchanged",
          lastMessage: "暂无更新",
        ),
      ],
    ));

    final saved = await store.saveFromPayload(
      {
        "enabled": true,
        "dailyTime": "7:05",
        "items": [
          {"jobId": "job-1", "enabled": false},
          {"jobId": "job-2", "enabled": true},
        ],
      },
      allowedJobIds: {"job-1"},
    );

    expect(saved.enabled, isTrue);
    expect(saved.dailyTime, "07:05");
    expect(saved.lastRunAt, checkedAt);
    expect(saved.items, hasLength(1));
    expect(saved.items.single.jobId, "job-1");
    expect(saved.items.single.enabled, isFalse);
    expect(saved.items.single.baselineFingerprint, "baseline");
    expect(saved.items.single.lastStatus, "unchanged");
  });

  test("invalid daily time falls back to default", () {
    expect(normalizeDailyTime("25:00"), "03:00");
    expect(normalizeDailyTime("bad"), "03:00");
    expect(normalizeDailyTime("9:08"), "09:08");
  });
}
