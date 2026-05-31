import 'dart:async';

import 'package:bili_novel_packer/web/cleanup_config.dart';
import 'package:bili_novel_packer/web/job_queue.dart';

class CleanupScheduler {
  final CleanupConfigStore configStore;
  final JobQueue queue;
  final Duration interval;

  Timer? _timer;
  bool _running = false;

  CleanupScheduler({
    required this.configStore,
    required this.queue,
    this.interval = const Duration(hours: 1),
  });

  void start() {
    unawaited(runOnce());
    _timer = Timer.periodic(interval, (_) => unawaited(runOnce()));
  }

  Future<int> runOnce({DateTime? now}) async {
    if (_running) {
      return 0;
    }
    _running = true;
    try {
      final config = await configStore.load();
      if (!config.enabled) {
        return 0;
      }
      final cutoff = (now ?? DateTime.now()).subtract(
        Duration(days: config.retentionDays),
      );
      return queue.cleanupCompletedOlderThan(cutoff);
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
