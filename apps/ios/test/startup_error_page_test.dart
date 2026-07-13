import 'package:bili_novel_packer_ios/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes supported server origins', () {
    expect(
      normalizeServerUri(' http://192.168.31.56:8080/path?q=1 '),
      Uri.parse('http://192.168.31.56:8080'),
    );
    expect(
      normalizeServerUri('https://book.jinhub.cn'),
      Uri.parse(remoteServerUri),
    );
    expect(normalizeServerUri('ftp://example.com'), isNull);
    expect(normalizeServerUri('https://user@example.com'), isNull);
  });

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
    String? connectedUrl;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupErrorPage(
          error: StateError('boom'),
          serverUrl: remoteServerUri,
          onConnect: (value) async => connectedUrl = value,
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('无法连接服务器'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);

    await tester.enterText(find.byType(TextField), 'http://192.168.31.56:8080');
    await tester.tap(find.text('连接'));
    await tester.pump();
    expect(connectedUrl, 'http://192.168.31.56:8080');
  });

  testWidgets('server dialog returns a normalized server origin', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showDialog<String>(
                context: context,
                builder: (context) =>
                    const ServerAddressDialog(initialValue: remoteServerUri),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://book.jinhub.cn/path?from=ios',
    );
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(selected, remoteServerUri);
  });
}
