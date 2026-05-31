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
    for (final controller
        in List<StreamController<String>>.from(_controllers)) {
      if (!controller.isClosed) {
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
}
