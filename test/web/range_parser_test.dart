import 'package:bili_novel_packer/web/range_parser.dart';
import 'package:test/test.dart';

void main() {
  group("parseIntegerRange", () {
    test("parses ordered ranges and single values", () {
      expect(parseIntegerRange("1-3,5,7~8"), [1, 2, 3, 5, 7, 8]);
    });

    test("parses comma separated values", () {
      expect(parseIntegerRange("1,2,3"), [1, 2, 3]);
    });

    test("parses mixed ranges and values", () {
      expect(parseIntegerRange("1-5,7"), [1, 2, 3, 4, 5, 7]);
    });

    test("parses full-width comma separated values", () {
      expect(parseIntegerRange("1，2，3"), [1, 2, 3]);
    });

    test("deduplicates values while preserving order", () {
      expect(parseIntegerRange("1,2,2,1,3"), [1, 2, 3]);
    });

    test("rejects ranges above max count", () {
      expect(
        () => parseIntegerRange("1-101", maxCount: 100),
        throwsA(isA<RangeParseException>()),
      );
    });

    test("rejects values above max value", () {
      expect(
        () => parseIntegerRange("1-3", maxValue: 2),
        throwsA(isA<RangeParseException>()),
      );
    });
  });

  group("buildUrlsFromTemplate", () {
    test("replaces id placeholder", () {
      expect(
        buildUrlsFromTemplate("https://example.test/novel/{id}.html", [8, 9]),
        [
          "https://example.test/novel/8.html",
          "https://example.test/novel/9.html",
        ],
      );
    });

    test("requires id placeholder", () {
      expect(
        () => buildUrlsFromTemplate("https://example.test/novel/1.html", [1]),
        throwsA(isA<RangeParseException>()),
      );
    });
  });
}
