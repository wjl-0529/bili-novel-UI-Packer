import 'package:bili_novel_packer_ios/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    expect(find.text('本地服务启动失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });
}
