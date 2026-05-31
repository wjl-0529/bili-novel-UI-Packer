import 'dart:io';

import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:bili_novel_packer/web/auto_update_scheduler.dart';
import 'package:bili_novel_packer/web/auto_update_service.dart';
import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:test/test.dart';

void main() {
  test("scheduler does nothing when disabled", () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);

    final result = await fixture.scheduler.runDue(
      now: DateTime(2026, 5, 31, 4),
    );

    expect(result, isNull);
    expect((await fixture.configStore.load()).lastRunAt, isNull);
  });

  test("scheduler backfills after daily time and runs once per day", () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    await fixture.configStore.save(const AutoUpdateConfig(
      enabled: true,
      dailyTime: "03:00",
    ));
    final firstRunAt = DateTime(2026, 5, 31, 4);

    final first = await fixture.scheduler.runDue(now: firstRunAt);
    final second = await fixture.scheduler.runDue(
      now: DateTime(2026, 5, 31, 5),
    );

    expect(first, isNotNull);
    expect(first?.checked, 0);
    expect(second, isNull);
    expect((await fixture.configStore.load()).lastRunAt, firstRunAt);
  });

  test("scheduler waits until configured time", () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    await fixture.configStore.save(const AutoUpdateConfig(
      enabled: true,
      dailyTime: "21:30",
    ));

    final result = await fixture.scheduler.runDue(
      now: DateTime(2026, 5, 31, 21, 29),
    );

    expect(result, isNull);
    expect((await fixture.configStore.load()).lastRunAt, isNull);
  });
}

Future<_Fixture> _createFixture() async {
  final dir =
      await Directory.systemTemp.createTemp("bnp_auto_update_scheduler_");
  final store = JobStore(dir.path);
  await store.load();
  final configStore = AutoUpdateConfigStore(dir.path);
  final webDavConfigStore = WebDavConfigStore(dir.path);
  final webDavClient = WebDavClient();
  final queue = JobQueue(
    store: store,
    events: EventBus(),
    barkClient: BarkClient(),
    webDavConfigStore: webDavConfigStore,
    webDavClient: webDavClient,
    maxBatchSize: 100,
  );
  final service = AutoUpdateService(
    configStore: configStore,
    store: store,
    queue: queue,
    webDavConfigStore: webDavConfigStore,
    webDavClient: webDavClient,
  );
  final scheduler = AutoUpdateScheduler(
    configStore: configStore,
    service: service,
  );
  return _Fixture(dir, configStore, scheduler);
}

class _Fixture {
  final Directory dir;
  final AutoUpdateConfigStore configStore;
  final AutoUpdateScheduler scheduler;

  _Fixture(this.dir, this.configStore, this.scheduler);

  Future<void> dispose() async {
    scheduler.stop();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
