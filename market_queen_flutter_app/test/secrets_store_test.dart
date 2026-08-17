import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/core/paths.dart';
import 'package:market_queen/core/secret_box.dart';
import 'package:market_queen/core/settings_store.dart';

import 'support/sandbox.dart';

/// A key you typed stays typed.
///
/// This is the complaint these tests exist for: a Google key entered on the
/// Models page was gone by the next launch. There were two ways that happened
/// and both are pinned here.
///
/// The first was the test suite itself. Every store in the app hangs off
/// `Paths.configDir`, which used to resolve to the real profile with no way to
/// point it elsewhere, and two files set a real credential in `setUpAll` and
/// cleared it in `tearDownAll`. Running `flutter test` deleted the user's
/// `gemini` and `anthropic` keys -- the two the suite happened to name, which is
/// exactly the two the report was about. That is fixed by a seam rather than by
/// an assertion, and the assertion that it works is every other file in this
/// directory calling `useSandboxConfig`.
///
/// The second is below: a secrets file that will not open must not be written
/// over. An unreadable file leaves the store empty, which is indistinguishable
/// from a fresh install, so the next key typed sealed a one-entry map on top of
/// everything that was there.
void main() {
  useSandboxConfig();

  late SettingsStore store;

  File secretsFile() => File('${Paths.configDir}/secrets.bin');

  /// The sandbox is one directory for the whole file, so each test starts by
  /// clearing what the last one sealed. Without it a test asserting a key is
  /// *absent* would be reading the previous test's file.
  setUp(() {
    final dir = Directory(Paths.configDir);
    if (dir.existsSync()) {
      for (final entry in dir.listSync()) {
        if (entry.path.contains('secrets.bin')) entry.deleteSync();
      }
    }
    store = SettingsStore();
  });

  tearDown(() => store.dispose());

  test('a key survives being reloaded from disk', () {
    store.setApiKey('__store_a__', 'sk-first');
    store.setApiKey('__store_b__', 'sk-second');

    // What a restart does: a second store over the same directory.
    final reopened = SettingsStore();
    addTearDown(reopened.dispose);

    expect(reopened.apiKey('__store_a__'), 'sk-first');
    expect(reopened.apiKey('__store_b__'), 'sk-second');
  });

  test('changing one key leaves the others alone', () {
    store
      ..setApiKey('__store_a__', 'sk-openai')
      ..setApiKey('__store_c__', 'sk-anthropic')
      ..setApiKey('__store_b__', 'sk-gemini-old');

    store.setApiKey('__store_b__', 'sk-gemini-new');

    final reopened = SettingsStore();
    addTearDown(reopened.dispose);

    expect(reopened.apiKey('__store_b__'), 'sk-gemini-new');
    expect(reopened.apiKey('__store_a__'), 'sk-openai');
    expect(reopened.apiKey('__store_c__'), 'sk-anthropic');
  });

  test('clearing a key removes only that one', () {
    store
      ..setApiKey('__store_a__', 'sk-openai')
      ..setApiKey('__store_b__', 'sk-gemini');

    store.setApiKey('__store_b__', '');

    final reopened = SettingsStore();
    addTearDown(reopened.dispose);

    expect(reopened.hasApiKey('__store_b__'), isFalse);
    expect(reopened.apiKey('__store_a__'), 'sk-openai');
  });

  /// The launch-environment case, which is what made this happen on one machine
  /// and not another. `USER` is absent from an Explorer launch and set by every
  /// MSYS shell, and both used to go into the key derivation -- so a file sealed
  /// from `flutter run` in Git Bash could not be opened by the built exe.
  test('a file sealed under a sibling device key still opens', () {
    final keys = SecretBox.candidateKeys();
    // Only meaningful where the environment actually yields two variants; on a
    // machine where it does not, there is nothing to be robust about.
    if (keys.length < 2) {
      expect(keys, isNotEmpty);
      return;
    }

    secretsFile().writeAsBytesSync(
      SecretBox.seal(
        Uint8List.fromList('{"__store_a__":"sk-from-the-other-shell"}'.codeUnits),
        keys.last,
      ),
    );

    final reopened = SettingsStore();
    addTearDown(reopened.dispose);

    expect(reopened.apiKey('__store_a__'), 'sk-from-the-other-shell');
    expect(reopened.secretsUnreadable, isFalse);
  });

  test('a secrets file that will not open is moved aside, not overwritten', () {
    // Sealed under a key this machine cannot derive.
    final foreign = Uint8List.fromList(List<int>.filled(32, 7));
    secretsFile().writeAsBytesSync(
      SecretBox.seal(
        Uint8List.fromList('{"__store_a__":"sk-not-ours"}'.codeUnits),
        foreign,
      ),
    );

    final reopened = SettingsStore();
    addTearDown(reopened.dispose);
    expect(reopened.secretsUnreadable, isTrue);
    expect(reopened.hasApiKey('__store_a__'), isFalse);

    reopened.setApiKey('__store_b__', 'sk-new');

    final kept = Directory(Paths.configDir)
        .listSync()
        .where((entry) => entry.path.contains('secrets.bin.unreadable-'));
    expect(kept, isNotEmpty, reason: 'the old blob should still be on disk');

    // And the new key is stored the ordinary way.
    final third = SettingsStore();
    addTearDown(third.dispose);
    expect(third.apiKey('__store_b__'), 'sk-new');
  });
}
