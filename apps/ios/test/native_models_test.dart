import 'package:bili_novel_packer_ios/native_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('job request serializes the server contract', () {
    const request = JobRequestModel(
      urlTemplate: 'https://www.bilinovel.com/novel/{id}.html',
      rangeText: '1-3',
      volumeRangeText: '1-2',
      combineVolume: true,
      addChapterTitle: true,
    );

    expect(request.toJson(), {
      'urlTemplate': 'https://www.bilinovel.com/novel/{id}.html',
      'rangeText': '1-3',
      'volumeRangeText': '1-2',
      'combineVolume': true,
      'addChapterTitle': true,
      'barkConfig': {
        'enabled': false,
        'serverUrl': '',
        'deviceKey': '',
        'events': {
          'start': false,
          'success': true,
          'failure': true,
          'progress': false,
          'update': true,
        },
        'progressThrottleSeconds': 300,
      },
    });
  });

  test('download job parses progress, files, and logs', () {
    final job = DownloadJobModel.fromJson({
      'id': 'job-1',
      'sourceId': 12,
      'url': 'https://example.com/12',
      'request': {'urlTemplate': 'https://example.com/{id}', 'rangeText': '12'},
      'status': 'succeeded',
      'progress': 1,
      'message': '完成',
      'createdAt': '2026-07-13T12:00:00.000Z',
      'outputFiles': ['book.epub'],
      'logs': ['done'],
    });

    expect(job.id, 'job-1');
    expect(job.progress, 1);
    expect(job.outputFiles, ['book.epub']);
    expect(job.logs, ['done']);
  });

  test('WebDAV and automatic update configs preserve API fields', () {
    expect(const WebDavConfigModel().basePath, isEmpty);
    final webDav = WebDavConfigModel.fromJson({
      'enabled': true,
      'serverUrl': 'https://dav.example.com',
      'username': 'reader',
      'basePath': '/books',
      'hasPassword': true,
    });
    final autoUpdate = AutoUpdateConfigModel.fromJson({
      'enabled': true,
      'dailyTime': '04:30',
      'items': [
        {'jobId': 'job-1', 'enabled': true, 'lastStatus': 'unchanged'},
      ],
    });

    expect(webDav.enabled, isTrue);
    expect(webDav.hasPassword, isTrue);
    expect(webDav.toJson()['password'], '');
    expect(autoUpdate.dailyTime, '04:30');
    expect(autoUpdate.items.single.jobId, 'job-1');
    expect(autoUpdate.items.single.lastStatus, 'unchanged');
  });

  test('novel preview parses metadata used by native selection', () {
    final preview = NovelPreviewModel.fromJson({
      'sourceId': 42,
      'id': '42',
      'url': 'https://example.com/42',
      'sourceName': '哔哩轻小说',
      'title': '测试小说',
      'author': '作者',
      'status': '连载中',
      'tags': ['奇幻'],
      'volumeCount': 3,
      'chapterCount': 28,
    });

    expect(preview.sourceId, 42);
    expect(preview.tags, ['奇幻']);
    expect(preview.volumeCount, 3);
    expect(preview.chapterCount, 28);
  });
}
