import 'package:bili_novel_packer/web/bark_message.dart';
import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/job.dart';
import 'package:test/test.dart';

JobRequest _request() {
  return const JobRequest(
    urlTemplate: 'https://example.com/novel/{id}',
    rangeText: '1',
    volumeRangeText: '',
    combineVolume: false,
    addChapterTitle: false,
    barkConfig: BarkConfig(enabled: true),
  );
}

void main() {
  test('includes novel title when available', () {
    final job = DownloadJob(
      id: 'job-1',
      sourceId: 42,
      url: 'https://example.com/novel/42',
      request: _request(),
      title: '测试小说',
    );

    expect(barkTitle(job, '下载完成'), '下载完成：《测试小说》');
    expect(barkBody(job, '已完成，生成 1 个 EPUB 文件'), contains('《测试小说》'));
    expect(barkBody(job, '已完成，生成 1 个 EPUB 文件'), contains(job.url));
  });

  test('falls back to source id when title is missing', () {
    final job = DownloadJob(
      id: 'job-2',
      sourceId: 7,
      url: 'https://example.com/novel/7',
      request: _request(),
    );

    expect(barkTitle(job, '下载开始'), '下载开始：小说 #7');
    expect(barkBody(job, '已开始下载'), contains('小说 #7'));
  });
}
