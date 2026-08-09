import 'dart:io';

import 'package:flutter/services.dart';

/// Windows keeps the title bar light unless the window opts in, so it has to
/// follow the in-app theme rather than the system one.
///
/// Handled by the runner (windows/runner/flutter_window.cpp); a no-op
/// everywhere else, where the platform draws the caption from the system theme
/// and there is nothing to override.
class TitleBar {
  TitleBar._();

  static const _channel = MethodChannel('marketqueen/titlebar');

  static Future<void> setDark(bool dark) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('setDark', dark);
    } on PlatformException {
      // An older runner without the channel: the bar keeps the system look,
      // which is cosmetic and never worth failing a theme switch over.
    } on MissingPluginException {
      // Same.
    }
  }
}
