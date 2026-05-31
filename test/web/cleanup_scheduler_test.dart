import 'dart:io';

import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/cleanup_config.dart';
import 'package:bili_novel_packer/web/cleanup_scheduler.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test("cleanup scheduler does nothing when disabled", () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 5, 31, 12);
    final job = _job(
      "old-success",
      "succeeded",
      createdAt: now.subtract(const Duration(days: 8)),
      finishedAt: now.subtract(const Duration(days: 8)),
      outputFiles: ["book.epub"],
    );
    await fixture.store.addAll([job]);
    await _writeOutput(fixture.store, job, "book.epub");

    final deleted = await fixture.scheduler.runOnce(now: now);

    expect(deleted, 0);
    expect(fixture.store.find(job.id), isNotNull);
    expect(
        await Directory(fixture.store.outputDirFor(job.id)).exists(), isTrue);
  });

  test("cleanup scheduler removes expired terminal jobs when enabled",
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 5, 31, 12);
    await fixture.cleanupConfigStore.save(const CleanupConfig(
      enabled: true,
      retentionDays: 7,
    ));
    final oldJob = _job(
      "old-success",
      "succeeded",
      createdAt: now.subtract(const Duration(days: 8)),
      finishedAt: now.subtract(const Duration(days: 8)),
      outputFiles: ["old.epub"],
    );
    final recentJob = _job(
      "recent-success",
      "succeeded",
      createdAt: now.subtract(const Duration(days: 2)),
      finishedAt: now.subtract(const Duration(days: 2)),
      outputFiles: ["recent.epub"],
    );
    await fixture.store.addAll([oldJob, recentJob]);
    await _writeOutput(fixture.store, oldJob, "old.epub");
    await _writeOutput(fixture.store, recentJob, "recent.epub");

    final deleted = await fixture.scheduler.runOnce(now: now);

    expect(deleted, 1);
    expect(fixture.store.find(oldJob.id), isNull);
    expect(fixture.store.find(recentJob.id), isNotNull);
    expect(
      await Directory(fixture.store.outputDirFor(oldJob.id)).exists(),
      isFalse,
    );
    expect(
      await Directory(fixture.store.outputDirFor(recentJob.id)).exists(),
      isTrue,
    );
  });
}

Future<_Fixture> _createFixture() async {
  final dir = await Directory.systemTemp.createTemp("bnp_cleanup_scheduler_");
  final store = JobStore(dir.path);
  await store.load();
  final cleanupConfigStore = CleanupConfigStore(dir.path);
  final queue = JobQueue(
    store: store,
    events: EventBus(),
    barkClient: BarkClient(),
    webDavConfigStore: WebDavConfigStore(dir.path),
    webDavClient: WebDavClient(),
    maxBatchSize: 100,
  );
  final scheduler = CleanupScheduler(
    configStore: cleanupConfigStore,
    queue: queue,
  );
  return _Fixture(dir, store, cleanupConfigStore, scheduler);
}

DownloadJob _job(
  String id,
  String status, {
  required DateTime createdAt,
  DateTime? finishedAt,
  List<String>? outputFiles,
}) {
  return DownloadJob(
    id: id,
    sourceId: 1,
    url: "https://example.test/novel/1.html",
    request: const JobRequest(
      urlTemplate: "https://example.test/novel/{id}.html",
      rangeText: "1",
      volumeRangeText: "",
      combineVolume: false,
      addChapterTitle: false,
      barkConfig: BarkConfig(),
    ),
    status: status,
    createdAt: createdAt,
    finishedAt: finishedAt,
    outputFiles: outputFiles,
  );
}

Future<void> _writeOutput(
  JobStore store,
  DownloadJob job,
  String fileName,
) async {
  final dir = Directory(store.outputDirFor(job.id));
  await dir.create(recursive: true);
  await File(path.join(dir.path, fileName)).writeAsString("epub");
}

class _Fixture {
  final Directory dir;
  final JobStore store;
  final CleanupConfigStore cleanupConfigStore;
  final CleanupScheduler scheduler;

  _Fixture(
    this.dir,
    this.store,
    this.cleanupConfigStore,
    this.scheduler,
  );

  Future<void> dispose() async {
    scheduler.stop();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
