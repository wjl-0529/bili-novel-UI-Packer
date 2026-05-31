import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class CleanupConfig {
  static const int defaultRetentionDays = 7;
  static const int minRetentionDays = 1;
  static const int maxRetentionDays = 365;

  final bool enabled;
  final int retentionDays;

  const CleanupConfig({
    this.enabled = false,
    this.retentionDays = defaultRetentionDays,
  });

  factory CleanupConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CleanupConfig();
    }
    return CleanupConfig(
      enabled: json["enabled"] == true,
      retentionDays: _normalizeRetentionDays(json["retentionDays"]),
    );
  }

  Map<String, dynamic> toJson() => {
        "enabled": enabled,
        "retentionDays": retentionDays,
      };
}

class CleanupConfigStore {
  final File _file;

  CleanupConfigStore(String dataDir)
      : _file = File(path.join(dataDir, "cleanup-config.json"));

  Future<CleanupConfig> load() async {
    if (!await _file.exists()) {
      return const CleanupConfig();
    }
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return const CleanupConfig();
    }
    return CleanupConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<CleanupConfig> save(CleanupConfig config) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent("  ");
    await _file.writeAsString(encoder.convert(config.toJson()));
    return config;
  }

  Future<CleanupConfig> saveFromPayload(Map<String, dynamic> payload) async {
    final current = await load();
    return save(CleanupConfig(
      enabled: payload["enabled"] == true,
      retentionDays: _normalizeRetentionDays(
        payload["retentionDays"],
        fallback: current.retentionDays,
      ),
    ));
  }
}

int _normalizeRetentionDays(
  Object? value, {
  int fallback = CleanupConfig.defaultRetentionDays,
}) {
  int? days;
  if (value is num) {
    days = value.round();
  } else if (value is String) {
    days = int.tryParse(value.trim());
  }
  final next = days ?? fallback;
  return next
      .clamp(
        CleanupConfig.minRetentionDays,
        CleanupConfig.maxRetentionDays,
      )
      .toInt();
}
