import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class AutoUpdateConfig {
  static const String defaultDailyTime = "03:00";

  final bool enabled;
  final String dailyTime;
  final DateTime? lastRunAt;
  final List<AutoUpdateItem> items;

  const AutoUpdateConfig({
    this.enabled = false,
    this.dailyTime = defaultDailyTime,
    this.lastRunAt,
    this.items = const [],
  });

  factory AutoUpdateConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AutoUpdateConfig();
    }
    return AutoUpdateConfig(
      enabled: json["enabled"] == true,
      dailyTime: normalizeDailyTime(json["dailyTime"]),
      lastRunAt: _parseDate(json["lastRunAt"]),
      items: (json["items"] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AutoUpdateItem.fromJson)
          .where((item) => item.jobId.isNotEmpty)
          .toList(),
    );
  }

  AutoUpdateConfig copyWith({
    bool? enabled,
    String? dailyTime,
    DateTime? lastRunAt,
    List<AutoUpdateItem>? items,
  }) {
    return AutoUpdateConfig(
      enabled: enabled ?? this.enabled,
      dailyTime: dailyTime ?? this.dailyTime,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() => {
        "enabled": enabled,
        "dailyTime": dailyTime,
        "lastRunAt": lastRunAt?.toIso8601String(),
        "items": items.map((item) => item.toJson()).toList(),
      };
}

class AutoUpdateItem {
  final String jobId;
  final bool enabled;
  final String? baselineFingerprint;
  final DateTime? lastCheckedAt;
  final DateTime? lastUpdatedAt;
  final String? lastStatus;
  final String? lastMessage;

  const AutoUpdateItem({
    required this.jobId,
    this.enabled = true,
    this.baselineFingerprint,
    this.lastCheckedAt,
    this.lastUpdatedAt,
    this.lastStatus,
    this.lastMessage,
  });

  factory AutoUpdateItem.fromJson(Map<String, dynamic> json) {
    return AutoUpdateItem(
      jobId: (json["jobId"] as String?)?.trim() ?? "",
      enabled: json["enabled"] != false,
      baselineFingerprint: json["baselineFingerprint"] as String?,
      lastCheckedAt: _parseDate(json["lastCheckedAt"]),
      lastUpdatedAt: _parseDate(json["lastUpdatedAt"]),
      lastStatus: json["lastStatus"] as String?,
      lastMessage: json["lastMessage"] as String?,
    );
  }

  AutoUpdateItem copyWith({
    bool? enabled,
    String? baselineFingerprint,
    DateTime? lastCheckedAt,
    DateTime? lastUpdatedAt,
    String? lastStatus,
    String? lastMessage,
  }) {
    return AutoUpdateItem(
      jobId: jobId,
      enabled: enabled ?? this.enabled,
      baselineFingerprint: baselineFingerprint ?? this.baselineFingerprint,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastStatus: lastStatus ?? this.lastStatus,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        "jobId": jobId,
        "enabled": enabled,
        "baselineFingerprint": baselineFingerprint,
        "lastCheckedAt": lastCheckedAt?.toIso8601String(),
        "lastUpdatedAt": lastUpdatedAt?.toIso8601String(),
        "lastStatus": lastStatus,
        "lastMessage": lastMessage,
      };
}

class AutoUpdateConfigStore {
  final File _file;

  AutoUpdateConfigStore(String dataDir)
      : _file = File(path.join(dataDir, "auto-update-config.json"));

  Future<AutoUpdateConfig> load() async {
    if (!await _file.exists()) {
      return const AutoUpdateConfig();
    }
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return const AutoUpdateConfig();
    }
    return AutoUpdateConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<AutoUpdateConfig> save(AutoUpdateConfig config) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent("  ");
    await _file.writeAsString(encoder.convert(config.toJson()));
    return config;
  }

  Future<AutoUpdateConfig> saveFromPayload(
    Map<String, dynamic> payload, {
    Set<String>? allowedJobIds,
  }) async {
    final current = await load();
    final currentById = {for (final item in current.items) item.jobId: item};
    final incomingItems = (payload["items"] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AutoUpdateItem.fromJson)
        .where((item) => item.jobId.isNotEmpty)
        .where((item) =>
            allowedJobIds == null || allowedJobIds.contains(item.jobId))
        .map((item) {
      final previous = currentById[item.jobId];
      if (previous == null) {
        return item;
      }
      return AutoUpdateItem(
        jobId: item.jobId,
        enabled: item.enabled,
        baselineFingerprint: previous.baselineFingerprint,
        lastCheckedAt: previous.lastCheckedAt,
        lastUpdatedAt: previous.lastUpdatedAt,
        lastStatus: previous.lastStatus,
        lastMessage: previous.lastMessage,
      );
    }).toList();

    return save(AutoUpdateConfig(
      enabled: payload["enabled"] == true,
      dailyTime: normalizeDailyTime(payload["dailyTime"]),
      lastRunAt: current.lastRunAt,
      items: incomingItems,
    ));
  }
}

String normalizeDailyTime(Object? value) {
  final text = value?.toString().trim() ?? "";
  final match = RegExp(r"^(\d{1,2}):(\d{2})$").firstMatch(text);
  if (match == null) {
    return AutoUpdateConfig.defaultDailyTime;
  }
  final hour = int.tryParse(match.group(1)!) ?? -1;
  final minute = int.tryParse(match.group(2)!) ?? -1;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return AutoUpdateConfig.defaultDailyTime;
  }
  return "${hour.toString().padLeft(2, "0")}:${minute.toString().padLeft(2, "0")}";
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
