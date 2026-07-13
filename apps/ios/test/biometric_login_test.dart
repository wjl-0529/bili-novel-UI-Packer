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
}

class _FakeBiometricService extends BiometricService {
  int authenticateCalls = 0;

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
}
