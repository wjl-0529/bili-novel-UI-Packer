import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/light_novel/base/light_novel_source.dart';
import 'package:bili_novel_packer/novel_packer.dart';
import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/event_bus.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_queue.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/webdav.dart';
import 'package:html/dom.dart';
import 'package:test/test.dart';

void main() {
  test('cancel keeps the queue slot until the active worker exits', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final jobs = await fixture.queue.submit(_request());

    await fixture.source.waitUntilStarted(1);
    await fixture.queue.cancel(jobs[0].id);

    expect(fixture.store.find(jobs[0].id)?.status, 'canceling');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fixture.source.startedIds, isNot(contains(2)));
    expect(fixture.store.find(jobs[1].id)?.status, 'queued');

    fixture.source.release(1);
    await fixture.source.waitUntilStarted(2);
    expect(fixture.store.find(jobs[0].id)?.status, 'canceled');

    fixture.source.release(2);
    await _waitUntil(
      () => fixture.store.find(jobs[1].id)?.status == 'succeeded',
    );
  });

  test('delete keeps a tombstone until the active worker exits', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final jobs = await fixture.queue.submit(_request());

    await fixture.source.waitUntilStarted(1);
    await fixture.queue.delete(jobs[0].id);

    expect(fixture.store.find(jobs[0].id), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fixture.source.startedIds, isNot(contains(2)));

    fixture.source.release(1);
    await fixture.source.waitUntilStarted(2);
    expect(
      await Directory(fixture.store.outputDirFor(jobs[0].id)).exists(),
      isFalse,
    );

    fixture.source.release(2);
    await _waitUntil(
      () => fixture.store.find(jobs[1].id)?.status == 'succeeded',
    );
  });
}

JobRequest _request() {
  return const JobRequest(
    urlTemplate: 'https://fake.test/novel/{id}.html',
    rangeText: '1-2',
    volumeRangeText: '',
    combineVolume: false,
    addChapterTitle: false,
    barkConfig: BarkConfig(),
  );
}

Future<_Fixture> _createFixture() async {
  final dir = await Directory.systemTemp.createTemp('bnp_cancel_test_');
  final store = JobStore(dir.path);
  await store.load();
  final source = _BlockingSource();
  final originalSources = List<LightNovelSource>.from(NovelPacker.sources);
  NovelPacker.sources.insert(0, source);
  final queue = JobQueue(
    store: store,
    events: EventBus(),
    barkClient: BarkClient(),
    webDavConfigStore: WebDavConfigStore(dir.path),
    webDavClient: WebDavClient(),
    maxBatchSize: 100,
  );
  return _Fixture(dir, store, queue, source, originalSources);
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for queue state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Fixture {
  final Directory dir;
  final JobStore store;
  final JobQueue queue;
  final _BlockingSource source;
  final List<LightNovelSource> originalSources;

  _Fixture(this.dir, this.store, this.queue, this.source, this.originalSources);

  Future<void> dispose() async {
    source.releaseAll();
    NovelPacker.sources
      ..clear()
      ..addAll(originalSources);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

class _BlockingSource implements LightNovelSource {
  final Map<int, Completer<void>> _gates = {};
  final Map<int, Completer<void>> _started = {};
  final Set<int> startedIds = {};

  @override
  String get name => 'fake';

  @override
  String get sourceUrl => 'https://fake.test';

  @override
  bool supportUrl(String url) => url.startsWith('$sourceUrl/');

  @override
  Future<Novel> getNovel(String url) async {
    final match = RegExp(r'/(\d+)\.html$').firstMatch(url)!;
    final id = int.parse(match.group(1)!);
    startedIds.add(id);
    final started = _started.putIfAbsent(id, Completer<void>.new);
    if (!started.isCompleted) {
      started.complete();
    }
    await _gates.putIfAbsent(id, Completer<void>.new).future;
    return Novel()
      ..url = url
      ..id = '$id'
      ..title = 'Novel $id'
      ..author = 'Author'
      ..status = 'complete'
      ..publisher = 'test';
  }

  Future<void> waitUntilStarted(int id) {
    return _started
        .putIfAbsent(id, Completer<void>.new)
        .future
        .timeout(const Duration(seconds: 5));
  }

  void release(int id) {
    final gate = _gates.putIfAbsent(id, Completer<void>.new);
    if (!gate.isCompleted) {
      gate.complete();
    }
  }

  void releaseAll() {
    for (final gate in _gates.values) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  @override
  Future<Catalog> getNovelCatalog(Novel novel) async {
    final catalog = Catalog(novel);
    catalog.volumes.add(Volume('Volume 1', catalog));
    return catalog;
  }

  @override
  Future<Document> getNovelChapter(Chapter chapter) async {
    return Document.html(LightNovelSource.html);
  }

  @override
  Future<Uint8List> getImage(String src) async => Uint8List(0);
}
