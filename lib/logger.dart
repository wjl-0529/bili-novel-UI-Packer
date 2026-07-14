import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;

String _logFilePath = _defaultLogFilePath();

String get logFilePath => _logFilePath;

File get loggerFile => File(_logFilePath);

Logger logger = _createLogger(loggerFile);

void configureLogger({required String dataDir}) {
  Directory(dataDir).createSync(recursive: true);
  final nextPath = path.join(dataDir, "bili_novel.log");
  logger.close();
  _logFilePath = nextPath;
  logger = _createLogger(File(nextPath));
}

void closeLogger() => logger.close();

String _defaultLogFilePath() {
  final dataDir = Platform.environment["DATA_DIR"];
  return dataDir == null
      ? "bili_novel.log"
      : path.join(dataDir, "bili_novel.log");
}

Logger _createLogger(File file) {
  return Logger(
    printer: PrettyPrinter(
      colors: false,
      methodCount: 1,
      dateTimeFormat: DateTimeFormat.dateAndTime,
      printEmojis: false,
    ),
    output: FileOutput(
      file: file,
      overrideExisting: true,
    ),
    filter: ProductionFilter(),
  );
}
