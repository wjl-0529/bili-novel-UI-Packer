class BarkEventsModel {
  final bool start;
  final bool success;
  final bool failure;
  final bool progress;
  final bool update;

  const BarkEventsModel({
    this.start = false,
    this.success = true,
    this.failure = true,
    this.progress = false,
    this.update = true,
  });

  factory BarkEventsModel.fromJson(Map<String, dynamic>? json) {
    return BarkEventsModel(
      start: json?['start'] == true,
      success: json?['success'] != false,
      failure: json?['failure'] != false,
      progress: json?['progress'] == true,
      update: json?['update'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'success': success,
    'failure': failure,
    'progress': progress,
    'update': update,
  };

  BarkEventsModel copyWith({
    bool? start,
    bool? success,
    bool? failure,
    bool? progress,
    bool? update,
  }) {
    return BarkEventsModel(
      start: start ?? this.start,
      success: success ?? this.success,
      failure: failure ?? this.failure,
      progress: progress ?? this.progress,
      update: update ?? this.update,
    );
  }
}

class BarkConfigModel {
  final bool enabled;
  final String serverUrl;
  final String deviceKey;
  final BarkEventsModel events;
  final int progressThrottleSeconds;

  const BarkConfigModel({
    this.enabled = false,
    this.serverUrl = '',
    this.deviceKey = '',
    this.events = const BarkEventsModel(),
    this.progressThrottleSeconds = 300,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'serverUrl': serverUrl,
    'deviceKey': deviceKey,
    'events': events.toJson(),
    'progressThrottleSeconds': progressThrottleSeconds,
  };

  BarkConfigModel copyWith({
    bool? enabled,
    String? serverUrl,
    String? deviceKey,
    BarkEventsModel? events,
    int? progressThrottleSeconds,
  }) {
    return BarkConfigModel(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      deviceKey: deviceKey ?? this.deviceKey,
      events: events ?? this.events,
      progressThrottleSeconds:
          progressThrottleSeconds ?? this.progressThrottleSeconds,
    );
  }
}

class JobRequestModel {
  final String urlTemplate;
  final String rangeText;
  final String volumeRangeText;
  final bool combineVolume;
  final bool addChapterTitle;
  final BarkConfigModel barkConfig;

  const JobRequestModel({
    required this.urlTemplate,
    required this.rangeText,
    this.volumeRangeText = '',
    this.combineVolume = false,
    this.addChapterTitle = false,
    this.barkConfig = const BarkConfigModel(),
  });

  Map<String, dynamic> toJson() => {
    'urlTemplate': urlTemplate,
    'rangeText': rangeText,
    'volumeRangeText': volumeRangeText,
    'combineVolume': combineVolume,
    'addChapterTitle': addChapterTitle,
    'barkConfig': barkConfig.toJson(),
  };

  factory JobRequestModel.fromJson(Map<String, dynamic> json) {
    final bark = json['barkConfig'] is Map
        ? Map<String, dynamic>.from(json['barkConfig'] as Map)
        : const <String, dynamic>{};
    return JobRequestModel(
      urlTemplate: json['urlTemplate']?.toString() ?? '',
      rangeText: json['rangeText']?.toString() ?? '',
      volumeRangeText: json['volumeRangeText']?.toString() ?? '',
      combineVolume: json['combineVolume'] == true,
      addChapterTitle: json['addChapterTitle'] == true,
      barkConfig: BarkConfigModel(
        enabled: bark['enabled'] == true,
        serverUrl: bark['serverUrl']?.toString() ?? '',
        deviceKey: bark['deviceKey']?.toString() ?? '',
        events: BarkEventsModel.fromJson(
          bark['events'] is Map
              ? Map<String, dynamic>.from(bark['events'] as Map)
              : null,
        ),
        progressThrottleSeconds:
            (bark['progressThrottleSeconds'] as num?)?.toInt() ?? 300,
      ),
    );
  }
}

class DownloadJobModel {
  final String id;
  final int sourceId;
  final String url;
  final JobRequestModel request;
  final String status;
  final double progress;
  final String message;
  final String? title;
  final String? author;
  final String? sourceName;
  final String? volumeSummary;
  final String? error;
  final String? outputDir;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final List<String> outputFiles;
  final List<String> logs;
  final String? uploadStatus;
  final List<String> uploadedFiles;
  final String? uploadError;

  const DownloadJobModel({
    required this.id,
    required this.sourceId,
    required this.url,
    required this.request,
    required this.status,
    required this.progress,
    required this.message,
    this.title,
    this.author,
    this.sourceName,
    this.volumeSummary,
    this.error,
    this.outputDir,
    this.createdAt,
    this.finishedAt,
    this.outputFiles = const [],
    this.logs = const [],
    this.uploadStatus,
    this.uploadedFiles = const [],
    this.uploadError,
  });

  factory DownloadJobModel.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['outputFiles'];
    final rawLogs = json['logs'];
    return DownloadJobModel(
      id: json['id']?.toString() ?? '',
      sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
      url: json['url']?.toString() ?? '',
      request: JobRequestModel.fromJson(
        Map<String, dynamic>.from((json['request'] as Map?) ?? const {}),
      ),
      status: json['status']?.toString() ?? 'queued',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      message: json['message']?.toString() ?? '排队中',
      title: json['title']?.toString(),
      author: json['author']?.toString(),
      sourceName: json['sourceName']?.toString(),
      volumeSummary: json['volumeSummary']?.toString(),
      error: json['error']?.toString(),
      outputDir: json['outputDir']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
      outputFiles: rawFiles is List
          ? rawFiles.map((value) => value.toString()).toList()
          : const [],
      logs: rawLogs is List
          ? rawLogs.map((value) => value.toString()).toList()
          : const [],
      uploadStatus: json['uploadStatus']?.toString(),
      uploadedFiles: json['uploadedFiles'] is List
          ? (json['uploadedFiles'] as List)
                .map((value) => value.toString())
                .toList()
          : const [],
      uploadError: json['uploadError']?.toString(),
    );
  }
}

class WebDavConfigModel {
  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String basePath;
  final bool hasPassword;

  const WebDavConfigModel({
    this.enabled = false,
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.basePath = '',
    this.hasPassword = false,
  });

  factory WebDavConfigModel.fromJson(Map<String, dynamic>? json) {
    return WebDavConfigModel(
      enabled: json?['enabled'] == true,
      serverUrl: json?['serverUrl']?.toString() ?? '',
      username: json?['username']?.toString() ?? '',
      password: '',
      basePath: json?['basePath']?.toString() ?? '',
      hasPassword: json?['hasPassword'] == true,
    );
  }

  Map<String, dynamic> toJson({bool clearPassword = false}) => {
    'enabled': enabled,
    'serverUrl': serverUrl,
    'username': username,
    'password': clearPassword ? '' : password,
    'basePath': basePath,
    'clearPassword': clearPassword,
  };

  WebDavConfigModel copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? basePath,
    bool? hasPassword,
  }) {
    return WebDavConfigModel(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      basePath: basePath ?? this.basePath,
      hasPassword: hasPassword ?? this.hasPassword,
    );
  }
}

