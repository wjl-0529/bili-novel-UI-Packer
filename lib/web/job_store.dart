import 'dart:convert';
import 'dart:io';

import 'package:bili_novel_packer/web/job.dart';
import 'package:path/path.dart' as path;

class JobStore {
  final String dataDir;
  late final String outputsDir = path.join(dataDir, "outputs");
  late final File _jobsFile = File(path.join(dataDir, "jobs.json"));
  final List<DownloadJob> _jobs = [];

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
    _jobs
      ..clear()
      ..addAll(decoded.map((json) => DownloadJob.fromJson(json)));
  }

  DownloadJob? find(String id) {
    for (final job in _jobs) {
      if (job.id == id) {
        return job;
      }
    }
    return null;
  }

  Future<void> addAll(List<DownloadJob> jobs) async {
    _jobs.addAll(jobs);
    await save();
  }

  Future<bool> delete(String jobId) async {
    final before = _jobs.length;
    _jobs.removeWhere((job) => job.id == jobId);
    if (_jobs.length == before) {
      return false;
    }
    await deleteOutputs(jobId);
    await save();
    return true;
  }

  Future<int> deleteMany(Iterable<String> jobIds) async {
    final ids = jobIds.toSet();
    if (ids.isEmpty) {
      return 0;
    }
    final before = _jobs.length;
    _jobs.removeWhere((job) => ids.contains(job.id));
    final deleted = before - _jobs.length;
    if (deleted == 0) {
      return 0;
    }
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

  Future<void> save() async {
    await Directory(dataDir).create(recursive: true);
    final encoder = const JsonEncoder.withIndent("  ");
    await _jobsFile.writeAsString(
      encoder.convert(_jobs.map((job) => job.toJson()).toList()),
    );
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
