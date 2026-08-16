import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/providers/registry.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/key_field.dart';

/// The key field, which for a while could not do the one thing its buttons
/// promised.
///
/// Show and Hide were unusable: pressing Show moved the focus off the text
/// field, the field read losing focus as "finished editing", saved, and
/// swapped itself for a settled line -- so the reveal was undone in the frame
/// it was asked for and the button looked inert.
///
/// It is one ordinary password box now: the value is always in it, the eye at
/// its right edge only changes what is drawn, and saving happens on Enter or
/// on leaving. These keep those three apart.
void main() {
  late AppState app;

  /// An account that does not exist.
  ///
  /// The settings store writes to the real config directory -- there is no
  /// seam to point it somewhere else -- so a test that used a genuine
  /// credential would overwrite whatever key the person running it actually
  /// has for that provider, and would race the other test files reading the
  /// same file. A made-up id touches nobody's account and is cleaned up below.
  const credential = CredentialEntry(
    id: '__key_field_test__',
    label: 'Test account',
    envVar: 'MQ_TEST_KEY',
    signupUrl: 'https://example.invalid',
    note: 'Not a real account.',
  );

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // The stored language too, not just the translator. AppState reapplies
    // `settings.uiLanguage` on every preference write, so a test that changes
    // any setting would otherwise snap the interface back to whatever this
    // machine has saved -- and every label asserted below is the English one.
    app.settings.uiLanguage = 'en';
    await app.translator.applyLanguage('en');
  });

  setUp(() => app.settings.setApiKey(credential.id, ''));
  tearDownAll(() => app.settings.setApiKey(credential.id, ''));

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1000, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = MqTheme(dark: false);
    await tester.pumpWidget(
      AppTheme(
        theme: theme,
        child: MaterialApp(
          theme: theme.material,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              // A fresh key per pump. Without it Flutter reuses the previous
              // test's State -- same widget type, same position in the tree --
              // and the field starts the next test still revealed, or still
              // open, from the one before.
              child: KeyField(
                key: UniqueKey(),
                app: app,
                credential: credential,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// What the text field is actually rendering: dots, or the key.
  bool obscured(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).obscureText;

  /// The eye at the end of the box, in each of its two states.
  Finder eye() => find.byTooltip('Show');
  Finder eyeOff() => find.byTooltip('Hide');

  testWidgets('the eye reveals without saving or closing the field', (
    tester,
  ) async {
    app.settings.setApiKey(credential.id, 'sk-secret-1234');
    await pump(tester);

    expect(obscured(tester), isTrue, reason: 'starts masked');

    await tester.tap(eye());
    await tester.pumpAndSettle();

    // The bug, in one line: the field used to have been swapped out by now.
    expect(find.byType(TextField), findsOneWidget, reason: 'field still there');
    expect(obscured(tester), isFalse, reason: 'now readable');

    await tester.tap(eyeOff());
    await tester.pumpAndSettle();
    expect(obscured(tester), isTrue);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('there is nothing to reveal on an empty field', (tester) async {
    await pump(tester);
    expect(eye(), findsNothing);
    expect(eyeOff(), findsNothing);
  });

  testWidgets('Enter writes the key', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'sk-secret-1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(app.settings.apiKey(credential.id), 'sk-secret-1234');
  });

  testWidgets('clicking away keeps what was pasted', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'sk-secret-1234');
    // Focus goes somewhere that is not this control.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(app.settings.apiKey(credential.id), 'sk-secret-1234');
  });

  // Not covered here: the field also re-hides the key when the focus leaves
  // it. Driving that needs a reveal *and* a blur in one test, and the eye
  // could not be found reliably that far into this file -- the shared
  // AppState writes to the real settings store, and the later tests in a run
  // do not start from the state they ask for. The behaviour is in
  // `_onFocus`; it is asserted by nothing, and that is worth knowing.
}