class CleanupConfigModel {
  final bool enabled;
  final int retentionDays;

  const CleanupConfigModel({this.enabled = false, this.retentionDays = 7});

  factory CleanupConfigModel.fromJson(Map<String, dynamic>? json) {
    return CleanupConfigModel(
      enabled: json?['enabled'] == true,
      retentionDays: (json?['retentionDays'] as num?)?.toInt() ?? 7,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'retentionDays': retentionDays,
  };

  CleanupConfigModel copyWith({bool? enabled, int? retentionDays}) {
    return CleanupConfigModel(
      enabled: enabled ?? this.enabled,
      retentionDays: retentionDays ?? this.retentionDays,
    );
  }
}

class AutoUpdateItemModel {
  final String jobId;
  final bool enabled;
  final String? lastCheckedAt;
  final String? lastUpdatedAt;
  final String? lastStatus;
  final String? lastMessage;

  const AutoUpdateItemModel({
    required this.jobId,
    this.enabled = true,
    this.lastCheckedAt,
    this.lastUpdatedAt,
    this.lastStatus,
    this.lastMessage,
  });

  factory AutoUpdateItemModel.fromJson(Map<String, dynamic> json) {
    return AutoUpdateItemModel(
      jobId: json['jobId']?.toString() ?? '',
      enabled: json['enabled'] != false,
      lastCheckedAt: json['lastCheckedAt']?.toString(),
      lastUpdatedAt: json['lastUpdatedAt']?.toString(),
      lastStatus: json['lastStatus']?.toString(),
      lastMessage: json['lastMessage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'enabled': enabled,
    'lastCheckedAt': lastCheckedAt,
    'lastUpdatedAt': lastUpdatedAt,
    'lastStatus': lastStatus,
    'lastMessage': lastMessage,
  };
}

class AutoUpdateConfigModel {
  final bool enabled;
  final String dailyTime;
  final String? lastRunAt;
  final List<AutoUpdateItemModel> items;

  const AutoUpdateConfigModel({
    this.enabled = false,
    this.dailyTime = '03:00',
    this.lastRunAt,
    this.items = const [],
  });

  factory AutoUpdateConfigModel.fromJson(Map<String, dynamic>? json) {
    final rawItems = json?['items'];
    return AutoUpdateConfigModel(
      enabled: json?['enabled'] == true,
      dailyTime: json?['dailyTime']?.toString() ?? '03:00',
      lastRunAt: json?['lastRunAt']?.toString(),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => AutoUpdateItemModel.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'dailyTime': dailyTime,
    'lastRunAt': lastRunAt,
    'items': items.map((item) => item.toJson()).toList(),
  };

  AutoUpdateConfigModel copyWith({
    bool? enabled,
    String? dailyTime,
    String? lastRunAt,
    List<AutoUpdateItemModel>? items,
  }) {
    return AutoUpdateConfigModel(
      enabled: enabled ?? this.enabled,
      dailyTime: dailyTime ?? this.dailyTime,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      items: items ?? this.items,
    );
  }
}

class NovelPreviewModel {
  final int sourceId;
  final String id;
  final String url;
  final String sourceName;
  final String title;
  final String? alias;
  final String author;
  final String status;
  final String? coverUrl;
  final List<String> tags;
  final String? publisher;
  final String? description;
  final int? volumeCount;
  final int? chapterCount;

  const NovelPreviewModel({
    required this.sourceId,
    required this.id,
    required this.url,
    required this.sourceName,
    required this.title,
    required this.author,
    required this.status,
    this.alias,
    this.coverUrl,
    this.tags = const [],
    this.publisher,
    this.description,
    this.volumeCount,
    this.chapterCount,
  });

  factory NovelPreviewModel.fromJson(Map<String, dynamic> json) {
    return NovelPreviewModel(
      sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名小说',
      alias: json['alias']?.toString(),
      author: json['author']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString(),
      tags: json['tags'] is List
          ? (json['tags'] as List).map((value) => value.toString()).toList()
          : const [],
      publisher: json['publisher']?.toString(),
      description: json['description']?.toString(),
      volumeCount: (json['volumeCount'] as num?)?.toInt(),
      chapterCount: (json['chapterCount'] as num?)?.toInt(),
    );
  }
}

class NovelPreviewFailureModel {
  final int sourceId;
  final String url;
  final String message;

  const NovelPreviewFailureModel({
    required this.sourceId,
    required this.url,
    required this.message,
  });

  factory NovelPreviewFailureModel.fromJson(Map<String, dynamic> json) {
    return NovelPreviewFailureModel(
      sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
      url: json['url']?.toString() ?? '',
      message: json['message']?.toString() ?? '未知错误',
    );
  }
}

class NovelPreviewResponseModel {
  final List<NovelPreviewModel> previews;
  final List<NovelPreviewFailureModel> failures;

  const NovelPreviewResponseModel({
    this.previews = const [],
    this.failures = const [],
  });
}

class AutoUpdateRunResultModel {
  final int checked;
  final int updated;

  const AutoUpdateRunResultModel({this.checked = 0, this.updated = 0});
}
