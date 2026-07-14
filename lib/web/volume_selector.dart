import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/web/range_parser.dart';

List<Volume> selectVolumes(Catalog catalog, String rangeText) {
  if (rangeText.trim().isEmpty || rangeText.trim() == "0") {
    return catalog.volumes;
  }
  final indexes = parseIntegerRange(
    rangeText,
    maxValue: catalog.volumes.length,
  );
  return indexes.map((index) => catalog.volumes[index - 1]).toList();
}

String volumeSummary(List<Volume> volumes) {
  if (volumes.isEmpty) {
    return "未选择分卷";
  }
  if (volumes.length <= 3) {
    return volumes.map((volume) => volume.toString()).join(", ");
  }
  return "${volumes.length} 个分卷";
}
