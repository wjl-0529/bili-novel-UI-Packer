import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_novel_packer/assets/assets.dart';
import 'package:bili_novel_packer/epub_packer/epub_navigator.dart';
import 'package:bili_novel_packer/epub_packer/epub_packer.dart';
import 'package:bili_novel_packer/light_novel/base/light_novel_cover_detector.dart';
import 'package:bili_novel_packer/light_novel/base/light_novel_model.dart';
import 'package:bili_novel_packer/light_novel/base/light_novel_source.dart';
import 'package:bili_novel_packer/light_novel/bili_novel/bili_novel_source.dart';
import 'package:bili_novel_packer/light_novel/wenku_novel/wenku_novel_source.dart';
import 'package:bili_novel_packer/log.dart';
import 'package:bili_novel_packer/pack_argument.dart';
import 'package:bili_novel_packer/pack_progress.dart';
import 'package:bili_novel_packer/util/html_util.dart';
import 'package:bili_novel_packer/util/sequence.dart';
import 'package:bili_novel_packer/util/volume_util.dart';
import 'package:console/console.dart';
import 'package:html/dom.dart';
import 'package:path/path.dart' as path;

class NovelPacker {
  static final List<LightNovelSource> sources = [
    BiliNovelSource(),
    WenkuNovelSource(),
  ];

  String url;
  LightNovelSource lightNovelSource;

  final Sequence _imageSequence = Sequence();
  final Sequence _chapterSequence = Sequence();

  late Novel novel;
  late Catalog catalog;

  NovelPacker._(this.lightNovelSource, this.url);

  factory NovelPacker.fromUrl(String url) {
    for (var source in sources) {
      if (source.supportUrl(url)) {
        return NovelPacker._(source, url);
      }
    }
    throw "不支持的 URL: $url";
  }

  Future<Novel> init({
    Function(Novel novel)? novelCallback,
    Function(Catalog catalog)? catalogCallback,
  }) async {
    novel = await getNovel();
    novelCallback?.call(novel);
    catalog = await getCatalog();
    catalogCallback?.call(catalog);
    return novel;
  }

  Future<Novel> getNovel() async {
    return lightNovelSource.getNovel(url).then((novel) => this.novel = novel);
  }

  Future<Catalog> getCatalog() async {
    return lightNovelSource
        .getNovelCatalog(novel)
        .then((catalog) => this.catalog = catalog);
  }

  Future<List<String>> pack(PackArgument arg) async {
    final outputFiles = <String>[];
    final totalWorkUnits = _totalWorkUnits(arg.packVolumes);
    var completedWorkUnits = 0;
    int markWorkUnit() => ++completedWorkUnits;
    int currentWorkUnits() => completedWorkUnits;

    if (!arg.combineVolume) {
      for (final volume in arg.packVolumes) {
        logger.i("开始打包 ${volume.catalog.novel.title} ${volume.volumeName}");
        _imageSequence.reset();
        _chapterSequence.reset();
        outputFiles.add(await _packVolume(
          volume,
          arg,
          totalWorkUnits: totalWorkUnits,
          currentWorkUnits: currentWorkUnits,
          markWorkUnit: markWorkUnit,
        ));
        logger.i("打包完成 ${volume.catalog.novel.title} ${volume.volumeName}");
      }
    } else {
      final title = _sanitizeFileName(novel.title);
      final filePath = _resolveOutputPath(
        arg,
        "$title.epub",
        folderName: title,
      );
      logger.i("EPUB 文件: $filePath");
      outputFiles.add(await _combineVolume(filePath, arg));
    }
    return outputFiles;
  }

  int _totalWorkUnits(List<Volume> volumes) {
    final totalChapters = volumes.fold<int>(
      0,
      (sum, volume) => sum + volume.chapters.length,
    );
    return totalChapters == 0 ? 1 : totalChapters * 2;
  }

