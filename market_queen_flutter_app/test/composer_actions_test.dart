import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/prompt_doctor.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/theme.dart';

/// The four things the prompt bar gained: a send key, a price, a size and a
/// wand.
void main() {
  const window = Size(1420, 940);

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    await app.translator.applyLanguage('en');
  });

  setUp(() {
    app.project.feed.clear();
    app.settings
      ..setPref('imageProvider', null)
      ..setPref('imageModel', null)
      ..setPref('imageSize', null)
      ..setPref('imageQuality', null);
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
            body: AdEditorPage(
              app: app,
              onGenerate: () {},
              onOpenRender: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pickTab(WidgetTester tester, ComposerTab tab) async {
    await tester.tap(find.text(ComposerSpec.of(tab).label));
    await tester.pump();
  }

  /// Every RichText on screen, flattened -- the meter is one, because half of
  /// it is bold.
  bool showsText(String fragment) => find
      .byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(fragment),
      )
      .evaluate()
      .isNotEmpty;

  group('Enter sends', () {
    testWidgets('a prompt and Enter puts a batch in the feed', (tester) async {
      // It used to be Ctrl+Enter, which meant reaching for the mouse and
      // pressing the arrow every single time.
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);

      await tester.enterText(
        find.byType(EditableText).first,
        'a bottle on a windowsill',
      );
      await tester.pump();
      expect(app.project.feed.batches, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(app.project.feed.batches, hasLength(1));
      expect(app.project.feed.batches.first.prompt, 'a bottle on a windowsill');
    });

    testWidgets('Shift+Enter does not send', (tester) async {
      // The bar must not bind it at all: a SingleActivator only fires when the
      // modifiers it does not name are up, so an unbound Shift+Enter reaches
      // the field and breaks the line. (That the newline is actually inserted
      // is the engine's job and is not visible from here -- a widget test types
      // through the text input rather than through the keyboard.)
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);

      final field = find.byType(EditableText).first;
      await tester.enterText(field, 'first line');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle(tester);

      expect(app.project.feed.batches, isEmpty);
      expect(tester.widget<EditableText>(field).controller.text, 'first line');
    });
  });

  group('the bar names what it will spend', () {
    testWidgets('the model and the price sit next to the send button', (
      tester,
    ) async {
      await pumpEditor(tester);

      for (final tab in [
        ComposerTab.actors,
        ComposerTab.image,
        ComposerTab.video,
      ]) {
        await pickTab(tester, tab);
        await settle(tester);

        final model = app.runner.modelLabel(ComposerSpec.of(tab).category);
        expect(model, isNotEmpty, reason: tab.name);
        expect(showsText(model), isTrue, reason: '${tab.name}: model');
        // A price, in whatever shape: an estimate for the press, or the
        // model's own rate when the press cannot be priced.
        expect(showsText(r'$'), isTrue, reason: '${tab.name}: price');
      }
    });
  });

  group('the picture settings follow the model', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
    }

    testWidgets('a model that sizes in pixels offers 1K, 2K and 4K', (
      tester,
    ) async {
      app.settings
        ..setPref('imageProvider', 'bytedance-image')
        ..setPref('imageModel', 'seedream-4-5-251128');

      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await openSettings(tester);

      expect(find.text('Size'), findsOneWidget);
      await tester.tap(find.text('2K'));
      await settle(tester);
      for (final size in ['1K', '2K', '4K']) {
        expect(find.text(size), findsWidgets, reason: size);
      }
      await tester.tap(find.text('4K').last);
      await settle(tester);
      expect(app.settings.prefString('imageSize'), '4K');
    });

    testWidgets('a model with no size input offers no row', (tester) async {
      // Gemini sizes itself from the ratio alone, so a menu there would be a
      // control that does nothing.
      app.settings
        ..setPref('imageProvider', 'gemini-image')
        ..setPref('imageModel', 'gemini-3.1-flash-image');

      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await openSettings(tester);

      expect(find.text('Size'), findsNothing);
      expect(find.text('Quality'), findsNothing);
    });

    testWidgets('OpenAI offers its three quality steps', (tester) async {
      app.settings
        ..setPref('imageProvider', 'openai-image')
        ..setPref('imageModel', 'gpt-image-2');

      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await openSettings(tester);

      expect(find.text('Quality'), findsOneWidget);
      expect(find.text('Size'), findsNothing);

      await tester.tap(find.text('Standard'));
      await settle(tester);
      await tester.tap(find.text('Best').last);
      await settle(tester);
      expect(app.settings.prefString('imageQuality'), 'high');
    });
  });

  group('the prompt doctor picks a writer', () {
    tearDown(() {
      app.settings
        ..setApiKey('gemini', '')
        ..setApiKey('anthropic', '');
    });

    test('a free model wins over a paid one, whatever is chosen', () {
      // The button says "free" or it says which account it will bill, and it
      // has to be telling the truth before it is pressed.
      app.settings
        ..setApiKey('anthropic', 'test-key')
        ..setPref('textProvider', 'anthropic-messages');

      final paid = app.promptDoctor.writer;
      expect(paid.exists, isTrue);
      expect(paid.providerId, 'anthropic-messages');
      expect(paid.free, isFalse);
      expect(paid.account, 'Anthropic (Claude)');

      // A key with a free tier on it takes over, even though the writer chosen
      // for scripts is still Anthropic: nothing marked "improve this" should
      // quietly cost money when it does not have to.
      app.settings.setApiKey('gemini', 'test-key');
      final free = app.promptDoctor.writer;
      expect(free.providerId, 'gemini-generate');
      expect(free.free, isTrue);
    });

    test('every kind of prompt gets its own instruction', () {
      final seen = <String>{};
      for (final kind in PromptKind.values) {
        final instruction = PromptDoctor.systemPromptFor(kind);
        expect(instruction, contains('@Image1'), reason: kind.name);
        expect(instruction, contains('same language'), reason: kind.name);
        seen.add(instruction);
      }
      // Script and voice-over share one; the other four are their own.
      expect(seen, hasLength(PromptKind.values.length - 1));
    });
  });
}
