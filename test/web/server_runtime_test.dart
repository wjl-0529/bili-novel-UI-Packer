import 'dart:convert';
import 'dart:io';

import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:bili_novel_packer/web/job_store.dart';
import 'package:bili_novel_packer/web/server_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('embedded runtime bootstraps once and closes its random port', () async {
    final root = await Directory.systemTemp.createTemp('bnp-runtime-');
    addTearDown(() => root.delete(recursive: true));
    final webRoot = Directory('${root.path}/web')..createSync(recursive: true);
    File('${webRoot.path}/index.html').writeAsStringSync('<h1>ready</h1>');
    final dataDir = '${root.path}/data';
    final seedStore = JobStore(dataDir);
    await seedStore.load();
    final runningJob = _job('was-running')
      ..status = 'running'
      ..progress = 0.42;
    final queuedJob = _job('was-queued')..status = 'queued';
    final completedJob = _job('was-completed')..status = 'succeeded';
    await seedStore.addAll([runningJob, queuedJob, completedJob]);

    final runtime = await WebServerRuntime.start(
      dataDir: dataDir,
      webRoot: webRoot.path,
      embeddedPlatform: 'ios',
    );
    addTearDown(runtime.close);
    expect(runtime.server.address.isLoopback, isTrue);
    expect(runtime.server.port, greaterThan(0));
    expect(runtime.store.find('was-running')?.status, 'paused');
    expect(runtime.store.find('was-running')?.progress, runningJob.progress);
    expect(runtime.store.find('was-queued')?.status, 'paused');
    expect(runtime.store.find('was-completed')?.status, 'succeeded');
    expect(
      runtime.store.find('was-running')?.logs.last,
      contains('未自动重新下载'),
    );

    final client = http.Client();
    addTearDown(client.close);
    final runtimeResponse = await client.get(
      runtime.baseUri.resolve('/api/runtime'),
    );
    expect(runtimeResponse.statusCode, 200);
    expect(jsonDecode(runtimeResponse.body), {
      'embedded': true,
      'platform': 'ios',
    });
    expect(
      (await client.get(runtime.baseUri.resolve('/api/jobs'))).statusCode,
      401,
    );

    final badBootstrap = await client.post(
      runtime.bootstrapUri!,
      headers: {'authorization': 'Bearer wrong'},
    );
    expect(badBootstrap.statusCode, 401);

    final bootstrapRequest = http.Request('POST', runtime.bootstrapUri!)
      ..followRedirects = false
      ..headers['authorization'] = 'Bearer ${runtime.bootstrapToken}';
    final bootstrapResponse = await client.send(bootstrapRequest);
    expect(bootstrapResponse.statusCode, 302);
    expect(bootstrapResponse.headers['location'], '/');
    final cookie = bootstrapResponse.headers['set-cookie']!.split(';').first;

    final reusedRequest = http.Request('POST', runtime.bootstrapUri!)
      ..followRedirects = false
      ..headers['authorization'] = 'Bearer ${runtime.bootstrapToken}';
    expect((await client.send(reusedRequest)).statusCode, 401);
    expect(
      (await client.get(
        runtime.baseUri.resolve('/api/jobs'),
        headers: {'cookie': cookie},
      )).statusCode,
      200,
    );

    final job = _job('job-1');
    job.outputFiles = ['novel.epub'];
    await runtime.store.addAll([job]);
    final output = runtime.store.outputFileFor(job.id, 'novel.epub');
    await output.parent.create(recursive: true);
    await output.writeAsBytes([1, 2, 3]);
    final fileUri = runtime.baseUri.resolve('/api/jobs/job-1/files/novel.epub');
    expect(runtime.isOutputDownloadUri(fileUri), isTrue);
    expect(runtime.resolveOutputFileFromUri(fileUri)?.path, output.path);

    final exportResponse = await client.post(
      runtime.baseUri.resolve('/api/native/exports'),
      headers: {
        'content-type': 'application/json',
        'cookie': cookie,
      },
      body: jsonEncode({'jobId': job.id, 'fileName': 'novel.epub'}),
    );
    expect(exportResponse.statusCode, 201);
    final exportJson = jsonDecode(exportResponse.body) as Map<String, dynamic>;
    final exportUri = runtime.baseUri.resolve(exportJson['url'] as String);
    final exportedFile = await client.get(exportUri);
    expect(exportedFile.statusCode, 200);
    expect(exportedFile.bodyBytes, [1, 2, 3]);
    expect((await client.get(exportUri)).statusCode, 404);

    expect(
      runtime.isOutputDownloadUri(
        runtime.baseUri.resolve('/api/jobs/job-1/files/a/b.epub'),
      ),
      isFalse,
    );
    expect(runtime.resolveOutputFile('job-1', '../novel.epub'), isNull);
    expect(
      runtime.resolveOutputFileFromUri(
        Uri.parse('https://example.com/api/jobs/job-1/files/novel.epub'),
      ),
      isNull,
    );
    expect(runtime.resolveOutputFile('job-1', 'missing.epub'), isNull);

    final port = runtime.server.port;
    await runtime.close();
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
  });
}

DownloadJob _job(String id) {
  return DownloadJob(
    id: id,
    sourceId: 1,
    url: 'https://example.com/$id',
    request: const JobRequest(
      urlTemplate: 'https://example.com/{}',
      rangeText: '1',
      volumeRangeText: '',
      combineVolume: false,
      addChapterTitle: false,
      barkConfig: BarkConfig(),
    ),
  );
}