  Future<String> _combineVolume(
    String filePath,
    PackArgument arg,
  ) async {
    final totalChapters = arg.packVolumes.fold<int>(
      0,
      (sum, volume) => sum + volume.chapters.length,
    );
    final totalWorkUnits = totalChapters == 0 ? 1 : totalChapters * 2;
    var completedWorkUnits = 0;
    int markWorkUnit() => ++completedWorkUnits;
    arg.onProgress?.call(PackProgressEvent(
      type: "pack-start",
      message: "开始打包《${novel.title}》",
      novel: novel,
      completed: completedWorkUnits,
      total: totalWorkUnits,
    ));

    final packer = EpubPacker(filePath);
    packer.docTitle = novel.title;
    packer.creator = novel.author;
    packer.source = novel.url;
    packer.publisher = novel.publisher;
    packer.subjects = novel.tags ?? [];
    packer.description = novel.description;

    final coverData = novel.coverUrl == null
        ? Uint8List(0)
        : await _getSingleImage(novel.coverUrl!);
    final coverName =
        "images/${_imageSequence.next.toString().padLeft(6, '0')}.jpg";
    packer.addImage(name: "OEBPS/$coverName", data: coverData);
    packer.cover = coverName;

    if (arg.addChapterTitle) {
      packer.addStylesheet(styleCss());
    }

    for (final volume in arg.packVolumes) {
      logger.i("开始处理分卷 ${volume.volumeName}");
      Console.write("正在处理: ${volume.volumeName}\n");
      arg.onProgress?.call(PackProgressEvent(
        type: "volume-start",
        message: "开始处理分卷 ${volume.volumeName}",
        novel: novel,
        volume: volume,
        completed: completedWorkUnits,
        total: totalWorkUnits,
      ));
      final volumeNavPoint = NavPoint(volume.volumeName);
      final futures = volume.chapters.map(
        (chapter) async {
          final document = await _resolveChapter(
            chapter,
            packer,
            arg.addChapterTitle,
            onProgress: arg.onProgress,
          );
          arg.onProgress?.call(PackProgressEvent(
            type: "chapter-downloaded",
            message: "章节下载完成 ${chapter.chapterName}",
            novel: novel,
            volume: volume,
            chapter: chapter,
            completed: markWorkUnit(),
            total: totalWorkUnits,
          ));
          return document;
        },
      ).toList();

      final chapterDocuments = await Future.wait(futures);
      for (var i = 0; i < chapterDocuments.length; i++) {
        final chapter = volume.chapters[i];
        final document = chapterDocuments[i];
        _addTitle(document, chapter.chapterName);
        var html = _closeTag(document);
        html = _appendXmlDeclare(html);
        final name =
            "chapter${_chapterSequence.next.toString().padLeft(6, "0")}.xhtml";
        packer.addChapter(
          addNavPoint: false,
          name: "OEBPS/$name",
          title: chapter.chapterName,
          chapterContent: html,
        );
        final chapterNavPoint = NavPoint(chapter.chapterName, src: name);
        volumeNavPoint.addChild(chapterNavPoint);
        if (i == 0) {
          volumeNavPoint.src = name;
        }
        arg.onProgress?.call(PackProgressEvent(
          type: "chapter-packed",
          message: "章节已写入 ${chapter.chapterName}",
          novel: novel,
          volume: volume,
          chapter: chapter,
          completed: markWorkUnit(),
          total: totalWorkUnits,
        ));
      }
      packer.addNavPoint(volumeNavPoint);
      logger.i("分卷处理完成 ${volume.volumeName}");
    }
    packer.pack();
    Console.write("打包完成: ${packer.absolutePath}\n");
    arg.onProgress?.call(PackProgressEvent(
      type: "pack-complete",
      message: "打包完成《${novel.title}》",
      filePath: packer.absolutePath,
      novel: novel,
      completed: totalWorkUnits,
      total: totalWorkUnits,
    ));
    return packer.absolutePath;
  }

  Future<Document> _resolveChapter(
    Chapter chapter,
    EpubPacker packer,
    bool addChapterTitle, {
    LightNovelCoverDetector? detector,
    PackProgressCallback? onProgress,
  }) async {
    onProgress?.call(PackProgressEvent(
      type: "chapter-start",
      message: "开始下载章节 ${chapter.chapterName}",
      novel: novel,
      volume: chapter.volume,
      chapter: chapter,
    ));
    final doc = await lightNovelSource.getNovelChapter(chapter);
    await _resolveImages(doc, packer, detector);

    if (addChapterTitle) {
      doc.head!.append(Element.html(
        '<link rel="stylesheet" type="text/css" href="styles/style.css">',
      ));
      final firstChild = doc.body!.firstChild;
      final chapterTitle = Element.html(
        '<div class="chapter-title">${chapter.chapterName}</div>',
      );
      doc.body!.insertBefore(chapterTitle, firstChild);
    }
    logger.i("完成 ${chapter.volume.volumeName} ${chapter.chapterName}");
    return doc;
  }

