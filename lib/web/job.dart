import 'package:bili_novel_packer/web/bark_client.dart';
import 'package:bili_novel_packer/web/webdav.dart';

class JobRequest {
  final String urlTemplate;
  final String rangeText;
  final String volumeRangeText;
  final bool combineVolume;
  final bool addChapterTitle;
  final BarkConfig barkConfig;

  const JobRequest({
    required this.urlTemplate,
    required this.rangeText,
    required this.volumeRangeText,
    required this.combineVolume,
    required this.addChapterTitle,
    required this.barkConfig,
  });

  factory JobRequest.fromJson(Map<String, dynamic> json) {
    return JobRequest(
      urlTemplate: (json["urlTemplate"] as String?)?.trim() ?? "",
      rangeText: (json["rangeText"] as String?)?.trim() ?? "",
      volumeRangeText: (json["volumeRangeText"] as String?)?.trim() ?? "",
      combineVolume: json["combineVolume"] == true,
      addChapterTitle: json["addChapterTitle"] == true,
      barkConfig:
          BarkConfig.fromJson(json["barkConfig"] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
        "urlTemplate": urlTemplate,
        "rangeText": rangeText,
        "volumeRangeText": volumeRangeText,
        "combineVolume": combineVolume,
        "addChapterTitle": addChapterTitle,
        "barkConfig": barkConfig.toJson(),
      };
}

class DownloadJob {
  final String id;
  final int sourceId;
  final String url;
  final JobRequest request;
  String status;
  double progress;
  String message;
  String? title;
  String? author;
  String? sourceName;
  String? volumeSummary;
  String? error;
  DateTime createdAt;
  DateTime? startedAt;
  DateTime? finishedAt;
  List<String> outputFiles;
  WebDavConfig? webDavConfig;
  String uploadStatus;
  List<String> uploadedFiles;
  String? uploadError;
  List<String> logs;

  DownloadJob({
    required this.id,
    required this.sourceId,
    required this.url,
    required this.request,
    this.status = "queued",
    this.progress = 0,
    this.message = "已排队",
    this.title,
    this.author,
    this.sourceName,
    this.volumeSummary,
    this.error,
    DateTime? createdAt,
    this.startedAt,
    this.finishedAt,
    List<String>? outputFiles,
    this.webDavConfig,
    this.uploadStatus = "disabled",
    List<String>? uploadedFiles,
    this.uploadError,
    List<String>? logs,
  })  : createdAt = createdAt ?? DateTime.now(),
        outputFiles = outputFiles ?? [],
        uploadedFiles = uploadedFiles ?? [],
        logs = logs ?? [];

  factory DownloadJob.fromJson(Map<String, dynamic> json) {
    return DownloadJob(
      id: json["id"] as String,
      sourceId: json["sourceId"] as int,
      url: json["url"] as String,
      request: JobRequest.fromJson(json["request"] as Map<String, dynamic>),
      status: json["status"] as String? ?? "queued",
      progress: (json["progress"] as num?)?.toDouble() ?? 0,
      message: json["message"] as String? ?? "已排队",
      title: json["title"] as String?,
      author: json["author"] as String?,
      sourceName: json["sourceName"] as String?,
      volumeSummary: json["volumeSummary"] as String?,
      error: json["error"] as String?,
      createdAt: DateTime.parse(json["createdAt"] as String),
      startedAt: _parseDate(json["startedAt"]),
      finishedAt: _parseDate(json["finishedAt"]),
      outputFiles: (json["outputFiles"] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
      webDavConfig: json["webDavConfig"] is Map<String, dynamic>
          ? WebDavConfig.fromJson(json["webDavConfig"] as Map<String, dynamic>)
          : null,
      uploadStatus: json["uploadStatus"] as String? ?? "disabled",
      uploadedFiles: (json["uploadedFiles"] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
      uploadError: json["uploadError"] as String?,
      logs: (json["logs"] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson({bool includeSecrets = true}) => {
        "id": id,
        "sourceId": sourceId,
        "url": url,
        "request": request.toJson(),
        "status": status,
        "progress": progress,
        "message": message,
        "title": title,
        "author": author,
        "sourceName": sourceName,
        "volumeSummary": volumeSummary,
        "error": error,
        "createdAt": createdAt.toIso8601String(),
        "startedAt": startedAt?.toIso8601String(),
        "finishedAt": finishedAt?.toIso8601String(),
        "outputFiles": outputFiles,
        "webDavConfig": includeSecrets
            ? webDavConfig?.toJson()
            : webDavConfig?.toSafeJson(),
        "uploadStatus": uploadStatus,
        "uploadedFiles": uploadedFiles,
        "uploadError": uploadError,
        "logs": logs,
      };

  void addLog(String message) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    logs.add("[$time] $message");
    if (logs.length > 200) {
      logs = logs.sublist(logs.length - 200);
    }
    this.message = message;
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
