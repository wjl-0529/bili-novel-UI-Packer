import 'dart:async';
import 'dart:io';

import 'package:bili_novel_packer/web/server_runtime.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'web_asset_installer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovelPackerIosApp());
}

class NovelPackerIosApp extends StatelessWidget {
  const NovelPackerIosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻小说打包器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4f46e5)),
        useMaterial3: true,
      ),
      home: const IosShellPage(),
    );
  }
}

class IosShellPage extends StatefulWidget {
  const IosShellPage({super.key});

  @override
  State<IosShellPage> createState() => _IosShellPageState();
}

class _IosShellPageState extends State<IosShellPage> {
  WebServerRuntime? _runtime;
  WebViewController? _controller;
  Object? _startupError;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final oldRuntime = _runtime;
    _runtime = null;
    _controller = null;
    if (mounted) {
      setState(() => _startupError = null);
    }
    if (oldRuntime != null) {
      await oldRuntime.close();
    }
    try {
      final support = await getApplicationSupportDirectory();
      final webRoot = await installBundledWebAssets(support);
      final runtime = await WebServerRuntime.start(
        dataDir: path.join(support.path, 'data'),
        webRoot: webRoot.path,
        host: InternetAddress.loopbackIPv4.address,
        port: 0,
        embeddedPlatform: 'ios',
      );
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xfff8fafc))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) =>
                _handleNavigation(runtime, request),
          ),
        );
      await controller.loadRequest(
        runtime.bootstrapUri!,
        method: LoadRequestMethod.post,
        headers: {'Authorization': 'Bearer ${runtime.bootstrapToken}'},
      );
      if (!mounted) {
        await runtime.close();
        return;
      }
      setState(() {
        _runtime = runtime;
        _controller = controller;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _startupError = error);
      }
    }
  }

  FutureOr<NavigationDecision> _handleNavigation(
    WebServerRuntime runtime,
    NavigationRequest request,
  ) {
    final uri = Uri.tryParse(request.url);
    if (uri == null || !runtime.isOutputDownloadUri(uri)) {
      return NavigationDecision.navigate;
    }
    unawaited(_shareOutput(runtime, uri));
    return NavigationDecision.prevent;
  }

  Future<void> _shareOutput(WebServerRuntime runtime, Uri uri) async {
    final file = runtime.resolveOutputFileFromUri(uri);
    if (file == null) {
      _showMessage('文件不存在或已被清理');
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/epub+zip')],
          subject: path.basename(file.path),
          sharePositionOrigin: origin,
        ),
      );
    } catch (error) {
      _showMessage('无法打开分享面板：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return StartupErrorPage(error: _startupError!, onRetry: _start);
    }
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}

class StartupErrorPage extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const StartupErrorPage({
    required this.error,
    required this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text('本地服务启动失败', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
