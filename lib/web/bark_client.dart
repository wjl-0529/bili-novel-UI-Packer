import 'dart:convert';

import 'package:http/http.dart' as http;

class BarkEvents {
  final bool start;
  final bool success;
  final bool failure;
  final bool progress;
  final bool update;

  const BarkEvents({
    this.start = false,
    this.success = false,
    this.failure = true,
    this.progress = false,
    this.update = true,
  });

  factory BarkEvents.fromJson(Map<String, dynamic>? json) {
    return BarkEvents(
      start: json?["start"] == true,
      success: json?["success"] == true,
      failure: json?["failure"] != false,
      progress: json?["progress"] == true,
      update: json?["update"] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    "start": start,
    "success": success,
    "failure": failure,
    "progress": progress,
    "update": update,
  };

  bool allows(String event) {
    return switch (event) {
      "start" => start,
      "success" => success,
      "failure" => failure,
      "progress" => progress,
      "update" => update,
      _ => false,
    };
  }
}

class BarkConfig {
  final bool enabled;
  final String serverUrl;
  final String deviceKey;
  final BarkEvents events;
  final int progressThrottleSeconds;

  const BarkConfig({
    this.enabled = false,
    this.serverUrl = "",
    this.deviceKey = "",
    this.events = const BarkEvents(),
    this.progressThrottleSeconds = 300,
  });

  factory BarkConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BarkConfig();
    }
    return BarkConfig(
      enabled: json["enabled"] == true,
      serverUrl: (json["serverUrl"] as String?)?.trim() ?? "",
      deviceKey: (json["deviceKey"] as String?)?.trim() ?? "",
      events: BarkEvents.fromJson(json["events"] as Map<String, dynamic>?),
      progressThrottleSeconds:
          (json["progressThrottleSeconds"] as num?)?.toInt() ?? 300,
    );
  }

  Map<String, dynamic> toJson() => {
    "enabled": enabled,
    "serverUrl": serverUrl,
    "deviceKey": deviceKey,
    "events": events.toJson(),
    "progressThrottleSeconds": progressThrottleSeconds,
  };
}

class BarkClient {
  final http.Client _client;

  BarkClient({http.Client? client}) : _client = client ?? http.Client();

  void close() => _client.close();

  Future<bool> notify({
    required BarkConfig config,
    required String event,
    required String title,
    required String body,
  }) async {
    if (!config.enabled ||
        config.deviceKey.isEmpty ||
        !config.events.allows(event)) {
      return false;
    }

    final serverUrl = config.serverUrl.endsWith("/")
        ? config.serverUrl
        : "${config.serverUrl}/";
    final uri = Uri.parse(
      serverUrl,
    ).resolve(Uri.encodeComponent(config.deviceKey));

    try {
      final response = await _client
          .post(
            uri,
            headers: {"content-type": "application/json"},
            body: jsonEncode({
              "title": title,
              "body": body,
              "group": "轻小说打包器",
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
