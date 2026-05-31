import 'package:bili_novel_packer/web/job.dart';

String barkDisplayName(DownloadJob job) {
  final title = job.title?.trim();
  if (title != null && title.isNotEmpty) {
    return "《$title》";
  }
  return "小说 #${job.sourceId}";
}

String barkTitle(DownloadJob job, String title) {
  return "$title：${barkDisplayName(job)}";
}

String barkBody(DownloadJob job, String body) {
  return "${barkDisplayName(job)} $body\n${job.url}";
}
