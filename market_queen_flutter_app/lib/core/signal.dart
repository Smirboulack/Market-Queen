import 'package:flutter/foundation.dart';

/// A notification with no state behind it -- the direct equivalent of a Qt
/// signal that carries nothing.
///
/// [ChangeNotifier.notifyListeners] is protected, so a bare `ChangeNotifier`
/// cannot be fired by its owner. This exposes it as [emit].
class Signal extends ChangeNotifier {
  void emit() => notifyListeners();
}

/// A signal that carries a payload. Listeners are called in registration
/// order, like connected slots.
class Event<T> {
  final List<void Function(T)> _listeners = [];

  void listen(void Function(T) listener) => _listeners.add(listener);

  void remove(void Function(T) listener) => _listeners.remove(listener);

  void emit(T value) {
    for (final listener in List.of(_listeners)) {
      listener(value);
    }
  }
}
