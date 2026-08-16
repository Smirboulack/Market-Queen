import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/i18n/translator.dart';
import 'package:market_queen/providers/registry.dart';
import 'package:market_queen/providers/types.dart';
import 'package:market_queen/ui/models_page.dart';
import 'package:market_queen/ui/settings_page.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/key_field.dart';

/// What the app promises about money.
///
/// This file used to assert that the "free tier" badges were on the right
/// models. There are no badges any more, and this is the same test inverted:
/// nothing anywhere may tell somebody a model is free. A free tier is a
/// provider's promotion, metered in units this app cannot see and withdrawn
/// whenever they like -- so on the one screen where being wrong costs the user
/// real money, the app says nothing rather than something it cannot stand
/// behind.
void main() {
  const window = Size(1420, 940);

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // The labels asserted below are the English sources. Without this the
    // catalogue follows the machine's own locale, and the whole file fails on
    // a French one.
    await app.translator.applyLanguage('en');
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
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
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pump();
  }

  test('nothing in the catalogue claims to be free', () {
    for (final provider in app.registry.entries) {
      expect(
        provider.note.toLowerCase(),
        isNot(contains('free')),
        reason: '${provider.id} note',
      );
    }
    for (final credential in app.registry.credentials()) {
      expect(
        credential.note.toLowerCase(),
        isNot(contains('free')),
        reason: '${credential.id} note',
      );
    }
  });

  test('a fresh install still lands on providers that exist', () {
    final registry = app.registry;

    // The defaults are the cheapest of each shelf rather than the free ones,
    // but they still have to resolve to something the factory can build.
    expect(registry.defaultProvider('text'), 'gemini-generate');
    expect(registry.defaultProvider('image'), 'gemini-image');
    expect(registry.defaultProvider('captions'), 'groq-whisper');

    expect(ProviderFactory.image('gemini-image', ImageRequest()), isNotNull);
    expect(
      ProviderFactory.transcribe('groq-whisper', TranscribeRequest()),
      isNotNull,
    );
  });

  testWidgets('the settings page makes no free offer', (tester) async {
    await pump(tester, SettingsPage(app: app));
    expect(tester.takeException(), isNull);

    expect(find.text(tr('Start for free')), findsNothing);

    // What survives is the part that was never about money: Google trains on
    // what you send unless the key has billing enabled.
    expect(
      find.text(tr('What Gemini does with what you send')),
      findsOneWidget,
    );

    // The keys themselves live in the Models menu. A second place to type them
    // is how two fields disagree about what the key is.
    expect(find.text(tr('Paste your key')), findsNothing);
  });

  testWidgets('the models page badges nothing as free', (tester) async {
    await pump(tester, ModelsPage(app: app));
    expect(tester.takeException(), isNull);
    expect(find.text(tr('Free tier')), findsNothing);
  });

  testWidgets('each tab shows its own shelf, and only that one', (
    tester,
  ) async {
    await pump(tester, ModelsPage(app: app));
    expect(tester.takeException(), isNull);

    // Every shelf is reachable: the tab row is always drawn in full, whichever
    // one is open.
    for (final panel in Registry.panels) {
      expect(find.text(tr(panel.title)), findsWidgets);
      // Keys is a shelf of accounts rather than of models, so it is the one
      // with no provider categories behind it.
      if (panel.id == 'keys') continue;
      expect(app.registry.providersForPanel(panel.id), isNotEmpty);
    }

    // Keys live on one shelf and one shelf only. They used to be a band inside
    // every account card, so an account selling on four shelves had its key
    // field drawn four times and setting the app up meant touring the tabs
    // looking for the empty ones.
    for (final panel in Registry.panels) {
      await tester.tap(find.text(tr(panel.title)).first);
      await tester.pump();

      expect(
        find.byType(KeyField),
        panel.id == 'keys'
            // Every account there is, each exactly once.
            ? findsNWidgets(app.registry.credentials().length)
            : findsNothing,
        reason: 'panel ${panel.id}',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
