import 'dart:io';

import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test("deleteOutputs removes files and keeps the job record", () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);

    final job = _job("done", 1, "succeeded", outputFiles: ["book.epub"]);
    await fixture.store.addAll([job]);
    await _writeOutput(fixture.store, job, "book.epub");

    final nextJob = await fixture.queue.deleteOutputs(job.id);

    expect(nextJob, isNotNull);
    expect(nextJob?.outputFiles, isEmpty);
    expect(fixture.store.find(job.id), isNotNull);
    expect(
        await Directory(fixture.store.outputDirFor(job.id)).exists(), isFalse);
    expect(nextJob?.logs.last, contains("输出文件已清理"));
  });

  test("cleanupCompleted only removes terminal jobs", () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);

    final jobs = [
      _job("success", 1, "succeeded", outputFiles: ["success.epub"]),
      _job("failed", 2, "failed", outputFiles: ["failed.epub"]),
      _job("canceled", 3, "canceled", outputFiles: ["canceled.epub"]),
      _job("running", 4, "running", outputFiles: ["running.epub"]),
      _job("queued", 5, "queued"),
      _job("canceling", 6, "canceling"),
    ];
    await fixture.store.addAll(jobs);
    for (final job in jobs.where((job) => job.outputFiles.isNotEmpty)) {
      await _writeOutput(fixture.store, job, job.outputFiles.first);
    }

    final deleted = await fixture.queue.cleanupCompleted();

    expect(deleted, 3);
    expect(fixture.store.find("success"), isNull);
    expect(fixture.store.find("failed"), isNull);
    expect(fixture.store.find("canceled"), isNull);
    expect(fixture.store.find("running"), isNotNull);
    expect(fixture.store.find("queued"), isNotNull);
    expect(fixture.store.find("canceling"), isNotNull);
    expect(
      await Directory(fixture.store.outputDirFor("running")).exists(),
      isTrue,
    );
  });

  test("cleanupCompletedOlderThan only removes expired terminal jobs",
      () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 5, 31, 12);
    final cutoff = now.subtract(const Duration(days: 7));
    final expired = now.subtract(const Duration(days: 8));
    final recent = now.subtract(const Duration(days: 2));

    final jobs = [
      _job(
        "old-success",
        1,
        "succeeded",
        outputFiles: ["old-success.epub"],
        finishedAt: expired,
      ),
      _job(
        "old-canceled",
        2,
        "canceled",
        outputFiles: ["old-canceled.epub"],
        createdAt: expired,
      ),
      _job(
        "recent-failed",
        3,
        "failed",
        outputFiles: ["recent-failed.epub"],
        finishedAt: recent,
      ),
      _job(
        "old-running",
        4,
        "running",
        outputFiles: ["old-running.epub"],
        createdAt: expired,
      ),
      _job(
        "old-queued",
        5,
        "queued",
        createdAt: expired,
      ),
      _job(
        "old-canceling",
        6,
        "canceling",
        createdAt: expired,
      ),
    ];
    await fixture.store.addAll(jobs);
    for (final job in jobs.where((job) => job.outputFiles.isNotEmpty)) {
      await _writeOutput(fixture.store, job, job.outputFiles.first);
    }

    final deleted = await fixture.queue.cleanupCompletedOlderThan(cutoff);

    expect(deleted, 2);
    expect(fixture.store.find("old-success"), isNull);
    expect(fixture.store.find("old-canceled"), isNull);
    expect(fixture.store.find("recent-failed"), isNotNull);
    expect(fixture.store.find("old-running"), isNotNull);
    expect(fixture.store.find("old-queued"), isNotNull);
    expect(fixture.store.find("old-canceling"), isNotNull);
    expect(
      await Directory(fixture.store.outputDirFor("old-success")).exists(),
      isFalse,
    );
    expect(
      await Directory(fixture.store.outputDirFor("old-canceled")).exists(),
      isFalse,
    );
    expect(
      await Directory(fixture.store.outputDirFor("recent-failed")).exists(),
      isTrue,
    );
    expect(
      await Directory(fixture.store.outputDirFor("old-running")).exists(),
      isTrue,
    );
  });
}

Future<_Fixture> _createFixture() async {
  final dir = await Directory.systemTemp.createTemp("bnp_job_queue_test_");
  final store = JobStore(dir.path);
  await store.load();
  final queue = JobQueue(
    store: store,
    events: EventBus(),
    barkClient: BarkClient(),
    webDavConfigStore: WebDavConfigStore(dir.path),
    webDavClient: WebDavClient(),
    maxBatchSize: 100,
  );
  return _Fixture(dir, store, queue);
}

DownloadJob _job(
  String id,
  int sourceId,
  String status, {
  List<String>? outputFiles,
  DateTime? createdAt,
  DateTime? finishedAt,
}) {
  return DownloadJob(
    id: id,
    sourceId: sourceId,
    url: "https://example.test/novel/$sourceId.html",
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
  final JobQueue queue;

  _Fixture(this.dir, this.store, this.queue);

  Future<void> dispose() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
