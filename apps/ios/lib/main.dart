import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'biometric_service.dart';
import 'native_models.dart';

const _serverConfigFileName = 'server_url.txt';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovelPackerIosApp());
}

class NovelPackerIosApp extends StatelessWidget {
  const NovelPackerIosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff0f766e),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: '轻小说打包器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xffe8f0ef),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withValues(alpha: 0.70),
          indicatorColor: scheme.primary.withValues(alpha: 0.16),
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primary.withValues(alpha: 0.88),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0x665f6f6d)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0x665f6f6d)),
          ),
          filled: true,
          fillColor: Color(0xb3ffffff),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
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
  final BiometricService _biometric = BiometricService();
  Uri? _serverUri;
  ApiClient? _api;
  Object? _startupError;
  bool _loading = true;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _startupError = null;
    });
    final savedServerUri = await _loadSavedServerUri();
    if (!mounted) {
      return;
    }
    if (savedServerUri == null) {
      setState(() {
        _loading = false;
        _serverUri = null;
        _api = null;
      });
      return;
    }
    await _connect(savedServerUri, persist: false);
  }

  Future<void> _connect(Uri uri, {bool persist = true}) async {
    final oldApi = _api;
    final api = ApiClient(uri);
    api.onUnauthorized = _handleUnauthorized;
    if (mounted) {
      setState(() {
        _loading = true;
        _startupError = null;
        _serverUri = uri;
        _api = api;
        _authenticated = false;
      });
    }
    oldApi?.close();
    try {
      final authenticated = await api.checkSession();
      if (!mounted || !identical(_api, api)) {
        api.close();
        return;
      }
      setState(() {
        _authenticated = authenticated;
        _loading = false;
      });
      if (persist) {
        await _saveServerUri(uri);
      }
    } catch (error) {
      api.close();
      if (mounted && identical(_api, api)) {
        setState(() {
          _loading = false;
          _startupError = error;
        });
      }
    }
  }

  Future<void> _changeServer(String value) async {
    final uri = normalizeServerUri(value);
    if (uri == null) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 地址');
    }
    await _connect(uri);
  }

  Future<Uri?> _loadSavedServerUri() async {
    try {
      final file = await _serverConfigFile();
      if (await file.exists()) {
        final saved = normalizeServerUri(await file.readAsString());
        if (saved != null) {
          return saved;
        }
      }
    } catch (_) {
      // A missing or unreadable local setting is handled by the setup page.
    }
    return null;
  }

  Future<void> _saveServerUri(Uri uri) async {
    final file = await _serverConfigFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(uri.toString(), flush: true);
  }

  Future<File> _serverConfigFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_serverConfigFileName');
  }

  void _handleUnauthorized() {
    if (!mounted) {
      return;
    }
    setState(() => _authenticated = false);
  }

  Future<void> _login(String password) async {
    final api = _api;
    if (api == null) {
      return;
    }
    await api.login(password);
    if (mounted) {
      setState(() => _authenticated = true);
    }
  }

  Future<void> _logout() async {
    await _api?.logout();
    if (mounted) {
      setState(() => _authenticated = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final api = _api;
    final serverUri = _serverUri;
    if (serverUri == null) {
      return ServerSetupPage(onConnect: _changeServer);
    }
    if (_startupError != null || api == null) {
      return StartupErrorPage(
        error: _startupError ?? StateError('服务器未初始化'),
        serverUrl: serverUri.toString(),
        onConnect: _changeServer,
        onRetry: () => unawaited(_boot()),
      );
    }
    if (!_authenticated) {
      return LoginPage(
        biometric: _biometric,
        serverUri: serverUri,
        onLogin: _login,
        onChangeServer: _showServerDialog,
      );
    }
    return NativeHomePage(
      api: api,
      biometric: _biometric,
      serverUri: serverUri,
      onLogout: _logout,
      onChangeServer: _changeServer,
    );
  }

  Future<void> _showServerDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          ServerAddressDialog(initialValue: _serverUri?.toString() ?? ''),
    );
    if (selected != null && mounted) {
      try {
        await _changeServer(selected);
      } catch (error) {
        _showMessage(error.toString());
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
}

class LoginPage extends StatefulWidget {
  final BiometricService biometric;
  final Uri serverUri;
  final Future<void> Function(String password) onLogin;
  final Future<void> Function() onChangeServer;

  const LoginPage({
    required this.biometric,
    required this.serverUri,
    required this.onLogin,
    required this.onChangeServer,
    super.key,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _biometricBusy = false;
  bool _biometricAvailable = false;
  bool _hasBiometricPassword = false;
  bool _rememberBiometric = true;
  bool _didAttemptAutomaticFaceId = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometricState());
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricState() async {
    final available = await widget.biometric.isAvailable();
    final hasPassword = available && await widget.biometric.hasSavedPassword();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _hasBiometricPassword = hasPassword;
        _rememberBiometric = available;
      });
      if (hasPassword && !_didAttemptAutomaticFaceId) {
        _didAttemptAutomaticFaceId = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_loginWithFaceId());
          }
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _error = '请输入管理员密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final password = _passwordController.text;
    try {
      await widget.onLogin(password);
      if (_biometricAvailable && _rememberBiometric) {
        try {
          await widget.biometric.savePassword(password);
          _hasBiometricPassword = true;
        } catch (_) {
          // Password login remains successful when Keychain is unavailable.
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loginWithFaceId() async {
    setState(() {
      _biometricBusy = true;
      _error = null;
    });
    try {
      final authenticated = await widget.biometric.authenticate();
      if (!authenticated) {
        return;
      }
      final password = await widget.biometric.readPassword();
      if (password == null || password.isEmpty) {
        setState(() => _hasBiometricPassword = false);
        return;
      }
      await widget.onLogin(password);
    } catch (error) {
      if (error is ApiException && error.statusCode == 401) {
        await widget.biometric.clearPassword();
        if (mounted) {
          setState(() => _hasBiometricPassword = false);
        }
      }
      if (mounted) {
        setState(() => _error = 'Face ID 登录失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _biometricBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassSurface(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.menu_book_rounded, size: 48),
                      const SizedBox(height: 14),
                      const Text(
                        '轻小说打包器',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.serverUri.authority,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _passwordController,
                        enabled: !_busy,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '管理员密码',
                          errorText: _error,
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: const Text('登录'),
                      ),
                      if (_biometricAvailable && !_hasBiometricPassword)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('启用 Face ID 快速登录'),
                          value: _rememberBiometric,
                          onChanged: _busy || _biometricBusy
                              ? null
                              : (value) =>
                                    setState(() => _rememberBiometric = value),
                        ),
                      if (_biometricAvailable && _hasBiometricPassword)
                        OutlinedButton.icon(
                          onPressed: _busy || _biometricBusy
                              ? null
                              : _loginWithFaceId,
                          icon: _biometricBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.face_retouching_natural),
                          label: const Text('使用 Face ID 登录'),
                        ),
                      TextButton.icon(
                        onPressed: _busy || _biometricBusy
                            ? null
                            : widget.onChangeServer,
                        icon: const Icon(Icons.dns_outlined),
                        label: const Text('切换服务器'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NativeHomePage extends StatefulWidget {
  final ApiClient api;
  final BiometricService biometric;
  final Uri serverUri;
  final Future<void> Function() onLogout;
  final Future<void> Function(String value) onChangeServer;

  const NativeHomePage({
    required this.api,
    required this.biometric,
    required this.serverUri,
    required this.onLogout,
    required this.onChangeServer,
    super.key,
  });

  @override
  State<NativeHomePage> createState() => _NativeHomePageState();
}

class _NativeHomePageState extends State<NativeHomePage> {
  int _index = 0;
  final _jobsKey = GlobalKey<_JobsPageState>();
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openJobs() {
    _selectTab(1);
    unawaited(_jobsKey.currentState?.refresh());
  }

  void _selectTab(int index) {
    if (index < 0 || index > 2) {
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (index == 1) {
      unawaited(_jobsKey.currentState?.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DownloadPage(api: widget.api, onCreated: _openJobs),
      JobsPage(key: _jobsKey, api: widget.api),
      SettingsPage(
        api: widget.api,
        biometric: widget.biometric,
        serverUri: widget.serverUri,
        onLogout: widget.onLogout,
        onChangeServer: widget.onChangeServer,
      ),
    ];
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: GlassBottomNavigationBar(
          selectedIndex: _index,
          onSelected: _selectTab,
        ),
      ),
    );
  }
}

class GlassBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const GlassBottomNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  static const _items =
      <({IconData icon, IconData selectedIcon, String label})>[
        (
          icon: Icons.download_outlined,
          selectedIcon: Icons.download_rounded,
          label: '下载',
        ),
        (
          icon: Icons.list_alt_outlined,
          selectedIcon: Icons.list_alt_rounded,
          label: '任务',
        ),
        (
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: '设置',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -180 && selectedIndex < _items.length - 1) {
          onSelected(selectedIndex + 1);
        } else if (velocity > 180 && selectedIndex > 0) {
          onSelected(selectedIndex - 1);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.54),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.82),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.45),
                  blurRadius: 2,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / _items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * itemWidth + 5,
                      top: 5,
                      width: itemWidth - 10,
                      height: 58,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(23),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.13),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 9,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var index = 0; index < _items.length; index++)
                          Expanded(
                            child: Semantics(
                              selected: selectedIndex == index,
                              button: true,
                              label: _items[index].label,
                              child: InkResponse(
                                onTap: () => onSelected(index),
                                containedInkWell: true,
                                highlightShape: BoxShape.rectangle,
                                child: SizedBox.expand(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: Icon(
                                          selectedIndex == index
                                              ? _items[index].selectedIcon
                                              : _items[index].icon,
                                          key: ValueKey(selectedIndex == index),
                                          size: 23,
                                          color: selectedIndex == index
                                              ? primary
                                              : const Color(0xff5f666b),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _items[index].label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: selectedIndex == index
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selectedIndex == index
                                              ? primary
                                              : const Color(0xff5f666b),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DownloadPage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onCreated;

  const DownloadPage({required this.api, required this.onCreated, super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _rangeController;
  late final TextEditingController _volumeController;
  late final TextEditingController _barkServerController;
  late final TextEditingController _barkKeyController;
  bool _combineVolume = false;
  bool _addChapterTitle = false;
  bool _barkEnabled = false;
  BarkEventsModel _barkEvents = const BarkEventsModel();
  bool _busy = false;
  bool _previewBusy = false;
  List<NovelPreviewModel> _previews = const [];
  List<NovelPreviewFailureModel> _previewFailures = const [];
  final Set<int> _selectedPreviewIds = <int>{};
  String? _previewSignature;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _rangeController = TextEditingController();
    _volumeController = TextEditingController();
    _barkServerController = TextEditingController();
    _barkKeyController = TextEditingController();
    _urlController.addListener(_invalidateStalePreview);
    _rangeController.addListener(_invalidateStalePreview);
  }

  @override
  void dispose() {
    _urlController.removeListener(_invalidateStalePreview);
    _rangeController.removeListener(_invalidateStalePreview);
    _urlController.dispose();
    _rangeController.dispose();
    _volumeController.dispose();
    _barkServerController.dispose();
    _barkKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final template = _urlController.text.trim();
    final range = _rangeController.text.trim();
    if (!template.contains('{id}')) {
      setState(() => _notice = 'URL 模板必须包含 {id}');
      return;
    }
    if (range.isEmpty) {
      setState(() => _notice = '请输入小说 ID 范围，例如 1-3 或 12,15');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    var request = JobRequestModel(
      urlTemplate: template,
      rangeText: range,
      volumeRangeText: _volumeController.text.trim(),
      combineVolume: _combineVolume,
      addChapterTitle: _addChapterTitle,
      barkConfig: BarkConfigModel(
        enabled: _barkEnabled,
        serverUrl: _barkServerController.text.trim(),
        deviceKey: _barkKeyController.text.trim(),
        events: _barkEvents,
      ),
    );
    if (_previews.isNotEmpty &&
        _selectedPreviewIds.isNotEmpty &&
        _previewSignature == _currentPreviewSignature) {
      request = JobRequestModel(
        urlTemplate: request.urlTemplate,
        rangeText: _previews
            .where((preview) => _selectedPreviewIds.contains(preview.sourceId))
            .map((preview) => preview.sourceId)
            .join(','),
        volumeRangeText: request.volumeRangeText,
        combineVolume: request.combineVolume,
        addChapterTitle: request.addChapterTitle,
        barkConfig: request.barkConfig,
      );
    }
    try {
      final jobs = await widget.api.createJobs(request);
      if (mounted) {
        setState(() => _notice = '已创建 ${jobs.length} 个任务');
      }
      widget.onCreated();
    } catch (error) {
      if (mounted) {
        setState(() => _notice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String get _currentPreviewSignature =>
      '${_urlController.text.trim()}\n${_rangeController.text.trim()}';

  void _invalidateStalePreview() {
    if (!mounted ||
        _previewSignature == null ||
        _previewSignature == _currentPreviewSignature) {
      return;
    }
    setState(() {
      _previewSignature = null;
      _previews = const [];
      _previewFailures = const [];
      _selectedPreviewIds.clear();
      _notice = '搜索条件已修改，请重新搜索预览';
    });
  }

  JobRequestModel _currentRequest() {
    return JobRequestModel(
      urlTemplate: _urlController.text.trim(),
      rangeText: _rangeController.text.trim(),
      volumeRangeText: _volumeController.text.trim(),
      combineVolume: _combineVolume,
      addChapterTitle: _addChapterTitle,
      barkConfig: BarkConfigModel(
        enabled: _barkEnabled,
        serverUrl: _barkServerController.text.trim(),
        deviceKey: _barkKeyController.text.trim(),
        events: _barkEvents,
      ),
    );
  }

  Future<void> _preview() async {
    final request = _currentRequest();
    final requestedSignature = _currentPreviewSignature;
    if (!request.urlTemplate.contains('{id}') || request.rangeText.isEmpty) {
      setState(() => _notice = '请先填写包含 {id} 的 URL 模板和小说 ID 范围');
      return;
    }
    setState(() {
      _previewBusy = true;
      _notice = null;
      _previews = const [];
      _previewFailures = const [];
      _selectedPreviewIds.clear();
      _previewSignature = null;
    });
    try {
      final response = await widget.api.previewNovel(request);
      if (!mounted) {
        return;
      }
      if (_currentPreviewSignature != requestedSignature) {
        setState(() => _notice = '搜索条件已修改，请重新搜索预览');
        return;
      }
      setState(() {
        _previews = response.previews;
        _previewFailures = response.failures;
        _previewSignature = requestedSignature;
        _selectedPreviewIds.addAll(
          response.previews.map((item) => item.sourceId),
        );
        _notice = response.previews.isEmpty
            ? '未找到可预览的小说'
            : '已找到 ${response.previews.length} 本小说'
                  '${response.failures.isEmpty ? '' : '，跳过 ${response.failures.length} 个 ID'}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _previewBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建下载任务')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          _SectionCard(
            title: '小说来源',
            icon: Icons.link,
            children: [
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL 模板',
                  hintText: 'https://.../{id}.html',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rangeController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: '小说 ID 范围',
                  hintText: '例如 1-3、8、12-15',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _volumeController,
                decoration: const InputDecoration(
                  labelText: '分卷范围（可选）',
                  hintText: '留空表示全部分卷',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '打包选项',
            icon: Icons.tune,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('合并分卷'),
                subtitle: const Text('将同一本小说的分卷合并到一个 EPUB'),
                value: _combineVolume,
                onChanged: (value) => setState(() => _combineVolume = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('添加章节标题'),
                value: _addChapterTitle,
                onChanged: (value) => setState(() => _addChapterTitle = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Bark 通知',
            icon: Icons.notifications_none,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 Bark'),
                value: _barkEnabled,
                onChanged: (value) => setState(() => _barkEnabled = value),
              ),
              if (_barkEnabled) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _barkServerController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Bark 服务地址'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _barkKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Device Key'),
                ),
                const SizedBox(height: 8),
                const Text(
                  '通知事件',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final entry in <String, String>{
                  'start': '开始',
                  'success': '成功',
                  'failure': '失败',
                  'progress': '进度',
                  'update': '追更',
                }.entries)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.value),
                    value: switch (entry.key) {
                      'start' => _barkEvents.start,
                      'success' => _barkEvents.success,
                      'failure' => _barkEvents.failure,
                      'progress' => _barkEvents.progress,
                      _ => _barkEvents.update,
                    },
                    onChanged: (value) => setState(() {
                      _barkEvents = switch (entry.key) {
                        'start' => _barkEvents.copyWith(start: value),
                        'success' => _barkEvents.copyWith(success: value),
                        'failure' => _barkEvents.copyWith(failure: value),
                        'progress' => _barkEvents.copyWith(progress: value),
                        _ => _barkEvents.copyWith(update: value),
                      };
                    }),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_previews.isNotEmpty || _previewFailures.isNotEmpty)
            _PreviewResults(
              api: widget.api,
              previews: _previews,
              failures: _previewFailures,
              selectedIds: _selectedPreviewIds,
              onToggle: (id, selected) => setState(() {
                if (selected) {
                  _selectedPreviewIds.add(id);
                } else {
                  _selectedPreviewIds.remove(id);
                }
              }),
              onSelectAll: () => setState(() {
                _selectedPreviewIds
                  ..clear()
                  ..addAll(_previews.map((item) => item.sourceId));
              }),
              onClear: () => setState(() => _selectedPreviewIds.clear()),
            ),
          if (_previews.isNotEmpty || _previewFailures.isNotEmpty)
            const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _previewBusy ? null : _preview,
            icon: _previewBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_previewBusy ? '正在搜索...' : '搜索并预览'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                _busy || (_previews.isNotEmpty && _selectedPreviewIds.isEmpty)
                ? null
                : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_busy ? '正在创建...' : '开始下载'),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Text(
              _notice!,
              style: TextStyle(
                color: _notice!.startsWith('已创建')
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewResults extends StatelessWidget {
  final ApiClient api;
  final List<NovelPreviewModel> previews;
  final List<NovelPreviewFailureModel> failures;
  final Set<int> selectedIds;
  final void Function(int id, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  const _PreviewResults({
    required this.api,
    required this.previews,
    required this.failures,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '搜索结果（已选 ${selectedIds.length}/${previews.length}）',
      icon: Icons.search,
      children: [
        Row(
          children: [
            TextButton(onPressed: onSelectAll, child: const Text('全选')),
            TextButton(onPressed: onClear, child: const Text('清空')),
            if (failures.isNotEmpty)
              Text(
                '跳过 ${failures.length} 个 ID',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        for (final preview in previews)
          _PreviewItem(
            api: api,
            preview: preview,
            selected: selectedIds.contains(preview.sourceId),
            onChanged: (value) => onToggle(preview.sourceId, value),
          ),
        for (final failure in failures)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline, color: Colors.orange),
            title: Text('#${failure.sourceId} 搜索失败'),
            subtitle: Text(failure.message),
          ),
      ],
    );
  }
}

class _PreviewItem extends StatefulWidget {
  final ApiClient api;
  final NovelPreviewModel preview;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _PreviewItem({
    required this.api,
    required this.preview,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_PreviewItem> createState() => _PreviewItemState();
}

class _PreviewItemState extends State<_PreviewItem> {
  Future<Uint8List?>? _coverBytes;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant _PreviewItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.coverUrl != widget.preview.coverUrl ||
        oldWidget.preview.url != widget.preview.url ||
        oldWidget.api != widget.api) {
      _loadCover();
    }
  }

  void _loadCover() {
    final coverUrl = widget.preview.coverUrl;
    _coverBytes = coverUrl == null || coverUrl.isEmpty
        ? null
        : widget.api
              .downloadCover(coverUrl, widget.preview.url)
              .then<Uint8List?>((bytes) => bytes)
              .catchError((_) => null);
  }

  Widget _coverPlaceholder([bool loading = false]) {
    return ColoredBox(
      color: const Color(0xffe8edf0),
      child: loading
          ? const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Icon(Icons.menu_book_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final meta = [
      if (preview.sourceName.isNotEmpty) preview.sourceName,
      if (preview.publisher?.isNotEmpty == true) preview.publisher!,
      if (preview.volumeCount != null) '${preview.volumeCount} 卷',
      if (preview.chapterCount != null) '${preview.chapterCount} 章',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: widget.selected,
            onChanged: (value) => widget.onChanged(value == true),
          ),
          const SizedBox(width: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 62,
              height: 88,
              child: _coverBytes == null
                  ? _coverPlaceholder()
                  : FutureBuilder<Uint8List?>(
                      future: _coverBytes,
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes == null || bytes.isEmpty) {
                          return _coverPlaceholder(
                            snapshot.connectionState == ConnectionState.waiting,
                          );
                        }
                        return Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => _coverPlaceholder(),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${preview.sourceId} ${preview.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (preview.alias?.isNotEmpty == true ||
                    preview.author.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [
                        if (preview.alias?.isNotEmpty == true) preview.alias!,
                        if (preview.author.isNotEmpty) preview.author,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (preview.status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      preview.status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (preview.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      preview.tags.take(5).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (preview.description?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      preview.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JobsPage extends StatefulWidget {
  final ApiClient api;

  const JobsPage({required this.api, super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  List<DownloadJobModel> _jobs = const [];
  Timer? _timer;
  bool _loading = true;
  bool _cleanupBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final jobs = await widget.api.getJobs();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _runAction(
    DownloadJobModel job,
    Future<void> Function(String id) action,
  ) async {
    try {
      await action(job.id);
      await refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openDetails(DownloadJobModel job) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          JobDetailSheet(api: widget.api, job: job, onChanged: refresh),
    );
    await refresh();
  }

  Future<void> _deleteJob(DownloadJobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: Text(
          '将删除任务 #${job.sourceId}'
          '${job.outputFiles.isEmpty ? '' : '及 ${job.outputFiles.length} 个输出文件'}，此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runAction(job, widget.api.deleteJob);
    }
  }

  Future<void> _cleanupCompleted() async {
    final count = _jobs
        .where(
          (job) =>
              const {'succeeded', 'failed', 'canceled'}.contains(job.status),
        )
        .length;
    if (count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可清理的已完成任务')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理已完成任务？'),
        content: Text('将删除 $count 个已完成、失败或已取消任务及其输出文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _cleanupBusy = true);
    try {
      final result = await widget.api.cleanupCompletedJobs();
      if (mounted) {
        setState(() => _jobs = result.jobs);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已清理 ${result.deleted} 个任务')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _cleanupBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务队列'),
        actions: [
          IconButton(
            tooltip: '清理已完成任务',
            onPressed: _cleanupBusy
                ? null
                : () => unawaited(_cleanupCompleted()),
            icon: _cleanupBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _jobs.isEmpty
          ? _ErrorState(message: _error!, onRetry: () => unawaited(refresh()))
          : _jobs.isEmpty
          ? const _EmptyState(
              icon: Icons.inbox_outlined,
              message: '暂无任务，先创建一个下载任务吧',
            )
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                itemCount: _jobs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final job = _jobs[index];
                  final queueAhead = job.status == 'queued'
                      ? _jobs
                                .take(index)
                                .where((item) => item.status == 'queued')
                                .length +
                            (_jobs.any((item) => item.status == 'running')
                                ? 1
                                : 0)
                      : 0;
                  return JobCard(
                    job: job,
                    queueAhead: queueAhead,
                    onTap: () => _openDetails(job),
                    onCancel: () => _runAction(job, widget.api.cancelJob),
                    onRetry: () => _runAction(job, widget.api.retryJob),
                    onDelete: () => _deleteJob(job),
                  );
                },
              ),
            ),
    );
  }
}

class JobCard extends StatelessWidget {
  final DownloadJobModel job;
  final int queueAhead;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const JobCard({
    required this.job,
    this.queueAhead = 0,
    required this.onTap,
    required this.onCancel,
    required this.onRetry,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (job.progress.clamp(0, 1) * 100).round();
    final terminal = const {
      'succeeded',
      'failed',
      'canceled',
      'paused',
    }.contains(job.status);
    return GlassSurface(
      borderRadius: BorderRadius.circular(16),
      blur: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.title ?? '小说 #${job.sourceId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _StatusChip(status: job.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                job.author?.isNotEmpty == true ? job.author! : job.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: percent / 100),
                  ),
                  const SizedBox(width: 10),
                  Text('$percent%'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                job.status == 'queued' && queueAhead > 0
                    ? '前面还有 $queueAhead 个任务，服务器将依次处理'
                    : job.error?.isNotEmpty == true
                    ? job.error!
                    : job.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!terminal)
                    IconButton(
                      tooltip: '取消任务',
                      onPressed: onCancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  if (job.status == 'failed' ||
                      job.status == 'canceled' ||
                      job.status == 'paused')
                    IconButton(
                      tooltip: '重试',
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                    ),
                  if (job.outputFiles.isNotEmpty)
                    IconButton(
                      tooltip: '查看文件',
                      onPressed: onTap,
                      icon: const Icon(Icons.file_present_outlined),
                    ),
                  IconButton(
                    tooltip: '删除任务',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JobDetailSheet extends StatefulWidget {
  final ApiClient api;
  final DownloadJobModel job;
  final Future<void> Function() onChanged;

  const JobDetailSheet({
    required this.api,
    required this.job,
    required this.onChanged,
    super.key,
  });

  @override
  State<JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends State<JobDetailSheet> {
  String? _busyFile;
  bool _cleaningOutputs = false;

  Future<void> _shareFile(String fileName) async {
    setState(() => _busyFile = fileName);
    try {
      final exportUrl = await widget.api.createNativeExport(
        widget.job.id,
        fileName,
      );
      final documents = await getApplicationDocumentsDirectory();
      final file = await widget.api.downloadExport(
        exportUrl,
        fileName,
        directory: documents,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('EPUB 已保存到本机“文件”App，可继续分享或打开')),
      );
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/epub+zip')],
          subject: fileName,
          sharePositionOrigin: origin,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busyFile = null);
      }
    }
  }

  Future<void> _deleteOutputs() async {
    if (widget.job.outputFiles.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理输出文件？'),
        content: Text(
          '将删除 ${widget.job.outputFiles.length} 个 EPUB 文件，但保留任务记录和日志。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _cleaningOutputs = true);
    try {
      await widget.api.deleteJobOutputs(widget.job.id);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('输出文件已清理，任务记录已保留')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _cleaningOutputs = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              job.title ?? '小说 #${job.sourceId}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _StatusChip(status: job.status),
                const SizedBox(width: 8),
                Text('${(job.progress.clamp(0, 1) * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: job.progress.clamp(0, 1)),
            const SizedBox(height: 12),
            Text(job.error?.isNotEmpty == true ? job.error! : job.message),
            if (job.outputDir != null || job.sourceName != null) ...[
              const SizedBox(height: 12),
              Text(
                [
                  if (job.sourceName != null) '来源：${job.sourceName}',
                  if (job.volumeSummary != null) '分卷：${job.volumeSummary}',
                  if (job.outputDir != null) '保存位置：${job.outputDir}',
                ].join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (job.uploadStatus != null && job.uploadStatus != 'disabled')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WebDAV：${_uploadStatusText(job.uploadStatus!, job.uploadError)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (job.outputFiles.isNotEmpty &&
                const {'succeeded', 'failed', 'canceled'}.contains(job.status))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _cleaningOutputs ? null : _deleteOutputs,
                  icon: _cleaningOutputs
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined),
                  label: const Text('清理输出文件'),
                ),
              ),
            if (job.outputFiles.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text(
                'EPUB 文件',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final file in job.outputFiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    file,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '保存或分享文件',
                    onPressed: _busyFile == null
                        ? () => _shareFile(file)
                        : null,
                    icon: _busyFile == file
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_for_offline_outlined),
                  ),
                ),
            ],
            const SizedBox(height: 22),
            const Text('任务日志', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffeef2f5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                job.logs.isEmpty ? '暂无日志' : job.logs.takeLast(80).join('\n'),
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final ApiClient api;
  final BiometricService biometric;
  final Uri serverUri;
  final Future<void> Function() onLogout;
  final Future<void> Function(String value) onChangeServer;

  const SettingsPage({
    required this.api,
    required this.biometric,
    required this.serverUri,
    required this.onLogout,
    required this.onChangeServer,
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  WebDavConfigModel _webDav = const WebDavConfigModel();
  CleanupConfigModel _cleanup = const CleanupConfigModel();
  AutoUpdateConfigModel _autoUpdate = const AutoUpdateConfigModel();
  List<DownloadJobModel> _jobs = const [];
  late final TextEditingController _webDavServerController;
  late final TextEditingController _webDavUsernameController;
  late final TextEditingController _webDavPasswordController;
  late final TextEditingController _webDavPathController;
  late final TextEditingController _retentionController;
  late final TextEditingController _dailyTimeController;
  bool _loading = true;
  bool _webDavBusy = false;
  bool _cleanupBusy = false;
  bool _autoUpdateBusy = false;
  String? _webDavNotice;
  String? _cleanupNotice;
  String? _autoUpdateNotice;
  bool _biometricAvailable = false;
  bool _faceIdEnabled = false;
  bool _faceIdBusy = false;
  String? _faceIdNotice;

  @override
  void initState() {
    super.initState();
    _webDavServerController = TextEditingController();
    _webDavUsernameController = TextEditingController();
    _webDavPasswordController = TextEditingController();
    _webDavPathController = TextEditingController();
    _retentionController = TextEditingController(text: '7');
    _dailyTimeController = TextEditingController(text: '03:00');
    unawaited(_load());
    unawaited(_loadBiometric());
  }

  @override
  void dispose() {
    _webDavServerController.dispose();
    _webDavUsernameController.dispose();
    _webDavPasswordController.dispose();
    _webDavPathController.dispose();
    _retentionController.dispose();
    _dailyTimeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        widget.api.getWebDavConfig(),
        widget.api.getCleanupConfig(),
        widget.api.getAutoUpdateConfig(),
        widget.api.getJobs(),
      ]);
      if (!mounted) {
        return;
      }
      final webDav = values[0] as WebDavConfigModel;
      final cleanup = values[1] as CleanupConfigModel;
      final autoUpdate = values[2] as AutoUpdateConfigModel;
      setState(() {
        _webDav = webDav;
        _cleanup = cleanup;
        _autoUpdate = autoUpdate;
        _jobs = values[3] as List<DownloadJobModel>;
        _loading = false;
        _syncControllers();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _autoUpdateNotice = error.toString();
        });
      }
    }
  }

  void _syncControllers() {
    _webDavServerController.text = _webDav.serverUrl;
    _webDavUsernameController.text = _webDav.username;
    _webDavPasswordController.clear();
    _webDavPathController.text = _webDav.basePath;
    _retentionController.text = _cleanup.retentionDays.toString();
    _dailyTimeController.text = _autoUpdate.dailyTime;
  }

  Future<void> _loadBiometric() async {
    final available = await widget.biometric.isAvailable();
    final enabled = available && await widget.biometric.hasSavedPassword();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _faceIdEnabled = enabled;
      });
    }
  }

  Future<void> _toggleFaceId(bool value) async {
    if (!value) {
      await widget.biometric.clearPassword();
      if (mounted) {
        setState(() {
          _faceIdEnabled = false;
          _faceIdNotice = 'Face ID 快速登录已关闭';
        });
      }
      return;
    }
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('启用 Face ID'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: '管理员密码'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('启用'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty || !mounted) {
      return;
    }
    setState(() => _faceIdBusy = true);
    try {
      await widget.api.login(password);
      await widget.biometric.savePassword(password);
      if (mounted) {
        setState(() {
          _faceIdEnabled = true;
          _faceIdNotice = 'Face ID 快速登录已启用';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Face ID 快速登录已启用')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _faceIdNotice = 'Face ID 启用失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _faceIdBusy = false);
      }
    }
  }

  WebDavConfigModel _editedWebDav() {
    return _webDav.copyWith(
      serverUrl: _webDavServerController.text.trim(),
      username: _webDavUsernameController.text.trim(),
      password: _webDavPasswordController.text,
      basePath: _webDavPathController.text.trim(),
    );
  }

  Future<void> _saveWebDav({bool clearPassword = false}) async {
    setState(() {
      _webDavBusy = true;
      _webDavNotice = null;
    });
    try {
      final config = await widget.api.saveWebDavConfig(
        _editedWebDav(),
        clearPassword: clearPassword,
      );
      if (mounted) {
        setState(() {
          _webDav = config;
          _webDavPasswordController.clear();
          _webDavNotice = clearPassword ? '已清空保存的密码' : 'WebDAV 设置已保存';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _webDavNotice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _webDavBusy = false);
      }
    }
  }

  Future<void> _testWebDav() async {
    setState(() {
      _webDavBusy = true;
      _webDavNotice = null;
    });
    try {
      await widget.api.testWebDavConfig(_editedWebDav());
      if (mounted) {
        setState(() => _webDavNotice = 'WebDAV 连接测试通过');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _webDavNotice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _webDavBusy = false);
      }
    }
  }

  Future<void> _saveCleanup() async {
    final days =
        int.tryParse(_retentionController.text)?.clamp(1, 365).toInt() ?? 7;
    setState(() {
      _cleanupBusy = true;
      _cleanupNotice = null;
    });
    try {
      final config = await widget.api.saveCleanupConfig(
        _cleanup.copyWith(retentionDays: days),
      );
      if (mounted) {
        setState(() {
          _cleanup = config;
          _retentionController.text = config.retentionDays.toString();
          _cleanupNotice = '自动清理设置已保存';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _cleanupNotice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _cleanupBusy = false);
      }
    }
  }

  Future<void> _saveAutoUpdate() async {
    final time =
        RegExp(
          r'^([01]\d|2[0-3]):[0-5]\d$',
        ).hasMatch(_dailyTimeController.text.trim())
        ? _dailyTimeController.text.trim()
        : '03:00';
    setState(() {
      _autoUpdateBusy = true;
      _autoUpdateNotice = null;
    });
    try {
      final config = await widget.api.saveAutoUpdateConfig(
        _autoUpdate.copyWith(dailyTime: time),
      );
      if (mounted) {
        setState(() {
          _autoUpdate = config;
          _dailyTimeController.text = config.dailyTime;
          _autoUpdateNotice = '自动更新设置已保存';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _autoUpdateNotice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _autoUpdateBusy = false);
      }
    }
  }

  Future<void> _runAutoUpdate() async {
    setState(() {
      _autoUpdateBusy = true;
      _autoUpdateNotice = null;
    });
    try {
      final response = await widget.api.runAutoUpdateNow();
      final jobs = await widget.api.getJobs();
      if (mounted) {
        setState(() {
          _autoUpdate = response.config;
          _jobs = jobs;
          _autoUpdateNotice =
              '已检查 ${response.result.checked} 个任务，更新 ${response.result.updated} 个';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _autoUpdateNotice = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _autoUpdateBusy = false);
      }
    }
  }

  void _toggleAutoUpdateJob(String jobId, bool selected) {
    final items = [..._autoUpdate.items];
    final existing = items.where((item) => item.jobId == jobId).firstOrNull;
    items.removeWhere((item) => item.jobId == jobId);
    if (selected) {
      items.add(existing ?? AutoUpdateItemModel(jobId: jobId));
    }
    setState(() => _autoUpdate = _autoUpdate.copyWith(items: items));
  }

  Future<void> _changeServer(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          ServerAddressDialog(initialValue: widget.serverUri.toString()),
    );
    if (selected == null || !context.mounted) {
      return;
    }
    try {
      await widget.onChangeServer(selected);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新输入管理员密码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final successfulJobs = _jobs
        .where((job) => job.status == 'succeeded')
        .toList();
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '刷新设置',
            onPressed: () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          GlassSurface(
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('服务器地址'),
              subtitle: Text(widget.serverUri.toString()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changeServer(context),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '安全登录',
            icon: Icons.face_retouching_natural,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Face ID 快速登录'),
                subtitle: Text(
                  _biometricAvailable
                      ? '凭据保存在 iOS Keychain，仅用于自动登录服务器'
                      : '当前设备未检测到可用的 Face ID',
                ),
                value: _faceIdEnabled,
                onChanged: !_biometricAvailable || _faceIdBusy
                    ? null
                    : _toggleFaceId,
              ),
              if (_faceIdNotice != null) Text(_faceIdNotice!),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'WebDAV 上传',
            icon: Icons.cloud_upload_outlined,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 WebDAV'),
                value: _webDav.enabled,
                onChanged: (value) => setState(() {
                  _webDav = _webDav.copyWith(enabled: value);
                }),
              ),
              TextField(
                controller: _webDavServerController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: '服务地址'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _webDavUsernameController,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _webDavPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: _webDav.hasPassword ? '留空不修改已保存密码' : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _webDavPathController,
                decoration: const InputDecoration(labelText: '基础目录'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _webDavBusy ? null : _testWebDav,
                    icon: const Icon(Icons.network_check),
                    label: const Text('测试连接'),
                  ),
                  FilledButton.icon(
                    onPressed: _webDavBusy ? null : _saveWebDav,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存'),
                  ),
                  if (_webDav.hasPassword)
                    TextButton(
                      onPressed: _webDavBusy
                          ? null
                          : () => _saveWebDav(clearPassword: true),
                      child: const Text('清空已保存密码'),
                    ),
                ],
              ),
              if (_webDavNotice != null) Text(_webDavNotice!),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '自动清理',
            icon: Icons.auto_delete_outlined,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用自动清理'),
                value: _cleanup.enabled,
                onChanged: (value) => setState(() {
                  _cleanup = _cleanup.copyWith(enabled: value);
                }),
              ),
              TextField(
                controller: _retentionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '保留天数（1-365）'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _cleanupBusy ? null : _saveCleanup,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存自动清理'),
              ),
              if (_cleanupNotice != null) Text(_cleanupNotice!),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '自动更新',
            icon: Icons.update,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用自动更新'),
                value: _autoUpdate.enabled,
                onChanged: (value) => setState(() {
                  _autoUpdate = _autoUpdate.copyWith(enabled: value);
                }),
              ),
              TextField(
                controller: _dailyTimeController,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: '每日检查时间',
                  hintText: '03:00',
                ),
              ),
              const SizedBox(height: 8),
              const Text('追更任务', style: TextStyle(fontWeight: FontWeight.w600)),
              if (successfulJobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('暂无可追更的成功任务'),
                ),
              for (final job in successfulJobs)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoUpdate.items.any(
                    (item) => item.jobId == job.id && item.enabled,
                  ),
                  onChanged: (value) =>
                      _toggleAutoUpdateJob(job.id, value == true),
                  title: Text('#${job.sourceId} ${job.title ?? '未命名任务'}'),
                  subtitle: Text(
                    _autoUpdate.items
                            .where((item) => item.jobId == job.id)
                            .firstOrNull
                            ?.lastMessage ??
                        '尚未检查',
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _autoUpdateBusy ? null : _saveAutoUpdate,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _autoUpdateBusy || _autoUpdate.items.isEmpty
                        ? null
                        : _runAutoUpdate,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('立即检查'),
                  ),
                ],
              ),
              if (_autoUpdate.lastRunAt != null)
                Text('上次运行：${_autoUpdate.lastRunAt}'),
              if (_autoUpdateNotice != null) Text(_autoUpdateNotice!),
            ],
          ),
          const SizedBox(height: 12),
          GlassSurface(
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () => _confirmLogout(context),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '轻小说打包器 · 原生 iOS',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool blur;

  const GlassSurface({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blur = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.72),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: surface,
            )
          : surface,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'queued' => ('排队中', Colors.blueGrey),
      'running' => ('下载中', Colors.blue),
      'paused' => ('已暂停', Colors.orange),
      'canceling' => ('取消中', Colors.orange),
      'succeeded' => ('已完成', Colors.green),
      'failed' => ('失败', Colors.red),
      'canceled' => ('已取消', Colors.grey),
      _ => (status, Colors.blueGrey),
    };
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: color, fontSize: 12),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _uploadStatusText(String status, String? error) {
  return switch (status) {
    'pending' => '等待上传',
    'uploading' => '上传中',
    'succeeded' => '上传成功',
    'failed' => error?.isNotEmpty == true ? '失败：$error' : '上传失败',
    _ => '未启用',
  };
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 46),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class ServerAddressDialog extends StatefulWidget {
  final String initialValue;

  const ServerAddressDialog({required this.initialValue, super.key});

  @override
  State<ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<ServerAddressDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = normalizeServerUri(_controller.text);
    if (uri == null) {
      setState(() => _error = '请输入有效的 HTTP 或 HTTPS 地址');
      return;
    }
    Navigator.of(context).pop(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('切换服务器'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: '服务器地址', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('连接')),
      ],
    );
  }
}

class ServerSetupPage extends StatefulWidget {
  final Future<void> Function(String value) onConnect;

  const ServerSetupPage({required this.onConnect, super.key});

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final TextEditingController _serverController = TextEditingController();
  String? _validationError;
  bool _connecting = false;

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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: GlassSurface(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.dns_outlined, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        '连接你的服务器',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '服务器地址只保存在这台设备上',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _serverController,
                        enabled: !_connecting,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'https://server.example.com',
                          errorText: _validationError,
                          prefixIcon: const Icon(Icons.link),
                        ),
                        onSubmitted: (_) => _connect(),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _connecting ? null : _connect,
                        icon: _connecting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: const Text('连接'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

Uri? normalizeServerUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
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

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) {
      return this;
    }
    return sublist(length - count);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
