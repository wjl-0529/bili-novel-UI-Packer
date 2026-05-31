class RangeParseException implements Exception {
  final String message;

  RangeParseException(this.message);

  @override
  String toString() => message;
}

List<int> parseIntegerRange(
  String input, {
  int? maxValue,
  int? maxCount,
}) {
  final normalized = input.trim();
  if (normalized.isEmpty) {
    throw RangeParseException("请输入范围");
  }

  final result = <int>[];
  final seen = <int>{};
  final parts = normalized
      .replaceAll("，", ",")
      .replaceAll(" ", ",")
      .split(",")
      .where((part) => part.trim().isNotEmpty);

  for (final rawPart in parts) {
    final part = rawPart.trim().replaceAll("~", "-");
    final range = part.split("-");
    if (range.length == 1) {
      _addValue(result, seen, _parsePositiveInt(range[0]), maxValue);
    } else if (range.length == 2) {
      var from = _parsePositiveInt(range[0]);
      var to = _parsePositiveInt(range[1]);
      if (from > to) {
        final tmp = from;
        from = to;
        to = tmp;
      }
      for (var value = from; value <= to; value++) {
        _addValue(result, seen, value, maxValue);
        if (maxCount != null && result.length > maxCount) {
          throw RangeParseException("范围数量不能超过 $maxCount 个");
        }
      }
    } else {
      throw RangeParseException("范围片段格式错误：$part");
    }
    if (maxCount != null && result.length > maxCount) {
      throw RangeParseException("范围数量不能超过 $maxCount 个");
    }
  }

  if (result.isEmpty) {
    throw RangeParseException("范围不能为空");
  }
  return result;
}

List<String> buildUrlsFromTemplate(String template, List<int> ids) {
  if (!template.contains("{id}")) {
    throw RangeParseException("URL 模板必须包含 {id}");
  }
  return ids.map((id) => template.replaceAll("{id}", id.toString())).toList();
}

int _parsePositiveInt(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) {
    throw RangeParseException("请输入正整数：$value");
  }
  return parsed;
}

void _addValue(
  List<int> result,
  Set<int> seen,
  int value,
  int? maxValue,
) {
  if (maxValue != null && value > maxValue) {
    throw RangeParseException("范围值 $value 超过最大值 $maxValue");
  }
  if (seen.add(value)) {
    result.add(value);
  }
}
