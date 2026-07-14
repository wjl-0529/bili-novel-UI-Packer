import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_novel_packer/web/job.dart';
import 'package:path/path.dart' as path;

class JobStore {
  final String dataDir;
  late final String outputsDir = path.join(dataDir, "outputs");
  late final File _jobsFile = File(path.join(dataDir, "jobs.json"));
  final List<DownloadJob> _jobs = [];
  final Map<String, DownloadJob> _jobMap = {};
  Future<void> _saveTail = Future<void>.value();
  Timer? _scheduledSave;

  JobStore(this.dataDir);

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);

  Future<void> load() async {
    await Directory(dataDir).create(recursive: true);
    await Directory(outputsDir).create(recursive: true);
    if (!_jobsFile.existsSync()) {
      await save();
      return;
    }
    final raw = await _jobsFile.readAsString();
    if (raw.trim().isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    final loaded = decoded
        .map((json) => DownloadJob.fromJson(json as Map<String, dynamic>))
        .toList();
    _jobs
      ..clear()
      ..addAll(loaded);
    _jobMap
      ..clear()
      ..addEntries(loaded.map((job) => MapEntry(job.id, job)));
  }

  DownloadJob? find(String id) => _jobMap[id];

  Future<void> addAll(List<DownloadJob> jobs) async {
    _jobs.addAll(jobs);
    for (final job in jobs) {
      _jobMap[job.id] = job;
    }
    await save();
  }

  Future<bool> delete(String jobId) async {
    final existed = _jobMap.remove(jobId) != null;
    if (!existed) {
      return false;
    }
    _jobs.removeWhere((job) => job.id == jobId);
    await deleteOutputs(jobId);
    await save();
    return true;
  }

  Future<int> deleteMany(Iterable<String> jobIds) async {
    final ids = jobIds.toSet();
    if (ids.isEmpty) {
      return 0;
    }
    var deleted = 0;
    for (final id in ids) {
      if (_jobMap.remove(id) != null) {
        deleted++;
      }
    }
    if (deleted == 0) {
      return 0;
    }
    _jobs.removeWhere((job) => ids.contains(job.id));
    for (final id in ids) {
      await deleteOutputs(id);
    }
    await save();
    return deleted;
  }

  Future<void> deleteOutputs(String jobId) async {
    final dir = Directory(outputDirFor(jobId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Coalesces frequent, non-critical progress updates into at most two writes
  /// per second. State transitions should continue to call and await [save].
  void scheduleSave({Duration delay = const Duration(milliseconds: 500)}) {
    _scheduledSave ??= Timer(delay, () {
      _scheduledSave = null;
      save().ignore();
    });
  }

  Future<void> save() {
    _scheduledSave?.cancel();
    _scheduledSave = null;
    final encoder = const JsonEncoder.withIndent("  ");
    final snapshot = encoder.convert(
      _jobs.map((job) => job.toJson()).toList(),
    );
    final operation = _saveTail.then((_) => _writeSnapshot(snapshot));
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _writeSnapshot(String snapshot) async {
    await Directory(dataDir).create(recursive: true);
    final temporaryFile = File('${_jobsFile.path}.$pid.tmp');
    await temporaryFile.writeAsString(snapshot, flush: true);
    await temporaryFile.rename(_jobsFile.path);
  }

  String outputDirFor(String jobId) {
    return path.join(outputsDir, jobId);
  }

  Map<String, dynamic> jobToJson(DownloadJob job) => {
    ...job.toJson(includeSecrets: false),
    "outputDir": outputDirFor(job.id),
  };

  List<Map<String, dynamic>> jobsToJson() =>
      _jobs.map((job) => jobToJson(job)).toList();

  File outputFileFor(String jobId, String fileName) {
    return File(path.join(outputDirFor(jobId), path.basename(fileName)));
  }
}
