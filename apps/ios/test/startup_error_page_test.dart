import 'package:bili_novel_packer_ios/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only output URLs from the configured server', () {
    final server = Uri.parse(remoteServerUri);
    expect(
      isRemoteOutputUri(
        server,
        Uri.parse('$remoteServerUri/api/jobs/job-1/files/book.epub'),
      ),
      isTrue,
    );
    expect(
      isRemoteOutputUri(
        server,
        Uri.parse('https://example.com/api/jobs/job-1/files/book.epub'),
      ),
      isFalse,
    );
    expect(
      isRemoteOutputUri(server, Uri.parse('$remoteServerUri/api/jobs')),
      isFalse,
    );
  });

  testWidgets('startup failure exposes a working retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupErrorPage(
          error: StateError('boom'),
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('无法连接服务器'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });
}
