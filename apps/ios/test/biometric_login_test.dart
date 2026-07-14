import 'package:bili_novel_packer_ios/biometric_service.dart';
import 'package:bili_novel_packer_ios/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saved Face ID credentials trigger automatic login', (
    tester,
  ) async {
    final biometric = _FakeBiometricService();
    String? loggedInPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          biometric: biometric,
          allowBiometricLogin: true,
          serverUri: Uri.parse('https://server.example.com'),
          onLogin: (password) async => loggedInPassword = password,
          onChangeServer: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 1);
    expect(loggedInPassword, 'stored-password');
  });

  testWidgets('first login requires password even if Keychain still has data', (
    tester,
  ) async {
    final biometric = _FakeBiometricService();
    String? loggedInPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          biometric: biometric,
          serverUri: Uri.parse('https://server.example.com'),
          onLogin: (password) async => loggedInPassword = password,
          onChangeServer: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 0);
    expect(find.text('使用 Face ID 登录'), findsNothing);
    await tester.enterText(find.byType(TextField), 'manual-password');
    await tester.tap(find.text('登录'));
    await tester.pump();

    expect(loggedInPassword, 'manual-password');
    expect(biometric.savePasswordCalls, 0);
  });
}

class _FakeBiometricService extends BiometricService {
  int authenticateCalls = 0;
  int savePasswordCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> hasSavedPassword() async => true;

  @override
  Future<bool> authenticate() async {
    authenticateCalls++;
    return true;
  }

  @override
  Future<String?> readPassword() async => 'stored-password';

  @override
  Future<void> savePassword(String password) async {
    savePasswordCalls++;
  }
}
