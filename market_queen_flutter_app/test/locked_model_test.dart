import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/key_field.dart';

import 'support/sandbox.dart';

/// A model you have no key for is offered, not hidden.
///
/// The old behaviour had two halves and both were wrong. The menu listed the
/// model as though it were ready, and pressing it selected it -- so the first
/// sign that Google was not set up was a generation failing. And the fix, when
/// you worked out what it was, meant leaving the studio for the Models page,
/// finding the right card among fifteen, pasting a key and walking back.
///
/// So: the row stays, greyed, saying what is missing, and pressing it asks for
/// that one key where you are standing.
void main() {
  // Never the real profile: see useSandboxConfig.
  useSandboxConfig();

  const window = Size(1420, 940);

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // Every label asserted below is the English source.
    app.settings.uiLanguage = 'en';
    await app.translator.applyLanguage('en');
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = MqTheme(dark: false);
    await tester.pumpWidget(
      AppTheme(
        theme: theme,
        child: MaterialApp(
          theme: theme.material,
          home: Scaffold(
            backgroundColor: theme.background,
            body: AdEditorPage(
              key: UniqueKey(),
              app: app,
              onGenerate: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The composer's settings row shows values rather than names, so the model
  /// setting is reached by the value it currently holds.
  Future<void> openModelMenu(WidgetTester tester) async {
    await tester.tap(find.text(ComposerSpec.of(ComposerTab.image).label));
    await tester.pump();
    await tester.tap(find.text(app.runner.modelLabel('image')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a model with no key says so instead of disappearing', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openModelMenu(tester);

    // Nothing has a key on a clean profile, so every row carries the note.
    expect(find.text('Add the API key'), findsWidgets);

    // And the models are still on the menu rather than filtered out of it.
    expect(find.text(app.runner.modelLabel('image')), findsWidgets);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('pressing a locked model asks for that account\'s key', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openModelMenu(tester);

    await tester.tap(find.text('Add the API key').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The key dialog, on the spot -- not the Models page.
    expect(find.text('Add your API key'), findsOneWidget);
    expect(find.byType(KeyField), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a key entered there selects the model that was locked', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openModelMenu(tester);

    // The first row of the menu is the first model of the first image provider,
    // so that provider's account is the one the dialog will ask about.
    final account = app.registry.providers('image').first.credential;
    final model = app.registry.providers('image').first.models.first.id;
    addTearDown(() => app.settings.setApiKey(account, ''));

    await tester.tap(find.text('Add the API key').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The key box, which is the only field the dialog has.
    await tester.enterText(
      find.descendant(
        of: find.byType(KeyField),
        matching: find.byType(EditableText),
      ),
      'sk-a-test-key',
    );
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The key landed, which is the part that matters: the dialog is the whole
    // of the fix.
    expect(app.settings.apiKey(account), 'sk-a-test-key');

    // And the model that was pressed is now the chosen one, so the trip through
    // the dialog did not cost the user the choice they were making.
    expect(app.settings.prefString('imageModel'), model);
  });
}
