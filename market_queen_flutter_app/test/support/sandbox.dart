import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/core/paths.dart';

/// Points the app's config directory at a throwaway folder for this file, and
/// clears it up afterwards.
///
/// Every test that builds an `AppState` has to call this, and the reason is a
/// bug rather than tidiness. `Paths.configDir` used to resolve to the real
/// profile unconditionally -- `%APPDATA%/MarketQueen/Market Queen` -- so
/// `flutter test` ran on top of whoever ran it: settings.json, secrets.bin,
/// actors.json and workspace.json were all the live ones. Two files then set a
/// real API key in `setUpAll` and cleared it again in `tearDownAll`, which is
/// exactly how a Google key typed into the Models page was gone by the next
/// launch.
///
/// Call it as the first statement of `main()`, above the file's own `setUpAll`.
/// The order matters and is what makes this reliable: `setUpAll` callbacks run
/// in the order they were declared, so the redirect is in place before anything
/// asks for a path.
///
/// ```dart
/// void main() {
///   useSandboxConfig();
///
///   setUpAll(() async {
///     TestWidgetsFlutterBinding.ensureInitialized();
///     app = await AppState.create();
///   });
/// ```
void useSandboxConfig() {
  Directory? sandbox;

  setUpAll(() {
    sandbox = Directory.systemTemp.createTempSync('mq-test-');
    Paths.overrideDir = sandbox!.path;
  });

  tearDownAll(() {
    Paths.overrideDir = null;
    final dir = sandbox;
    sandbox = null;
    if (dir == null) return;
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A file the app still holds open, which Windows will not let go of.
      // Leaving it is harmless: the OS clears systemTemp.
    }
  });
}

/// Puts a fake key on every account for the duration of the current test.
///
/// For the tests that are about picking a model rather than about not having
/// one. A model on an account with no key is offered locked -- pressing it asks
/// for the key instead of selecting it -- so on a clean profile, where nothing
/// has a key, "tap a model and see the row change" cannot happen at all. The keys
/// go nowhere: nothing in a widget test opens a socket.
void unlockEveryProvider(AppState app) {
  final restore = <String, String>{};
  for (final credential in app.registry.credentials()) {
    restore[credential.id] = app.settings.apiKey(credential.id);
    app.settings.setApiKey(credential.id, 'test-key-not-a-real-one');
  }
  addTearDown(() {
    restore.forEach(app.settings.setApiKey);
  });
}
