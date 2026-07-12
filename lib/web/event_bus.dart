import 'dart:async';
import 'dart:convert';

class EventBus {
  final List<StreamController<String>> _controllers = [];

  Stream<String> subscribe({Iterable<String> initialEvents = const []}) {
    late StreamController<String> controller;
    controller = StreamController<String>(
      sync: true,
      onCancel: () => _controllers.remove(controller),
    );
    _controllers.add(controller);
    for (final event in initialEvents) {
      controller.add(event);
    }
    return controller.stream;
  }

  void publish(String type, Object? data) {
    final event = formatEvent(type, data);
    // Iterate in reverse to allow safe removal during iteration
    for (var i = _controllers.length - 1; i >= 0; i--) {
      // The subscription cancellation callback owns this controller's cleanup.
      // ignore: close_sinks
      final controller = _controllers[i];
      if (controller.isClosed) {
        _controllers.removeAt(i);
      } else {
        controller.add(event);
      }
    }
  }

  String formatEvent(String type, Object? data) {
    return jsonEncode({
      "type": type,
      "data": data,
      "ts": DateTime.now().toIso8601String(),
    });
  }

  Future<void> close() async {
    final controllers = List<StreamController<String>>.from(_controllers);
    _controllers.clear();
    await Future.wait(controllers.map((controller) => controller.close()));
  }
}
