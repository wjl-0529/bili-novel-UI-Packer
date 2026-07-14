import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'native_models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final Uri baseUri;
  final HttpClient _httpClient = HttpClient();
  String? _cookie;
  void Function()? onUnauthorized;

  ApiClient(this.baseUri);

  bool get hasSession => _cookie != null;

  Future<bool> checkSession() async {
    final payload = await _request('GET', '/api/me');
    return payload['authenticated'] == true;
  }

  Future<void> login(String password) async {
    await _request('POST', '/api/login', body: {'password': password});
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/api/logout');
    } finally {
      _cookie = null;
    }
  }

  Future<List<DownloadJobModel>> getJobs() async {
    final payload = await _request('GET', '/api/jobs');
    final jobs = payload['jobs'];
    if (jobs is! List) {
      return const [];
    }
    return jobs
        .whereType<Map>()
        .map((job) => DownloadJobModel.fromJson(Map<String, dynamic>.from(job)))
        .toList();
  }

  Future<List<DownloadJobModel>> createJobs(JobRequestModel request) async {
    final payload = await _request('POST', '/api/jobs', body: request.toJson());
    final jobs = payload['jobs'];
    if (jobs is! List) {
      return const [];
    }
    return jobs
        .whereType<Map>()
        .map((job) => DownloadJobModel.fromJson(Map<String, dynamic>.from(job)))
        .toList();
  }

  Future<NovelPreviewResponseModel> previewNovel(
    JobRequestModel request,
  ) async {
    final payload = await _request(
      'POST',
      '/api/novel/preview',
      body: request.toJson(),
      timeout: const Duration(minutes: 5),
      timeoutMessage: '搜索耗时较长，服务器仍未返回结果，请稍后重试',
    );
    final rawPreviews = payload['previews'];
    final rawFailures = payload['previewFailures'];
    final previews = <NovelPreviewModel>[];
    if (rawPreviews is List) {
      previews.addAll(
        rawPreviews.whereType<Map>().map(
          (item) => NovelPreviewModel.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
    } else if (payload['preview'] is Map) {
      previews.add(
        NovelPreviewModel.fromJson(
          Map<String, dynamic>.from(payload['preview'] as Map),
        ),
      );
    }
    final failures = rawFailures is List
        ? rawFailures
              .whereType<Map>()
              .map(
                (item) => NovelPreviewFailureModel.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <NovelPreviewFailureModel>[];
    return NovelPreviewResponseModel(previews: previews, failures: failures);
  }

  Future<void> cancelJob(String id) async {
    await _request('POST', '/api/jobs/${Uri.encodeComponent(id)}/cancel');
  }

  Future<void> retryJob(String id) async {
    await _request('POST', '/api/jobs/${Uri.encodeComponent(id)}/retry');
  }

  Future<void> deleteJob(String id) async {
    await _request('DELETE', '/api/jobs/${Uri.encodeComponent(id)}');
  }

  Future<DownloadJobModel> deleteJobOutputs(String id) async {
    final payload = await _request(
      'DELETE',
      '/api/jobs/${Uri.encodeComponent(id)}/outputs',
    );
    final job = payload['job'];
    if (job is! Map) {
      throw const ApiException(500, '服务器没有返回任务信息');
    }
    return DownloadJobModel.fromJson(Map<String, dynamic>.from(job));
  }

  Future<({int deleted, List<DownloadJobModel> jobs})>
  cleanupCompletedJobs() async {
    final payload = await _request('POST', '/api/jobs/cleanup');
    final rawJobs = payload['jobs'];
    final jobs = rawJobs is List
        ? rawJobs
              .whereType<Map>()
              .map(
                (job) =>
                    DownloadJobModel.fromJson(Map<String, dynamic>.from(job)),
              )
              .toList()
        : const <DownloadJobModel>[];
    return (deleted: (payload['deleted'] as num?)?.toInt() ?? 0, jobs: jobs);
  }

  Future<WebDavConfigModel> getWebDavConfig() async {
    final payload = await _request('GET', '/api/webdav/config');
    return WebDavConfigModel.fromJson(
      payload['config'] is Map
          ? Map<String, dynamic>.from(payload['config'] as Map)
          : null,
    );
  }

  Future<WebDavConfigModel> saveWebDavConfig(
    WebDavConfigModel config, {
    bool clearPassword = false,
  }) async {
    final payload = await _request(
      'PUT',
      '/api/webdav/config',
      body: config.toJson(clearPassword: clearPassword),
    );
    return WebDavConfigModel.fromJson(
      payload['config'] is Map
          ? Map<String, dynamic>.from(payload['config'] as Map)
          : null,
    );
  }

  Future<void> testWebDavConfig(WebDavConfigModel config) async {
    await _request(
      'POST',
      '/api/webdav/test',
      body: config.toJson(),
      timeout: const Duration(minutes: 2),
      timeoutMessage: 'WebDAV 测试超时，请检查地址和网络',
    );
  }

  Future<CleanupConfigModel> getCleanupConfig() async {
    final payload = await _request('GET', '/api/cleanup/config');
    return CleanupConfigModel.fromJson(
      payload['config'] is Map
          ? Map<String, dynamic>.from(payload['config'] as Map)
          : null,
    );
  }

  Future<CleanupConfigModel> saveCleanupConfig(
    CleanupConfigModel config,
  ) async {
    final payload = await _request(
      'PUT',
      '/api/cleanup/config',
      body: config.toJson(),
    );
    return CleanupConfigModel.fromJson(
      payload['config'] is Map
          ? Map<String, dynamic>.from(payload['config'] as Map)
          : null,
    );
  }

  Future<AutoUpdateConfigModel> getAutoUpdateConfig() async {
    final payload = await _request('GET', '/api/auto-update/config');
    return AutoUpdateConfigModel.fromJson(
      payload['config'] is Map
          ? Map<String, dynamic>.from(payload['config'] as Map)
          : null,
    );
  }

  Future<AutoUpdateConfigModel> saveAutoUpdateConfig(
    AutoUpdateConfigModel config,
  ) async {
    final payload = await _request(
      'PUT',
      '/api/auto-update/config',
      body: config.toJson(),
    );
    return AutoUpdateConfigModel.fromJson(
      payload['config'] is Map
          ? Map<String, dynamic>.from(payload['config'] as Map)
          : null,
    );
  }

  Future<({AutoUpdateConfigModel config, AutoUpdateRunResultModel result})>
  runAutoUpdateNow() async {
    final payload = await _request(
      'POST',
      '/api/auto-update/run',
      timeout: const Duration(minutes: 10),
      timeoutMessage: '自动更新检查超时，服务器可能仍在检查章节',
    );
    final result = payload['result'] is Map
        ? Map<String, dynamic>.from(payload['result'] as Map)
        : const <String, dynamic>{};
    return (
      config: AutoUpdateConfigModel.fromJson(
        payload['config'] is Map
            ? Map<String, dynamic>.from(payload['config'] as Map)
            : null,
      ),
      result: AutoUpdateRunResultModel(
        checked: (result['checked'] as num?)?.toInt() ?? 0,
        updated: (result['updated'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Future<String> createNativeExport(String jobId, String fileName) async {
    final payload = await _request(
      'POST',
      '/api/native/exports',
      body: {'jobId': jobId, 'fileName': fileName},
    );
    final path = payload['url']?.toString();
    if (path == null || path.isEmpty) {
      throw const ApiException(500, '服务器没有返回文件地址');
    }
    return path;
  }

  Future<Uint8List> downloadCover(String coverUrl, String referer) async {
    final uri = baseUri.resolve(coverUrl);
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 30));
    request.headers.set(
      HttpHeaders.acceptHeader,
      'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 Mobile/15E148',
    );
    if (referer.isNotEmpty) {
      request.headers.set(HttpHeaders.refererHeader, referer);
    }
    if (_isSameOrigin(uri, baseUri)) {
      _applyCookie(request);
    }
    final response = await request.close().timeout(const Duration(minutes: 1));
    if (response.statusCode == HttpStatus.unauthorized) {
      onUnauthorized?.call();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, '封面下载失败（${response.statusCode}）');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > 12 * 1024 * 1024) {
        throw const ApiException(413, '封面文件过大');
      }
    }
    return bytes.takeBytes();
  }

  Future<({File file, bool reused})> downloadExport(
    String relativeUrl,
    String fileName, {
    required Directory directory,
    required Directory cacheDirectory,
    required String cacheKey,
    void Function(int received, int? total)? onProgress,
  }) async {
    await directory.create(recursive: true);
    await cacheDirectory.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${directory.path}/$safeName');
    final markerName = safeName.length > 80
        ? safeName.substring(safeName.length - 80)
        : safeName;
    final cacheMarker = File('${cacheDirectory.path}/$markerName.export-cache');
    try {
      if (await file.exists() && await cacheMarker.exists()) {
        final savedKey = await cacheMarker.readAsString();
        final length = await file.length();
        if (savedKey == cacheKey && length > 0) {
          onProgress?.call(length, length);
          return (file: file, reused: true);
        }
      }
    } catch (_) {
      // A stale cache marker must never block a fresh download.
    }

    final uri = baseUri.resolve(relativeUrl);
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 30));
    _applyCookie(request);
    final response = await request.close().timeout(const Duration(minutes: 2));
    if (response.statusCode != HttpStatus.ok) {
      throw ApiException(response.statusCode, '文件下载失败（${response.statusCode}）');
    }
    final total = response.contentLength >= 0 ? response.contentLength : null;
    final partialFile = File('${directory.path}/.$safeName.part');
    IOSink? sink;
    try {
      sink = partialFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await file.exists()) {
        await file.delete();
      }
      await partialFile.rename(file.path);
      try {
        await cacheMarker.writeAsString(cacheKey, flush: true);
      } catch (_) {
        // Caching is an optimization; the downloaded file is still valid.
      }
    } catch (_) {
      await sink?.close();
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      rethrow;
    }
    return (file: file, reused: false);
  }

  void close() => _httpClient.close(force: true);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
    String timeoutMessage = '连接服务器超时，请检查网络和服务器地址',
  }) async {
    late HttpClientResponse response;
    ApiException? networkError;
    final attempts = method == 'GET' ? 2 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final request = await _httpClient
            .openUrl(method, baseUri.resolve(path))
            .timeout(timeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'BNP-iOS/0.2.54');
        _applyCookie(request);
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        response = await request.close().timeout(timeout);
        networkError = null;
        break;
      } on TimeoutException {
        networkError = ApiException(0, timeoutMessage);
      } on SocketException catch (error) {
        networkError = ApiException(0, '无法连接服务器：${error.message}');
      } on TlsException catch (error) {
        networkError = ApiException(0, 'HTTPS 连接失败：${error.message}');
      } on HttpException catch (error) {
        networkError = ApiException(0, '网络请求失败：${error.message}');
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (networkError != null) {
      throw networkError;
    }

    _captureCookies(response);
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic> payload = <String, dynamic>{};
    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const ApiException(500, '服务器返回了无法解析的数据');
        }
      }
    }
    if (response.statusCode == HttpStatus.unauthorized) {
      onUnauthorized?.call();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          payload['message']?.toString() ?? '请求失败（${response.statusCode}）';
      throw ApiException(response.statusCode, message);
    }
    return payload;
  }

  void _applyCookie(HttpClientRequest request) {
    final cookie = _cookie;
    if (cookie != null && cookie.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }
  }

  bool _isSameOrigin(Uri left, Uri right) {
    int portOf(Uri uri) => uri.hasPort
        ? uri.port
        : uri.scheme == 'https'
        ? 443
        : 80;
    return left.scheme == right.scheme &&
        left.host == right.host &&
        portOf(left) == portOf(right);
  }

  void _captureCookies(HttpClientResponse response) {
    if (response.cookies.isEmpty) {
      return;
    }
    final values = response.cookies.map(
      (cookie) => '${cookie.name}=${cookie.value}',
    );
    _cookie = values.join('; ');
  }
}
