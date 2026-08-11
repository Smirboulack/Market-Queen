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

/// What the app promises about money, asserted rather than trusted.
///
/// "Free tier" is the one label here that can be wrong in a way that costs
/// somebody real money: the free quota covers Flash and not Pro, the two sit on
/// the same key, and nothing at runtime would tell them apart. So the claim is
/// pinned to the models it is actually true of, and a fresh install is checked
/// to land on providers it can run without funding anything first.
void main() {
  const window = Size(1420, 940);

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
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

  test('the free tier is declared where it is real and nowhere else', () {
    final registry = app.registry;

    // Both Pro models are on the same key as the Flash ones and bill from the
    // first token. Marking them free is the expensive mistake.
    final free = {
      for (final model in registry.provider('gemini-generate')!.models)
        if (model.isFree) model.id,
    };
    expect(free, contains('gemini-3.5-flash'));
    expect(free, isNot(contains('gemini-2.5-pro')));
    expect(free, isNot(contains('gemini-3.1-pro-preview')));

    // A fresh install lands on providers it can actually run: the saved
    // preference wins for anyone who has already chosen, so this is only ever
    // the first run's experience.
    expect(registry.defaultProvider('text'), 'gemini-generate');
    expect(registry.defaultProvider('image'), 'gemini-image');
    expect(registry.defaultProvider('captions'), 'groq-whisper');

    // "Auto" takes the head of the list, so the head has to be a free one.
    expect(
      registry.resolveModel('gemini-image', 'auto'),
      'gemini-3.1-flash-image',
    );

    // And the id reaches a task rather than a null out of the factory.
    expect(ProviderFactory.image('gemini-image', ImageRequest()), isNotNull);
    expect(
      ProviderFactory.transcribe('groq-whisper', TranscribeRequest()),
      isNotNull,
    );
  });

  testWidgets('settings names the offer and its catch, but takes no keys', (
    tester,
  ) async {
    await pump(tester, SettingsPage(app: app));
    expect(tester.takeException(), isNull);

    // Looked up through `tr` rather than written out: the catalogue that
    // happens to be loaded depends on the machine's language, and this is a
    // test about what the page says, not about which language it says it in.
    expect(find.text(tr('Start for free')), findsOneWidget);

    // One row per provider that hands out a key for nothing. Asserted by name,
    // because the button beside it reads "Key added" once a key is there and
    // the machine running this may well have one.
    for (final credential in app.registry.credentials()) {
      if (!credential.free) continue;
      expect(
        find.text(credential.label),
        findsOneWidget,
        reason: '${credential.id} is free but is not on the Settings card',
      );
    }

    // The data-usage disclosure sits in the same card as the offer.
    expect(
      find.text(tr(
        'What free costs instead: Google says content sent on the free '
        'Gemini tier is used to improve its products, and the paid tier '
        'is not. That covers your brief, your script and any product '
        'photo you attach. Enable billing on the key to opt out.',
      )),
      findsOneWidget,
    );

    // The keys themselves moved to the Models menu. A second place to type
    // them is how two fields disagree about what the key is.
    expect(find.text(tr('Paste your key')), findsNothing);
  });

  testWidgets('the models page badges the free entries', (tester) async {
    await pump(tester, ModelsPage(app: app));
    expect(tester.takeException(), isNull);
    expect(find.text(tr('Free tier')), findsWidgets);
  });

  testWidgets('every shelf is drawn, with the keys it needs on it', (
    tester,
  ) async {
    await pump(tester, ModelsPage(app: app));
    expect(tester.takeException(), isNull);

    // The five shelves, and inside each one the providers that fill it. A
    // panel that renders its title but none of its providers is the failure
    // this catches -- it looks configured and offers nothing.
    for (final panel in Registry.panels) {
      expect(find.text(tr(panel.title)), findsOneWidget);
      expect(app.registry.providersForPanel(panel.id), isNotEmpty);
    }

    // One key field per shelf that needs it, which means OpenAI is drawn four
    // times on purpose -- it unlocks the writer, the stills, Sora and the
    // voice-over, and each panel has to be usable without leaving it.
    final expected = [
      for (final panel in Registry.panels)
        ...app.registry.credentialsForPanel(panel.id),
    ].length;

    expect(find.byType(KeyField), findsNWidgets(expected));
    expect(
      app.registry.credentialsForPanel('llm'),
      contains(isA<CredentialEntry>().having((c) => c.id, 'id', 'openai')),
    );
  });
}