  Future<Uint8List> _getSingleImage(String src) async {
    try {
      return await lightNovelSource.getImage(src);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<String> _packVolume(
    Volume volume,
    PackArgument arg, {
    required int totalWorkUnits,
    required int Function() currentWorkUnits,
    required int Function() markWorkUnit,
  }) async {
    final addChapterTitle = arg.addChapterTitle;
    Console.write("开始打包 ${volume.volumeName}...\n");
    arg.onProgress?.call(PackProgressEvent(
      type: "volume-start",
      message: "开始打包分卷 ${volume.volumeName}",
      novel: novel,
      volume: volume,
      completed: currentWorkUnits(),
      total: totalWorkUnits,
    ));

    final packer = EpubPacker(_getEpubName(volume, arg));
    packer.docTitle = "${volume.catalog.novel.title} ${volume.volumeName}";
    if (volume.volumeName.startsWith(volume.catalog.novel.title)) {
      packer.docTitle = volume.volumeName;
    }
    packer.creator = volume.catalog.novel.author;
    packer.source = novel.url;
    packer.publisher = novel.publisher;
    packer.subjects = novel.tags ?? [];
    packer.description = novel.description;
    packer.calibreSeriesIndex = VolumeUtil.getSeriesIndex(volume.volumeName);
    if (packer.calibreSeriesIndex != null) {
      packer.calibreSeries = volume.catalog.novel.title;
    }

    final detector = LightNovelCoverDetector();

    if (addChapterTitle) {
      packer.addStylesheet(styleCss());
    }

    final futures = volume.chapters.map(
      (chapter) async {
        final document = await _resolveChapter(
          chapter,
          packer,
          addChapterTitle,
          detector: detector,
          onProgress: arg.onProgress,
        );
        arg.onProgress?.call(PackProgressEvent(
          type: "chapter-downloaded",
          message: "章节下载完成 ${chapter.chapterName}",
          novel: novel,
          volume: volume,
          chapter: chapter,
          completed: markWorkUnit(),
          total: totalWorkUnits,
        ));
        return document;
      },
    ).toList();

    final chapterDocuments = await Future.wait(futures);

    for (var i = 0; i < chapterDocuments.length; i++) {
      final chapter = volume.chapters[i];
      final document = chapterDocuments[i];
      _addTitle(document, chapter.chapterName);
      var html = _closeTag(document);
      html = _appendXmlDeclare(html);
      packer.addChapter(
        name:
            "OEBPS/chapter${_chapterSequence.next.toString().padLeft(6, "0")}.xhtml",
        title: chapter.chapterName,
        chapterContent: html,
      );
      arg.onProgress?.call(PackProgressEvent(
        type: "chapter-packed",
        message: "章节已写入 ${chapter.chapterName}",
        novel: novel,
        volume: volume,
        chapter: chapter,
        completed: markWorkUnit(),
        total: totalWorkUnits,
      ));
    }

    await _resolveCover(volume, packer, detector);
    packer.pack();
    logger.i("EPUB 文件: ${packer.absolutePath}");
    Console.write("打包完成: ${packer.absolutePath}\n\n");
    arg.onProgress?.call(PackProgressEvent(
      type: "volume-complete",
      message: "分卷打包完成 ${volume.volumeName}",
      filePath: packer.absolutePath,
      novel: novel,
      volume: volume,
      completed: currentWorkUnits(),
      total: totalWorkUnits,
    ));
    return packer.absolutePath;
  }

  Future<void> _resolveImages(
    Document doc,
    EpubPacker packer,
    LightNovelCoverDetector? detector,
  ) async {
    final imgList = doc.querySelectorAll("img");
    final futures = <Future<Pair<Element, Uint8List>?>>[];
    for (final img in imgList) {
      futures.add(_resolveSingleImage(img, packer, detector));
    }
    final pairList = await Future.wait(futures);
    for (final pair in pairList) {
      if (pair == null) continue;
      final img = pair.v1;
      final imageData = pair.v2;
      final name = "${_imageSequence.next.toString().padLeft(6, '0')}.jpg";
      final relativeSrc = "images/$name";
      packer.addImage(name: "OEBPS/$relativeSrc", data: imageData);
      final src = img.attributes["src"];
      img.attributes["src"] = relativeSrc;
      try {
        detector?.add("OEBPS/$relativeSrc", imageData);
      } on UnsupportedImageException catch (e) {
        print("$src ${e.message}");
      }
    }

    HTMLUtil.wrapDuoKanImage(doc.body!);
  }

  Future<Pair<Element, Uint8List>?> _resolveSingleImage(
    Element img,
    EpubPacker packer,
    LightNovelCoverDetector? detector,
  ) async {
    final src = img.attributes["src"];
    if (src == null || src.isEmpty) {
      return null;
    }
    final imageData = await _getSingleImage(src);
    if (imageData.isEmpty) {
      print("$src 图片下载失败");
      return null;
    }
    return Pair(img, imageData);
  }

  Future<void> _resolveCover(
    Volume volume,
    EpubPacker packer,
    LightNovelCoverDetector coverDetector,
  ) async {
    if (volume.cover != null) {
      final coverData = await _getSingleImage(volume.cover!).catchError((e) {
        throw "封面下载失败 ${volume.cover}\n$e";
      });
      final coverName =
          "images/${_imageSequence.next.toString().padLeft(6, '0')}.jpg";
      packer.addImage(name: "OEBPS/$coverName", data: coverData);
      packer.cover = coverName;
    } else {
      final cover = coverDetector.detectCover();
      if (cover != null) {
        packer.cover = cover.replaceFirst("OEBPS/", "");
      }
    }
  }

  String _getEpubName(Volume volume, PackArgument arg) {
    final title = _sanitizeFileName(volume.catalog.novel.title);
    final volumeName = _sanitizeFileName(volume.volumeName);
    if (volumeName == "") {
      return _resolveOutputPath(arg, "$title.epub", folderName: title);
    }
    if (volumeName.startsWith(title)) {
      return _resolveOutputPath(arg, "$volumeName.epub", folderName: title);
    }
    return _resolveOutputPath(arg, "$title $volumeName.epub",
        folderName: title);
  }

  String _resolveOutputPath(
    PackArgument arg,
    String fileName, {
    required String folderName,
  }) {
    final outputDirectory = arg.outputDirectory;
    if (outputDirectory == null || outputDirectory.isEmpty) {
      return "$folderName${Platform.pathSeparator}$fileName";
    }
    return path.join(outputDirectory, fileName);
  }

  String _sanitizeFileName(String name) {
    final keywords = {
      ":",
      "*",
      "?",
      "\"",
      "\\",
      "/",
      "<",
      ">",
      "|",
      "\\0",
      "\u3000"
    };
    for (final keyword in keywords) {
      name = name.replaceAll(keyword, " ");
    }
    if (name.startsWith(".")) {
      name = name.substring(1);
    }
    if (name.endsWith(".")) {
      name = name.substring(0, name.length - 1);
    }
    name = name.replaceAllMapped(RegExp("\\s+"), (_) => " ");
    return name.trim();
  }

  void _addTitle(Document document, String title) {
    final element = document.createElement("title");
    element.text = title;
    document.head?.append(element);
  }

  String _closeTag(Document document) {
    var html = document.outerHtml;
    final regExp = RegExp("(<(?:img|link).*?)>");
    final matches = regExp.allMatches(html);
    for (final match in matches) {
      final img = match.group(0)!;
      if (!img.endsWith("/>")) {
        final newImg = "${match.group(1)!}/>";
        html = html.replaceAll(img, newImg);
      }
    }
    return html;
  }

  String _appendXmlDeclare(String html) {
    const xmlDeclare = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
""";
    return xmlDeclare + html;
  }
}

class Pair<V1, V2> {
  V1 v1;
  V2 v2;

  Pair(this.v1, this.v2);
}
