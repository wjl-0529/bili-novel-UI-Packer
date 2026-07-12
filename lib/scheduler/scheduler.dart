import 'dart:async';
import 'dart:collection';

typedef SchedulerTask<R> = FutureOr<R> Function(SchedulerController controller);

/// Starts queued tasks at a fixed rate while allowing already-started tasks to
/// run concurrently.
class Scheduler {
  final Queue<_ScheduledTask<dynamic>> _queue = Queue();
  final Set<Future<void>> _inFlight = {};
  final SchedulerController _controller = SchedulerController();
  final Stopwatch _clock = Stopwatch()..start();

  late final Duration _gap;
  bool _pumping = false;
  int _nextStartMicroseconds = 0;
  Completer<void>? _idleCompleter;

  Scheduler(int n, Duration per) {
    if (n > 0 && per.inMicroseconds > 0) {
      _gap = Duration(
        microseconds: (per.inMicroseconds / n).ceil(),
      );
    } else {
      _gap = Duration.zero;
    }
  }

  Scheduler.unlimited() : this(0, Duration.zero);

  Future<R> run<R>(SchedulerTask<R> task) {
    final completer = Completer<R>();
    _queue.add(_ScheduledTask<R>(task, completer));
    _idleCompleter ??= Completer<void>();
    _startPump();
    return completer.future;
  }

  void _startPump() {
    if (_pumping) {
      return;
    }
    _pumping = true;
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    try {
      while (_queue.isNotEmpty) {
        await _controller._waitUntilResumed();
        await _waitForRateLimit();
        // A running task can pause the scheduler while the rate-limit timer is
        // pending, so check again immediately before starting the next task.
        await _controller._waitUntilResumed();
        if (_queue.isEmpty) {
          break;
        }
        final scheduled = _queue.removeFirst();
        _startTask(scheduled);
        _nextStartMicroseconds =
            _clock.elapsedMicroseconds + _gap.inMicroseconds;
      }
    } finally {
      _pumping = false;
      if (_queue.isNotEmpty) {
        _startPump();
      }
      _completeIdleIfNeeded();
    }
  }

  Future<void> _waitForRateLimit() async {
    final remaining = _nextStartMicroseconds - _clock.elapsedMicroseconds;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(microseconds: remaining));
    }
  }

  void _startTask(_ScheduledTask<dynamic> scheduled) {
    late final Future<void> completion;
    completion =
        Future<dynamic>.sync(
          () => scheduled.task(_controller),
        ).then<void>(
          scheduled.completer.complete,
          onError: (Object error, StackTrace stackTrace) {
            scheduled.completer.completeError(error, stackTrace);
          },
        );
    _inFlight.add(completion);
    unawaited(
      completion.whenComplete(() {
        _inFlight.remove(completion);
        _completeIdleIfNeeded();
      }),
    );
  }

  bool get _isIdle => _queue.isEmpty && !_pumping && _inFlight.isEmpty;

  void _completeIdleIfNeeded() {
    if (!_isIdle) {
      return;
    }
    final completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> wait() async {
    while (!_isIdle) {
      _idleCompleter ??= Completer<void>();
      await _idleCompleter!.future;
    }
  }
}

class _ScheduledTask<R> {
  final SchedulerTask<R> task;
  final Completer<R> completer;

  _ScheduledTask(this.task, this.completer);
}

class SchedulerController {
  bool _paused = false;
  Completer<void>? _resumeCompleter;

  Future<void> _waitUntilResumed() {
    if (!_paused) {
      return Future<void>.value();
    }
    return _resumeCompleter!.future;
  }

  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;
    _resumeCompleter = Completer<void>();
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
