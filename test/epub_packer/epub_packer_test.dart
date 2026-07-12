import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:bili_novel_packer/epub_packer/epub_packer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('EpubPacker', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bnp_epub_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates a zip archive in a portable temporary directory', () {
      final output = path.join(tempDir.path, 'archive.epub');
      final zip = ZipFileEncoder();
      zip.create(output);
      zip.addArchiveFile(
        ArchiveFile.string(
          'container',
          'application/epub+zip',
        ),
      );
      zip.close();

      expect(File(output).existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(File(output).readAsBytesSync());
      expect(archive.files.map((file) => file.name), contains('container'));
    });

    test('packs a minimal EPUB', () {
      final output = path.join(tempDir.path, 'book.epub');
      final packer = EpubPacker(output)
        ..docTitle = '测试 EPUB'
        ..creator = 'Author'
        ..bookUuid = 'abc123-def456-ghd8909';

      packer.pack();

      expect(File(output).existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(File(output).readAsBytesSync());
      expect(archive.files.first.name, 'mimetype');
      expect(
        archive.files.map((file) => file.name),
        containsAll(['META-INF/container.xml', 'OEBPS/content.opf']),
      );
    });
  });
}
