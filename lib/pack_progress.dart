import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';

typedef PackProgressCallback = void Function(PackProgressEvent event);

class PackProgressEvent {
  final String type;
  final String message;
  final String? filePath;
  final Novel? novel;
  final Volume? volume;
  final Chapter? chapter;
  final int? completed;
  final int? total;

  const PackProgressEvent({
    required this.type,
    required this.message,
    this.filePath,
    this.novel,
    this.volume,
    this.chapter,
    this.completed,
    this.total,
  });

  double? get ratio {
    if (completed == null || total == null || total == 0) {
      return null;
    }
    return completed! / total!;
  }
}
