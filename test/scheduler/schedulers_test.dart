import 'dart:async';

import 'package:bili_novel_packer/scheduler/scheduler.dart';
import 'package:test/test.dart';

void main() {
  test('each submission has an independent result', () async {
    final scheduler = Scheduler.unlimited();
    var calls = 0;

    Future<int> task(SchedulerController _) async => ++calls;

    final results = await Future.wait([
      scheduler.run(task),
      scheduler.run(task),
    ]);

    expect(results, [1, 2]);
    await expectLater(
      scheduler.run<int>((_) => throw StateError('boom')),
      throwsStateError,
    );
    await scheduler.wait();
  });

  test(
    'rate limit spaces starts without waiting for task completion',
    () async {
      final scheduler = Scheduler(20, const Duration(seconds: 1));
      final firstGate = Completer<void>();
      final secondStarted = Completer<void>();
      final stopwatch = Stopwatch()..start();

      final first = scheduler.run((_) async {
        await firstGate.future;
        return 1;
      });
      final second = scheduler.run((_) {
        secondStarted.complete();
        return 2;
      });

      await secondStarted.future.timeout(const Duration(seconds: 1));
      expect(firstGate.isCompleted, isFalse);
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 40)),
      );

      firstGate.complete();
      expect(await first, 1);
      expect(await second, 2);
      await scheduler.wait();
    },
  );

  test('pause blocks new starts and wait includes in-flight work', () async {
    final scheduler = Scheduler.unlimited();
    final firstStarted = Completer<void>();
    final firstGate = Completer<void>();
    var secondStarted = false;

    final first = scheduler.run((controller) async {
      controller.pause();
      firstStarted.complete();
      await firstGate.future;
      controller.resume();
    });
    final second = scheduler.run((_) {
      secondStarted = true;
    });

    await firstStarted.future;
    var waitCompleted = false;
    final waiting = scheduler.wait().then((_) => waitCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(secondStarted, isFalse);
    expect(waitCompleted, isFalse);

    firstGate.complete();
    await Future.wait([first, second, waiting]);
    expect(secondStarted, isTrue);
    expect(waitCompleted, isTrue);
  });

  test('pause raised during a rate delay blocks the next start', () async {
    final scheduler = Scheduler(10, const Duration(seconds: 1));
    final paused = Completer<void>();
    late SchedulerController controller;
    var secondStarted = false;

    final first = scheduler.run((value) async {
      controller = value;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.pause();
      paused.complete();
    });
    final second = scheduler.run((_) {
      secondStarted = true;
    });

    await paused.future;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(secondStarted, isFalse);

    controller.resume();
    await Future.wait([first, second]);
    expect(secondStarted, isTrue);
  });
}
