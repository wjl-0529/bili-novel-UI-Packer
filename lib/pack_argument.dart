import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/pack_progress.dart';

class PackArgument {
  late bool addChapterTitle;

  bool combineVolume = false;

  late List<Volume> packVolumes;

  String? outputDirectory;

  PackProgressCallback? onProgress;

  PackArgument();

  PackArgument.all({
    required this.addChapterTitle,
    required this.combineVolume,
    required this.packVolumes,
    this.outputDirectory,
    this.onProgress,
  });

  @override
  String toString() {
    return 'PackArgument{addChapterTitle: $addChapterTitle, combineVolume: $combineVolume, packVolumes: $packVolumes, outputDirectory: $outputDirectory}';
  }
}
