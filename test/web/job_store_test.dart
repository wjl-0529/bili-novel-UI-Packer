import 'dart:io';

import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:test/test.dart';

void main() {
  test('loaded list and id index share the same job instance', () async {
    final dir = await Directory.systemTemp.createTemp('bnp_job_store_test_');
    addTearDown(() => dir.delete(recursive: true));
    final original = JobStore(dir.path);
    await original.load();
    await original.addAll([_job('job-1')]);

    final loaded = JobStore(dir.path);
    await loaded.load();
    final listJob = loaded.jobs.single;
    final indexedJob = loaded.find('job-1');

    expect(identical(listJob, indexedJob), isTrue);
    indexedJob!.status = 'succeeded';
    await loaded.save();

    final reloaded = JobStore(dir.path);
    await reloaded.load();
    expect(reloaded.find('job-1')?.status, 'succeeded');
  });

  test(
    'concurrent saves are serialized and keep the newest snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp('bnp_job_store_test_');
      addTearDown(() => dir.delete(recursive: true));
      final store = JobStore(dir.path);
      await store.load();
      final job = _job('job-1');
      await store.addAll([job]);

      final saves = <Future<void>>[];
      for (var i = 1; i <= 20; i++) {
        job.progress = i / 20;
        saves.add(store.save());
      }
      await Future.wait(saves);

      final reloaded = JobStore(dir.path);
      await reloaded.load();
      expect(reloaded.find('job-1')?.progress, 1);
      expect(
        Directory(dir.path).listSync().whereType<File>().where(
          (file) => file.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    },
  );
}

DownloadJob _job(String id) {
  return DownloadJob(
    id: id,
    sourceId: 1,
    url: 'https://example.test/novel/1.html',
    request: const JobRequest(
      urlTemplate: 'https://example.test/novel/{id}.html',
      rangeText: '1',
      volumeRangeText: '',
      combineVolume: false,
      addChapterTitle: false,
      barkConfig: BarkConfig(),
    ),
  );
}
