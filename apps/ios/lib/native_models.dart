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
}

class BarkConfigModel {
  final bool enabled;
  final String serverUrl;
  final String deviceKey;
  final BarkEventsModel events;
  final int progressThrottleSeconds;

  const BarkConfigModel({
    this.enabled = false,
    this.serverUrl = 'https://api.day.app',
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
    return JobRequestModel(
      urlTemplate: json['urlTemplate']?.toString() ?? '',
      rangeText: json['rangeText']?.toString() ?? '',
      volumeRangeText: json['volumeRangeText']?.toString() ?? '',
      combineVolume: json['combineVolume'] == true,
      addChapterTitle: json['addChapterTitle'] == true,
      barkConfig: BarkConfigModel(
        enabled: (json['barkConfig'] as Map?)?['enabled'] == true,
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
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final List<String> outputFiles;
  final List<String> logs;

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
    this.createdAt,
    this.finishedAt,
    this.outputFiles = const [],
    this.logs = const [],
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
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
      outputFiles: rawFiles is List
          ? rawFiles.map((value) => value.toString()).toList()
          : const [],
      logs: rawLogs is List
          ? rawLogs.map((value) => value.toString()).toList()
          : const [],
    );
  }
}
