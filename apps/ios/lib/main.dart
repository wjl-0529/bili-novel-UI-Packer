import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'native_models.dart';

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
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff0f766e),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: '轻小说打包器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xfff5f7f9),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
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
  Uri _serverUri = Uri.parse(remoteServerUri);
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
    await _loadSavedServerUri();
    await _connect(_serverUri, persist: false);
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
      if (persist) {
        await _saveServerUri(uri);
      }
      final authenticated = await api.checkSession();
      if (!mounted || !identical(_api, api)) {
        api.close();
        return;
      }
      setState(() {
        _authenticated = authenticated;
        _loading = false;
      });
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

  Future<void> _loadSavedServerUri() async {
    try {
      final file = await _serverConfigFile();
      if (await file.exists()) {
        final saved = normalizeServerUri(await file.readAsString());
        if (saved != null) {
          _serverUri = saved;
        }
      }
    } catch (_) {
      // The build-time URL remains the fallback when storage is unavailable.
    }
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
    if (_startupError != null || api == null) {
      return StartupErrorPage(
        error: _startupError ?? StateError('服务器未初始化'),
        serverUrl: _serverUri.toString(),
        onConnect: _changeServer,
        onRetry: () => unawaited(_boot()),
      );
    }
    if (!_authenticated) {
      return LoginPage(
        serverUri: _serverUri,
        onLogin: _login,
        onChangeServer: _showServerDialog,
      );
    }
    return NativeHomePage(
      api: api,
      serverUri: _serverUri,
      onLogout: _logout,
      onChangeServer: _changeServer,
    );
  }

  Future<void> _showServerDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          ServerAddressDialog(initialValue: _serverUri.toString()),
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
  final Uri serverUri;
  final Future<void> Function(String password) onLogin;
  final Future<void> Function() onChangeServer;

  const LoginPage({
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
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
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
    try {
      await widget.onLogin(_passwordController.text);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                color: Colors.white,
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
                      TextButton.icon(
                        onPressed: _busy ? null : widget.onChangeServer,
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
  final Uri serverUri;
  final Future<void> Function() onLogout;
  final Future<void> Function(String value) onChangeServer;

  const NativeHomePage({
    required this.api,
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

  void _openJobs() {
    setState(() => _index = 1);
    unawaited(_jobsKey.currentState?.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DownloadPage(api: widget.api, onCreated: _openJobs),
      JobsPage(key: _jobsKey, api: widget.api),
      SettingsPage(
        serverUri: widget.serverUri,
        onLogout: widget.onLogout,
        onChangeServer: widget.onChangeServer,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() => _index = index);
          if (index == 1) {
            unawaited(_jobsKey.currentState?.refresh());
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: '任务',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
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
  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: 'https://www.bilinovel.com/novel/{id}.html',
    );
    _rangeController = TextEditingController(text: '1-3');
    _volumeController = TextEditingController();
    _barkServerController = TextEditingController(text: 'https://api.day.app');
    _barkKeyController = TextEditingController();
  }

  @override
  void dispose() {
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
    final request = JobRequestModel(
      urlTemplate: template,
      rangeText: range,
      volumeRangeText: _volumeController.text.trim(),
      combineVolume: _combineVolume,
      addChapterTitle: _addChapterTitle,
      barkConfig: BarkConfigModel(
        enabled: _barkEnabled,
        serverUrl: _barkServerController.text.trim(),
        deviceKey: _barkKeyController.text.trim(),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建下载任务')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
              ],
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务队列'),
        actions: [
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _jobs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final job = _jobs[index];
                  return JobCard(
                    job: job,
                    onTap: () => _openDetails(job),
                    onCancel: () => _runAction(job, widget.api.cancelJob),
                    onRetry: () => _runAction(job, widget.api.retryJob),
                    onDelete: () => _runAction(job, widget.api.deleteJob),
                  );
                },
              ),
            ),
    );
  }
}

class JobCard extends StatelessWidget {
  final DownloadJobModel job;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const JobCard({
    required this.job,
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
    return Card(
      color: Colors.white,
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
                job.error?.isNotEmpty == true ? job.error! : job.message,
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

  Future<void> _shareFile(String fileName) async {
    setState(() => _busyFile = fileName);
    File? file;
    try {
      final exportUrl = await widget.api.createNativeExport(
        widget.job.id,
        fileName,
      );
      file = await widget.api.downloadExport(exportUrl, fileName);
      if (!mounted) {
        return;
      }
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
      if (file != null) {
        try {
          final directory = file.parent;
          await file.delete();
          await directory.delete();
        } catch (_) {
          // Temporary cleanup is best effort after the share sheet returns.
        }
      }
      if (mounted) {
        setState(() => _busyFile = null);
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
                    tooltip: '分享文件',
                    onPressed: _busyFile == null
                        ? () => _shareFile(file)
                        : null,
                    icon: _busyFile == file
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share),
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

class SettingsPage extends StatelessWidget {
  final Uri serverUri;
  final Future<void> Function() onLogout;
  final Future<void> Function(String value) onChangeServer;

  const SettingsPage({
    required this.serverUri,
    required this.onLogout,
    required this.onChangeServer,
    super.key,
  });

  Future<void> _changeServer(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) =>
          ServerAddressDialog(initialValue: serverUri.toString()),
    );
    if (selected == null || !context.mounted) {
      return;
    }
    try {
      await onChangeServer(selected);
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
      await onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('服务器地址'),
              subtitle: Text(serverUri.toString()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changeServer(context),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
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
    return Card(
      color: Colors.white,
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
