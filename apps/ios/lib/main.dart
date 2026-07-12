import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

const remoteServerUri = 'https://book.jinhub.cn';

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
  static final Uri _serverUri = Uri.parse(remoteServerUri);

  WebViewController? _controller;
  Object? _startupError;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _controller = null;
        _startupError = null;
      });
    }
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xfff8fafc))
        ..addJavaScriptChannel(
          'NativeExport',
          onMessageReceived: (message) {
            unawaited(_handleExportMessage(message.message));
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) => _handleNavigation(request),
            onWebResourceError: (error) {
              if (error.isForMainFrame == true && mounted) {
                setState(() => _startupError = error.description);
              }
            },
          ),
        );
      await controller.loadRequest(_serverUri);
      if (!mounted) {
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) {
        setState(() => _startupError = error);
      }
    }
  }

  FutureOr<NavigationDecision> _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null || !isRemoteOutputUri(_serverUri, uri)) {
      return NavigationDecision.navigate;
    }
    unawaited(_requestNativeExport(uri));
    return NavigationDecision.prevent;
  }

  Future<void> _requestNativeExport(Uri outputUri) async {
    if (_exporting) {
      _showMessage('已有文件正在导出');
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final segments = outputUri.pathSegments;
    final body = jsonEncode({'jobId': segments[2], 'fileName': segments[4]});
    setState(() => _exporting = true);
    _showMessage('正在从服务器准备 EPUB…');
    try {
      await controller.runJavaScript('''
        (async () => {
          try {
            const response = await fetch('/api/native/exports', {
              method: 'POST',
              credentials: 'same-origin',
              headers: {'content-type': 'application/json'},
              body: ${jsonEncode(body)}
            });
            const payload = await response.text();
            NativeExport.postMessage(JSON.stringify({
              ok: response.ok,
              status: response.status,
              payload: payload
            }));
          } catch (error) {
            NativeExport.postMessage(JSON.stringify({
              ok: false,
              status: 0,
              payload: JSON.stringify({message: String(error)})
            }));
          }
        })();
      ''');
    } catch (error) {
      if (mounted) {
        setState(() => _exporting = false);
      }
      _showMessage('无法请求服务器导出：$error');
    }
  }

  Future<void> _handleExportMessage(String message) async {
    try {
      final envelope = jsonDecode(message) as Map<String, dynamic>;
      final payloadText = envelope['payload'] as String? ?? '{}';
      final payload = jsonDecode(payloadText) as Map<String, dynamic>;
      if (envelope['ok'] != true) {
        throw StateError(
          payload['message']?.toString() ?? '服务器导出失败（${envelope['status']}）',
        );
      }
      final relativeUrl = payload['url'] as String?;
      final fileName = payload['fileName'] as String?;
      if (relativeUrl == null || fileName == null) {
        throw const FormatException('服务器没有返回导出地址');
      }
      await _downloadAndShare(_serverUri.resolve(relativeUrl), fileName);
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _downloadAndShare(Uri uri, String fileName) async {
    final client = HttpClient();
    File? temporaryFile;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('服务器返回 ${response.statusCode}');
      }
      final temporaryDirectory = await getTemporaryDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
      temporaryFile = File('${temporaryDirectory.path}/$safeName');
      await response.pipe(temporaryFile.openWrite());

      if (!mounted) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(temporaryFile.path, mimeType: 'application/epub+zip')],
          subject: fileName,
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      client.close(force: true);
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
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

bool isRemoteOutputUri(Uri serverUri, Uri candidate) {
  final serverPort = serverUri.hasPort
      ? serverUri.port
      : serverUri.scheme == 'https'
      ? 443
      : 80;
  final candidatePort = candidate.hasPort
      ? candidate.port
      : candidate.scheme == 'https'
      ? 443
      : 80;
  if (candidate.scheme != serverUri.scheme ||
      candidate.host != serverUri.host ||
      candidatePort != serverPort) {
    return false;
  }
  final segments = candidate.pathSegments;
  return segments.length == 5 &&
      segments[0] == 'api' &&
      segments[1] == 'jobs' &&
      segments[2].isNotEmpty &&
      segments[3] == 'files' &&
      segments[4].isNotEmpty;
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
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                const Text('无法连接服务器', style: TextStyle(fontSize: 20)),
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
