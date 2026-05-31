import 'dart:async';

import 'package:bili_novel_packer/web/auto_update_config.dart';
import 'package:bili_novel_packer/web/auto_update_service.dart';

class AutoUpdateScheduler {
  final AutoUpdateConfigStore configStore;
  final AutoUpdateService service;
  final Duration interval;

  Timer? _timer;
  bool _checking = false;

  AutoUpdateScheduler({
    required this.configStore,
    required this.service,
    this.interval = const Duration(minutes: 1),
  });

  void start() {
    unawaited(runDue());
    _timer = Timer.periodic(interval, (_) => unawaited(runDue()));
  }

  Future<AutoUpdateRunResult?> runDue({DateTime? now}) async {
    if (_checking) {
      return null;
    }
    _checking = true;
    try {
      final checkedAt = now ?? DateTime.now();
      final config = await configStore.load();
      if (!config.enabled || !_isDue(config, checkedAt)) {
        return null;
      }
      return service.runOnce(now: checkedAt, markRun: true);
    } finally {
      _checking = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool _isDue(AutoUpdateConfig config, DateTime now) {
    final scheduledAt = _scheduledAt(config.dailyTime, now);
    if (now.isBefore(scheduledAt)) {
      return false;
    }
    final lastRunAt = config.lastRunAt;
    if (lastRunAt == null) {
      return true;
    }
    return !_sameLocalDate(lastRunAt, now);
  }

  DateTime _scheduledAt(String dailyTime, DateTime now) {
    final normalized = normalizeDailyTime(dailyTime);
    final parts = normalized.split(":");
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  bool _sameLocalDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
