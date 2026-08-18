import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/actor_smith.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/actor_editor.dart';
import 'package:market_queen/ui/dialogs/actor_wizard.dart';
import 'package:market_queen/ui/dialogs/asset_studio.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/chip.dart';
import 'package:market_queen/ui/widgets/buttons.dart';
import 'package:market_queen/ui/widgets/mq_dialog.dart';

import 'support/sandbox.dart';

/// An actor is now four things -- a face, a way of moving, a voice and a
/// personality -- built over four steps and edited in five sections. None of
/// that has a cheap failure mode: a section that overflows or a step that
/// throws on its first frame compiles perfectly and is only ever found by
/// opening it.
///
/// So every screen is opened here, in both languages, at the sizes the window
/// actually gets. The test framework fails on a laid-out overflow by itself,
/// which makes walking the screens most of the assertion.
void main() {
  // Never the real profile: see useSandboxConfig.
  useSandboxConfig();

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    app.settings.uiLanguage = 'en';
    await app.translator.applyLanguage('en');
  });

  /// The canvas and the drop zones run animations that never settle, so
  /// `pumpAndSettle` would wait for them forever. Every step is pumped by hand.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A host whose only job is to open one of the dialogs under test.
  Future<void> pumpHost(
    WidgetTester tester,
    Size size,
    Future<void> Function(BuildContext context) open,
  ) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = MqTheme(dark: false);
    await tester.pumpWidget(
      AppTheme(
        theme: theme,
        child: MaterialApp(
          theme: theme.material,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: GhostButton(
                  text: 'open',
                  onPressed: () => open(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  LibraryAsset madeActor(String name) {
    final actor = LibraryAsset(name: name, prompt: 'A woman in her twenties')
      ..setExtra('createdVia', 'describe')
      ..setExtra('voiceGender', 'female')
      ..setExtra('voiceAge', 'young')
      ..setExtra('voiceName', 'Nathalie')
      ..setExtra('voiceKind', 'designed')
      ..setExtra(ActorAction.key, 'Talking to camera, holding a bottle');
    return actor;
  }

  group('the wizard', () {
    testWidgets('describing walks four steps and blocks on the first', (
      tester,
    ) async {
      await pumpHost(
        tester,
        const Size(1420, 940),
        (context) => showActorWizard(context, app: app),
      );

      for (final step in [
        'Appearance',
        'Action',
        'Voice',
        'Bring the actor to life',
      ]) {
        expect(find.text(step), findsOneWidget, reason: step);
      }

      // Nothing has been chosen, so Next cannot be pressed and says why.
      expect(find.text("Let's start"), findsOneWidget);
      expect(
        find.byTooltip('Pick one of the pictures first.'),
        findsOneWidget,
      );
      // Nothing to save either: the early exit only appears once there is a
      // face worth keeping.
      expect(find.text('Save and close'), findsNothing);
    });

    testWidgets('the photograph route is three steps and says what it does', (
      tester,
    ) async {
      await pumpHost(
        tester,
        const Size(1420, 940),
        (context) => showActorWizard(
          context,
          app: app,
          route: ActorRoute.fromImage,
        ),
      );

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Bring the actor to life'), findsOneWidget);
      // No Appearance or Action step: the picture answers both.
      expect(find.text('Appearance'), findsNothing);

      expect(find.text('What happens next'), findsOneWidget);
      // The claim the screen is not allowed to make, stated as the thing it
      // does instead.
      expect(find.text(ActorProfile.disclaimer), findsOneWidget);
    });
  });

  group('nothing is taller than the window it opens in', () {
    // The regression: the casting studio sized its picture strip from the
    // screen and *then* stacked a header, a name row, a prompt bar and an
    // action row around it, so the card came out taller than the screen it had
    // just measured. The modal scrolls as one piece, so the bar you type in
    // and the button you press both ended up below the bottom edge.
    for (final size in const [
      Size(1020, 700),
      Size(1280, 800),
      Size(1420, 940),
      // Deliberately cramped: a laptop with a scaled display lands here.
      Size(900, 600),
    ]) {
      testWidgets('the wizard fits at $size', (tester) async {
        for (final route in ActorRoute.values) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpHost(
            tester,
            size,
            (context) => showActorWizard(context, app: app, route: route),
          );

          final card = tester.getSize(find.byType(MqModalCard));
          expect(
            card.height,
            lessThanOrEqualTo(size.height),
            reason: 'card $card taller than the window $size on $route',
          );
          expect(card.width, lessThanOrEqualTo(size.width), reason: '$route');
          expect(tester.takeException(), isNull, reason: '$route $size');
        }
      });
    }

    for (final size in const [
      Size(1020, 700),
      Size(1280, 800),
      Size(1420, 940),
      Size(900, 600),
    ]) {
      testWidgets('the editor fits at $size', (tester) async {
        // The editor takes as much of the window as it can get -- three columns
        // of fields do not read at all when they are squeezed -- so "as much as
        // it can get" has to be a number that leaves the card inside the window
        // on every screen it can open on, not only the one it was drawn for.
        app.actors.save(madeActor('Margot'));
        addTearDown(() => app.actors.remove(app.actors.assets.first.id));

        await pumpHost(
          tester,
          size,
          (context) => showActorEditor(
            context,
            app: app,
            actor: app.actors.assets.first,
          ),
        );

        final card = tester.getSize(find.byType(MqModalCard));
        expect(
          card.height,
          lessThanOrEqualTo(size.height),
          reason: 'card $card taller than the window $size',
        );
        expect(card.width, lessThanOrEqualTo(size.width), reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
      });
    }

    testWidgets('the prompt bar stays on screen while the feed scrolls', (
      tester,
    ) async {
      await pumpHost(
        tester,
        const Size(1020, 700),
        (context) => showActorWizard(context, app: app),
      );

      // The bar and the buttons are inside the window, which is the whole
      // point: they are what the feed gives its room up for.
      for (final finder in [
        find.byType(AssetForge),
        find.text('Next'),
        find.text('Cancel'),
      ]) {
        final box = tester.getRect(finder.first);
        expect(box.bottom, lessThanOrEqualTo(700.0), reason: '$finder');
        expect(box.top, greaterThanOrEqualTo(0.0), reason: '$finder');
      }
    });
  });

  group('the editor', () {
    testWidgets('every section opens', (tester) async {
      final actor = madeActor('Camille');
      app.actors.save(actor);
      addTearDown(() => app.actors.remove(app.actors.assets.first.id));

      await pumpHost(
        tester,
        const Size(1420, 940),
        (context) => showActorEditor(
          context,
          app: app,
          actor: app.actors.assets.first,
        ),
      );

      // The actor is on screen throughout, which is the whole point of the
      // layout: it is what every control on the right is changing.
      expect(find.text('Camille'), findsWidgets);

      for (final section in [
        'Overview',
        'Appearance',
        'Voice',
        'Action',
        'Looks',
      ]) {
        await tester.tap(find.text(section).first);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: section);
        expect(find.text('Camille'), findsWidgets, reason: section);
      }
    });

    testWidgets('what the actor is doing is the one thing shown', (
      tester,
    ) async {
      app.actors.save(madeActor('Jules'));
      addTearDown(() => app.actors.remove(app.actors.assets.first.id));

      await pumpHost(
        tester,
        const Size(1420, 940),
        (context) => showActorEditor(
          context,
          app: app,
          actor: app.actors.assets.first,
        ),
      );

      await tester.tap(find.text('Action').first);
      await settle(tester);

      expect(
        find.text('Talking to camera, holding a bottle'),
        findsOneWidget,
      );
    });
  });

  group('in French, where every label is half again as long', () {
    setUp(() async {
      app.settings.uiLanguage = 'fr';
      await app.translator.applyLanguage('fr');
    });

    tearDown(() async {
      app.settings.uiLanguage = 'en';
      await app.translator.applyLanguage('en');
    });

    for (final size in const [Size(1020, 700), Size(1420, 940)]) {
      testWidgets('the wizard opens cleanly at $size', (tester) async {
        for (final route in ActorRoute.values) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpHost(
            tester,
            size,
            (context) => showActorWizard(context, app: app, route: route),
          );
          expect(tester.takeException(), isNull, reason: '$route $size');
        }
      });

      testWidgets('every editor section opens cleanly at $size', (
        tester,
      ) async {
        app.actors.save(madeActor('Camille'));
        addTearDown(() => app.actors.remove(app.actors.assets.first.id));

        await pumpHost(
          tester,
          size,
          (context) => showActorEditor(
            context,
            app: app,
            actor: app.actors.assets.first,
          ),
        );

        for (final section in ActorSection.values) {
          final label = ActorEditor.labelFor(section);
          await tester.tap(find.text(label).first);
          await settle(tester);
          final thrown = tester.takeException();
          if (thrown != null) {
            // ignore: avoid_print
            print('OVERFLOW in $label $size:');
            if (thrown is FlutterError) {
              for (final node in thrown.diagnostics) {
                // ignore: avoid_print
                print('   ${node.toStringDeep()}');
              }
            }
          }
          expect(thrown, isNull, reason: '$label $size');
        }
      });
    }
  });

  group('the voice workshop', () {
    /// Opens the editor on the Voice section, on a clean actor.
    Future<void> openVoice(WidgetTester tester, {String route = 'Design'}) async {
      app.actors.save(madeActor('Adèle'));
      addTearDown(() => app.actors.remove(app.actors.assets.first.id));

      await pumpHost(
        tester,
        const Size(1420, 940),
        (context) => showActorEditor(
          context,
          app: app,
          actor: app.actors.assets.first,
        ),
      );

      await tester.tap(find.text(ActorEditor.labelFor(ActorSection.voice)).first);
      await settle(tester);
      await tester.tap(find.text(route).first);
      await settle(tester);
    }

    /// Puts the voice preference back however this machine had it: it is a real
    /// file shared with every other test running at the same time.
    void restoreVoicePrefs() {
      final provider = app.settings.prefString('voiceProvider');
      final model = app.settings.prefString('voiceModel');
      addTearDown(() => app.settings
        ..setPref('voiceProvider', provider)
        ..setPref('voiceModel', model));
    }

    testWidgets('both providers are offered, and the keyless one is locked', (
      tester,
    ) async {
      // The whole flow used to be ElevenLabs and nothing else -- not as a
      // choice anybody had made, just as the only path there was.
      restoreVoicePrefs();
      app.settings
        ..setPref('voiceProvider', 'elevenlabs')
        ..setApiKey('elevenlabs', 'test-key-not-a-real-one')
        ..setApiKey('minimax', '');
      addTearDown(() => app.settings
        ..setApiKey('elevenlabs', '')
        ..setApiKey('minimax', ''));

      await openVoice(tester);

      // The chip carries its value in its label -- "Provider · ElevenLabs" --
      // so it is found by what it says rather than by a tooltip it only grows
      // in its compact form.
      await tester.tap(find.textContaining('Provider').first);
      await settle(tester);

      expect(find.text('ElevenLabs'), findsWidgets);
      expect(find.text('MiniMax'), findsWidgets);
      // The account with no key is offered with the way out beside it rather
      // than being dropped from the list.
      expect(find.text(lockedByKeyLabel), findsWidgets);

      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
    });

    testWidgets('a voice cannot be designed without a name', (tester) async {
      restoreVoicePrefs();
      app.settings
        ..setPref('voiceProvider', 'elevenlabs')
        ..setApiKey('elevenlabs', 'test-key-not-a-real-one');
      addTearDown(() => app.settings.setApiKey('elevenlabs', ''));

      await openVoice(tester);

      // The name box is seeded from the actor, and the brief is empty, so the
      // button is already refusing -- for the other reason.
      // The value and the placeholder are both the actor's name at this point,
      // so the finder matches the one field through two of its own Texts.
      final name = find.widgetWithText(TextField, 'Adèle').first;
      expect(name, findsOneWidget);

      await tester.enterText(name, '');
      await settle(tester);

      expect(
        find.byTooltip('Give the voice a name first.'),
        findsOneWidget,
        reason: 'an unnamed voice is one nobody can find again',
      );
    });

    testWidgets('with no key the route offers the key instead of the form', (
      tester,
    ) async {
      restoreVoicePrefs();
      app.settings
        ..setPref('voiceProvider', 'minimax-tts')
        ..setApiKey('minimax', '');

      await openVoice(tester, route: 'Clone');

      // Not four dead controls with the reason in their tooltips: one sentence
      // and the button that fixes it.
      expect(find.text(lockedByKeyLabel), findsOneWidget);
      expect(find.text('Clone this voice'), findsNothing);
    });
  });

  group('what a vision model is allowed to hand back', () {
    test('a value outside the vocabulary is dropped, not passed on', () {
      // The regression this exists for: the casting search filters on
      // ElevenLabs' own spellings, and "young adult" instead of "young" writes
      // a query that matches nobody -- silently, since an empty shortlist looks
      // exactly like a brief nobody fits.
      final profile = ActorProfile.fromJson({
        'appearance': 'A woman in her twenties',
        'gender': 'Female',
        'age': 'young adult',
        'tone': 'energetic',
        'use': 'social_media',
        'voice': 'Warm, young, conversational',
      });

      // Case is theirs to get right and ours to fold: "Female" is the value,
      // just shouted.
      expect(profile.gender, 'female');
      // Neither of these is in the vocabulary, so neither narrows the search.
      expect(profile.age, isEmpty);
      expect(profile.tone, isEmpty);
      expect(profile.useCase, 'social_media');
    });

    test('what it saw is written onto the actor in the app\'s own keys', () {
      const profile = ActorProfile(
        appearance: 'A man in his forties',
        gender: 'male',
        age: 'middle_aged',
        tone: 'calm',
        voiceDescription: 'A steady, low voice',
        action: 'Sitting, talking to camera',
      );

      final actor = LibraryAsset(name: 'Read');
      profile.applyTo(actor);

      expect(actor.extraText('voiceGender'), 'male');
      expect(actor.extraText('voiceAge'), 'middle_aged');
      // Unset by the model, so the app picks the one use case a UGC ad is
      // always for rather than leaving the search unaimed.
      expect(actor.extraText('voiceUse'), 'social_media');
      expect(ActorAction.of(actor), 'Sitting, talking to camera');
      expect(actor.extraText('voiceDescription'), 'A steady, low voice');
    });

    test('an action already written by hand is not overwritten', () {
      const profile = ActorProfile(
        appearance: 'A man in his forties',
        action: 'Sitting still',
      );

      final actor = LibraryAsset(name: 'Read')
        ..setExtra(ActorAction.key, 'Walking through a shop');
      profile.applyTo(actor);

      expect(ActorAction.of(actor), 'Walking through a shop');
    });
  });

  group('the parts of an actor that have nothing to look at', () {
    test('looks survive a trip through the store', () {
      final actor = LibraryAsset(name: 'Sarah');
      ActorLooks.save(actor, [
        const ActorLook(id: '1', name: 'Business', path: 'a.png'),
        const ActorLook(id: '2', name: 'Gym', path: 'b.png', prompt: 'in a gym'),
      ]);

      final reloaded = LibraryAsset.fromJson(actor.toJson());
      final looks = ActorLooks.of(reloaded);

      expect(looks.length, 2);
      expect(looks.last.name, 'Gym');
      expect(looks.last.prompt, 'in a gym');
    });
  });
}
