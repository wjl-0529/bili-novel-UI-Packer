import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

const _assetPrefix = 'assets/web/';

Future<Directory> installBundledWebAssets(
  Directory applicationSupportDirectory,
) async {
  final destination = Directory(
    path.join(applicationSupportDirectory.path, 'web'),
  );
  if (await destination.exists()) {
    await destination.delete(recursive: true);
  }
  await destination.create(recursive: true);

  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest
      .listAssets()
      .where((asset) => asset.startsWith(_assetPrefix))
      .toList(growable: false);
  if (assets.isEmpty) {
    throw StateError('应用包中缺少 React Web 资源');
  }
  for (final asset in assets) {
    final relativePath = asset.substring(_assetPrefix.length);
    if (relativePath.isEmpty) {
      continue;
    }
    final data = await rootBundle.load(asset);
    final file = File(path.join(destination.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return destination;
}
