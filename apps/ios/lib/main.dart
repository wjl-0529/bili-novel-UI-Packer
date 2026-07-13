import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

const remoteServerUri = String.fromEnvironment(
  'REMOTE_SERVER_URL',
  defaultValue: 'https://book.jinhub.cn',
);
const _serverConfigFileName = 'server_url.txt';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f766e)),
        scaffoldBackgroundColor: const Color(0xffeef2f6),
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
  Uri _serverUri = Uri.parse(remoteServerUri);

  WebViewController? _controller;
  Object? _startupError;
  bool _exporting = false;
  bool _serverPreferenceLoaded = false;
  int _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!_serverPreferenceLoaded) {
      await _loadSavedServerUri();
      _serverPreferenceLoaded = true;
    }
    if (mounted) {
      setState(() {
        _controller = null;
        _startupError = null;
        _loadingProgress = 0;
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
            onPageStarted: (_) {
              if (mounted) {
                setState(() => _loadingProgress = 0);
              }
            },
            onProgress: (progress) {
              if (mounted) {
                setState(
                  () => _loadingProgress = progress.clamp(0, 100).toInt(),
                );
              }
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() => _loadingProgress = 100);
              }
            },
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

  Future<void> _loadSavedServerUri() async {
    try {
      final file = await _serverConfigFile();
      if (!await file.exists()) {
        return;
      }
      final saved = normalizeServerUri(await file.readAsString());
      if (saved != null) {
        _serverUri = saved;
      }
    } catch (_) {
      // Keep the build-time default when the preference cannot be read.
    }
  }

  Future<void> _changeServer(String value) async {
    final next = normalizeServerUri(value);
    if (next == null) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 地址');
    }
    final file = await _serverConfigFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(next.toString(), flush: true);
    _serverUri = next;
    await _start();
  }

  Future<File> _serverConfigFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_serverConfigFileName');
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
      return StartupErrorPage(
        error: _startupError!,
        serverUrl: _serverUri.toString(),
        onConnect: _changeServer,
        onRetry: _start,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: controller)),
            if (_loadingProgress < 100)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _loadingProgress == 0 ? null : _loadingProgress / 100,
                  minHeight: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Uri? normalizeServerUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.replace(path: '', query: null, fragment: null);
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

class StartupErrorPage extends StatefulWidget {
  final Object error;
  final String serverUrl;
  final Future<void> Function(String value) onConnect;
  final VoidCallback onRetry;

  const StartupErrorPage({
    required this.error,
    required this.serverUrl,
    required this.onConnect,
    required this.onRetry,
    super.key,
  });

  @override
  State<StartupErrorPage> createState() => _StartupErrorPageState();
}

class _StartupErrorPageState extends State<StartupErrorPage> {
  late final TextEditingController _serverController;
  String? _validationError;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.serverUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _validationError = null;
    });
    try {
      await widget.onConnect(_serverController.text);
    } catch (error) {
      if (mounted) {
        setState(
          () => _validationError = error.toString().replaceFirst(
            'FormatException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text('无法连接服务器', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 8),
                  Text('${widget.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _serverController,
                    enabled: !_connecting,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '服务器地址',
                      errorText: _validationError,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _connecting ? null : _connect,
                          icon: _connecting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.link),
                          label: const Text('连接'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _connecting ? null : widget.onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
