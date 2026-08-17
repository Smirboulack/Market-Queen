import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/actor_smith.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/actor_editor.dart';
import 'package:market_queen/ui/dialogs/actor_wizard.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/buttons.dart';

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
      ..setExtra(ActorPersona.actionKey, 'Talking to camera, holding a bottle')
      ..setExtra(ActorPersona.styleKey, 'Short sentences, never salesy');
    ActorPersona.setTraits(actor, ['friendly', 'gen-z']);
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
        'Bring them to life',
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
      expect(find.text('Bring them to life'), findsOneWidget);
      // No Appearance or Action step: the picture answers both.
      expect(find.text('Appearance'), findsNothing);

      expect(find.text('What happens when you press Create'), findsOneWidget);
      // The claim the screen is not allowed to make, stated as the thing it
      // does instead.
      expect(find.text(ActorProfile.disclaimer), findsOneWidget);
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
        'Personality',
        'Looks',
      ]) {
        await tester.tap(find.text(section).first);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: section);
        expect(find.text('Camille'), findsWidgets, reason: section);
      }
    });

    testWidgets('the personality the user set is the one shown', (
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

      await tester.tap(find.text('Personality').first);
      await settle(tester);

      expect(find.text('Short sentences, never salesy'), findsOneWidget);
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
        'personality': ['friendly', 'invented', 'gen-z'],
      });

      // Case is theirs to get right and ours to fold: "Female" is the value,
      // just shouted.
      expect(profile.gender, 'female');
      // Neither of these is in the vocabulary, so neither narrows the search.
      expect(profile.age, isEmpty);
      expect(profile.tone, isEmpty);
      expect(profile.useCase, 'social_media');
      // Only the traits the app actually has pills for survive.
      expect(profile.traits, ['friendly', 'gen-z']);
    });

    test('what it saw is written onto the actor in the app\'s own keys', () {
      const profile = ActorProfile(
        appearance: 'A man in his forties',
        gender: 'male',
        age: 'middle_aged',
        tone: 'calm',
        voiceDescription: 'A steady, low voice',
        traits: ['professional'],
        speakingStyle: 'Measured, no hype',
        action: 'Sitting, talking to camera',
      );

      final actor = LibraryAsset(name: 'Read');
      profile.applyTo(actor);

      expect(actor.extraText('voiceGender'), 'male');
      expect(actor.extraText('voiceAge'), 'middle_aged');
      // Unset by the model, so the app picks the one use case a UGC ad is
      // always for rather than leaving the search unaimed.
      expect(actor.extraText('voiceUse'), 'social_media');
      expect(ActorPersona.traitsOf(actor), ['professional']);
      expect(actor.extraText(ActorPersona.actionKey), 'Sitting, talking to camera');
      expect(actor.extraText('voiceDescription'), 'A steady, low voice');
    });

    test('an action already written by hand is not overwritten', () {
      const profile = ActorProfile(
        appearance: 'A man in his forties',
        action: 'Sitting still',
      );

      final actor = LibraryAsset(name: 'Read')
        ..setExtra(ActorPersona.actionKey, 'Walking through a shop');
      profile.applyTo(actor);

      expect(actor.extraText(ActorPersona.actionKey), 'Walking through a shop');
    });
  });

  group('the parts of an actor that have nothing to look at', () {
    test('the persona reaches the writer as a sentence', () {
      final actor = LibraryAsset(name: 'Sarah')
        ..setExtra(ActorPersona.energyKey, 0.9)
        ..setExtra(ActorPersona.styleKey, 'Never sounds like an advert');
      ActorPersona.setTraits(actor, ['friendly', 'bold']);

      final brief = ActorPersona.brief(actor);
      expect(brief, contains('Friendly'));
      expect(brief, contains('Bold'));
      expect(brief, contains('high energy'));
      expect(brief, contains('Never sounds like an advert'));
    });

    test('an actor nobody described contributes nothing', () {
      expect(ActorPersona.brief(LibraryAsset(name: 'Blank')), isEmpty);
    });

    test('a trait toggles both ways', () {
      final actor = LibraryAsset(name: 'Sarah');
      ActorPersona.toggleTrait(actor, 'bold');
      expect(ActorPersona.traitsOf(actor), ['bold']);
      ActorPersona.toggleTrait(actor, 'bold');
      expect(ActorPersona.traitsOf(actor), isEmpty);
    });

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
