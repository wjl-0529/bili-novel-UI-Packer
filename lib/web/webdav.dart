import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class WebDavConfig {
  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String basePath;

  const WebDavConfig({
    this.enabled = false,
    this.serverUrl = "",
    this.username = "",
    this.password = "",
    this.basePath = "",
  });

  bool get hasPassword => password.isNotEmpty;

  bool get isReady =>
      enabled &&
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  factory WebDavConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const WebDavConfig();
    }
    return WebDavConfig(
      enabled: json["enabled"] == true,
      serverUrl: (json["serverUrl"] as String?)?.trim() ?? "",
      username: (json["username"] as String?)?.trim() ?? "",
      password: (json["password"] as String?) ?? "",
      basePath: _normalizeBasePath(
        (json["basePath"] as String?)?.trim() ?? "",
      ),
    );
  }

  WebDavConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? basePath,
  }) {
    return WebDavConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      basePath: basePath ?? this.basePath,
    );
  }

  Map<String, dynamic> toJson() => {
    "enabled": enabled,
    "serverUrl": serverUrl,
    "username": username,
    "password": password,
    "basePath": basePath,
  };

  Map<String, dynamic> toSafeJson() => {
    "enabled": enabled,
    "serverUrl": serverUrl,
    "username": username,
    "basePath": basePath,
    "hasPassword": hasPassword,
  };
}

class WebDavConfigStore {
  final File _file;

  WebDavConfigStore(String dataDir)
    : _file = File(path.join(dataDir, "webdav-config.json"));

  Future<WebDavConfig> load() async {
    if (!await _file.exists()) {
      return const WebDavConfig();
    }
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return const WebDavConfig();
    }
    return WebDavConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<WebDavConfig> save(WebDavConfig config) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent("  ");
    await _file.writeAsString(encoder.convert(config.toJson()));
    return config;
  }

  Future<WebDavConfig> saveFromPayload(Map<String, dynamic> payload) async {
    final current = await load();
    final clearPassword = payload["clearPassword"] == true;
    final passwordInput = payload["password"] as String?;
    final nextPassword = clearPassword
        ? ""
        : passwordInput != null && passwordInput.isNotEmpty
        ? passwordInput
        : current.password;
    return save(
      WebDavConfig(
        enabled: payload["enabled"] == true,
        serverUrl: (payload["serverUrl"] as String?)?.trim() ?? "",
        username: (payload["username"] as String?)?.trim() ?? "",
        password: nextPassword,
        basePath: _normalizeBasePath(
          (payload["basePath"] as String?)?.trim() ?? current.basePath,
        ),
      ),
    );
  }
}

class WebDavUploadResult {
  final List<String> remoteFiles;

  const WebDavUploadResult(this.remoteFiles);
}

class WebDavException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  WebDavException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() {
    if (statusCode == null) {
      return message;
    }
    return "$message (HTTP $statusCode)";
  }
}

class WebDavClient {
  final http.Client _client;
  final Duration timeout;

  WebDavClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  void close() => _client.close();

  Future<void> test(WebDavConfig config) async {
    _validate(config);
    await _ensureDirectory(config, _splitRemotePath(config.basePath));
  }

  Future<WebDavUploadResult> uploadFiles({
    required WebDavConfig config,
    required int sourceId,
    required String jobId,
    required String? title,
    required List<File> files,
  }) async {
    _validate(config);
    final folder = _jobFolderName(sourceId, title, jobId);
    final baseSegments = _splitRemotePath(config.basePath);
    final folderSegments = [...baseSegments, folder];
    await _ensureDirectory(config, folderSegments);

    final remoteFiles = <String>[];
    for (final file in files) {
      if (!await file.exists()) {
        throw WebDavException("本地输出文件不存在：${file.path}");
      }
      final remoteSegments = [...folderSegments, path.basename(file.path)];
      final uri = _resolve(config, remoteSegments);
      final response = await _send(
        config,
        "PUT",
        uri,
        bodyBytes: await file.readAsBytes(),
        headers: {"content-type": "application/epub+zip"},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WebDavException(
          "WebDAV 上传失败：${path.basename(file.path)}",
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
      remoteFiles.add(_displayPath(remoteSegments));
    }
    return WebDavUploadResult(remoteFiles);
  }

  Future<void> deleteDisplayPath(
    WebDavConfig config,
    String displayPath,
  ) async {
    _validate(config);
    final segments = _splitRemotePath(displayPath);
    if (segments.isEmpty) {
      return;
    }
    final response = await _send(config, "DELETE", _resolve(config, segments));
    if (response.statusCode == 200 ||
        response.statusCode == 202 ||
        response.statusCode == 204 ||
        response.statusCode == 404) {
      return;
    }
    throw WebDavException(
      "WebDAV 删除失败：$displayPath",
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  void _validate(WebDavConfig config) {
    if (!config.enabled) {
      throw WebDavException("WebDAV 未启用");
    }
    if (config.serverUrl.trim().isEmpty) {
      throw WebDavException("WebDAV 服务地址不能为空");
    }
    if (config.username.trim().isEmpty) {
      throw WebDavException("WebDAV 用户名不能为空");
    }
    if (config.password.isEmpty) {
      throw WebDavException("WebDAV 密码不能为空");
    }
    final uri = Uri.tryParse(config.serverUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw WebDavException("WebDAV 服务地址格式不正确");
    }
  }

  Future<void> _ensureDirectory(
    WebDavConfig config,
    List<String> segments,
  ) async {
    final current = <String>[];
    for (final segment in segments) {
      current.add(segment);
      final response = await _send(config, "MKCOL", _resolve(config, current));
      if (response.statusCode == 201 ||
          response.statusCode == 200 ||
          response.statusCode == 405) {
        continue;
      }
      throw WebDavException(
        "WebDAV 创建目录失败：${_displayPath(current)}",
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  Future<http.Response> _send(
    WebDavConfig config,
    String method,
    Uri uri, {
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(_authHeaders(config))
      ..headers.addAll(headers ?? {});
    if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    }
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed);
  }

  Map<String, String> _authHeaders(WebDavConfig config) {
    final token = base64Encode(
      utf8.encode("${config.username}:${config.password}"),
    );
    return {"authorization": "Basic $token"};
  }

  Uri _resolve(WebDavConfig config, List<String> remoteSegments) {
    final base = Uri.parse(config.serverUrl.trim());
    final baseSegments = base.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    return base.replace(
      pathSegments: [...baseSegments, ...remoteSegments],
      query: "",
      fragment: "",
    );
  }
}

String _jobFolderName(int sourceId, String? title, String jobId) {
  final readableTitle = _sanitizeSegment(
    title == null || title.trim().isEmpty ? "untitled" : title,
  );
  final shortJobId = jobId.length <= 8 ? jobId : jobId.substring(0, 8);
  return _sanitizeSegment("$sourceId-$readableTitle-$shortJobId");
}

String _sanitizeSegment(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), "_")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
  if (cleaned.isEmpty) {
    return "untitled";
  }
  final runes = cleaned.runes.toList();
  if (runes.length <= 80) {
    return cleaned;
  }
  return String.fromCharCodes(runes.take(80));
}

String _normalizeBasePath(String value) {
  final segments = _splitRemotePath(value);
  if (segments.isEmpty) {
    return "";
  }
  return _displayPath(segments);
}

List<String> _splitRemotePath(String value) {
  return value
      .split("/")
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
}

String _displayPath(List<String> segments) => "/${segments.join("/")}";
