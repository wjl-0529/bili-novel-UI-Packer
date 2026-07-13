import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  Future<void> cancelJob(String id) async {
    await _request('POST', '/api/jobs/${Uri.encodeComponent(id)}/cancel');
  }

  Future<void> retryJob(String id) async {
    await _request('POST', '/api/jobs/${Uri.encodeComponent(id)}/retry');
  }

  Future<void> deleteJob(String id) async {
    await _request('DELETE', '/api/jobs/${Uri.encodeComponent(id)}');
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

  Future<File> downloadExport(String relativeUrl, String fileName) async {
    final uri = baseUri.resolve(relativeUrl);
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 30));
    _applyCookie(request);
    final response = await request.close().timeout(const Duration(minutes: 2));
    if (response.statusCode != HttpStatus.ok) {
      throw ApiException(response.statusCode, '文件下载失败（${response.statusCode}）');
    }
    final directory = await Directory.systemTemp.createTemp('bnp-export-');
    final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${directory.path}/$safeName');
    await response.pipe(file.openWrite());
    return file;
  }

  void close() => _httpClient.close(force: true);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    HttpClientResponse response;
    try {
      final request = await _httpClient.openUrl(method, baseUri.resolve(path));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      _applyCookie(request);
      response = await request.close().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const ApiException(0, '连接服务器超时，请检查网络和服务器地址');
    } on SocketException catch (error) {
      throw ApiException(0, '无法连接服务器：${error.message}');
    } on HttpException catch (error) {
      throw ApiException(0, '网络请求失败：${error.message}');
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
