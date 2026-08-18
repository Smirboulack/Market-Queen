import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/asset_gallery.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/cast_panels.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/mq_dialog.dart';

import 'support/sandbox.dart';

/// The way in to an actor or a scene, end to end.
///
/// Every step of it is a modal opening another modal, which is exactly the sort
/// of chain that compiles and then throws on the first frame -- so it is walked
/// here rather than clicked through by hand once and hoped about.
void main() {
  // Never the real profile: see useSandboxConfig.
  useSandboxConfig();

  const window = Size(1420, 940);

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // The labels asserted below are the English sources. Without this the
    // catalogue follows the machine's own locale, and the whole file fails on
    // a French one.
    // The stored language too, not just the translator. AppState reapplies
    // `settings.uiLanguage` on every preference write, so a test that changes
    // any setting would otherwise snap the interface back to whatever this
    // machine has saved -- and every label asserted below is the English one.
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
            body: AdEditorPage(
              app: app,
              onGenerate: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The canvas runs a shimmer that never stops, so `pumpAndSettle` would wait
  /// for it forever. Every step is pumped by hand instead.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the actor chip opens the library, not a question', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Add an actor'));
    await settle(tester);

    // Straight onto the grid, with one maker as its first tile.
    expect(find.text('Select an actor'), findsOneWidget);
    expect(find.byType(CreateAssetTile), findsOneWidget);
    expect(find.text('Search actors'), findsOneWidget);
  });

  testWidgets('the maker tile asks which way in, then opens it', (
    tester,
  ) async {
    // The grid carried both doors for a while, which put the *method* on the
    // library before anybody had thought about the person. One tile now, and
    // the question it asks is the first thing on the way in rather than a
    // property of which tile you happened to hit.
    await pumpEditor(tester);

    await tester.tap(find.text('Add an actor'));
    await settle(tester);
    await tester.tap(find.text('Create an actor'));
    await settle(tester);

    expect(find.byType(IllustratedChoice), findsNWidgets(2));

    // The artwork is really in the bundle. `Image.asset` falls back to the
    // section's glyph when a file is absent, which is the right behaviour and
    // also completely silent -- so a door whose picture had been left out of
    // pubspec would look almost right and never fail a test.
    for (final art in [
      'assets/illustrations/create_with_prompt.png',
      'assets/illustrations/create_with_image.png',
    ]) {
      expect(
        (await rootBundle.load(art)).lengthInBytes,
        greaterThan(0),
        reason: art,
      );
    }

    // `.last` is the bar at the bottom of the card. The same words are its
    // heading as well -- the door is named after what pressing it does --
    // so the finder matches twice and the button is the second of them.
    await tester.tap(find.text('Write who the actor is').last);
    await settle(tester);

    // Step one is the studio and nothing else: naming happens at the end, once
    // there is somebody to name.
    expect(find.text("Let's start"), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text("Actor's name"), findsNothing);
    // Four steps, and no way past the first until a face has been chosen.
    for (final step in ['Appearance', 'Action', 'Voice', 'Bring the actor to life']) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
  });

  testWidgets('the photograph door reads the picture rather than filing it', (
    tester,
  ) async {
    // A picture of a person is not a finished actor: it has no voice, nothing
    // that moves and no personality. So this door leads into the wizard, which
    // fills all three in from the picture, rather than straight to a save.
    await pumpEditor(tester);

    await tester.tap(find.text('Add an actor'));
    await settle(tester);
    await tester.tap(find.text('Create an actor'));
    await settle(tester);
    await tester.tap(find.text('Use a photograph').last);
    await settle(tester);

    expect(find.text("Drop the actor's picture in"), findsOneWidget);
    expect(find.text('Read this picture'), findsOneWidget);
    expect(find.text('What happens next'), findsOneWidget);
    // The name is asked for on the last step, not this one.
    expect(find.text("Actor's name"), findsNothing);
  });

  testWidgets('a scene still files a picture and nothing else', (tester) async {
    // The plain import survives for scenes, which really are just a picture.
    await pumpEditor(tester);

    await tester.tap(find.text('Add a scene'));
    await settle(tester);
    await tester.tap(find.text('Create a scene'));
    await settle(tester);
    await tester.tap(find.text('Use a photograph').last);
    await settle(tester);

    expect(find.text('Drop a picture in'), findsOneWidget);
    expect(find.text('Create the scene'), findsOneWidget);
  });

  testWidgets("the cast actor's name opens the read, the arrows swap them", (
    tester,
  ) async {
    app.actors.save(LibraryAsset(name: 'Camille', prompt: 'A woman, 30s'));
    app.project.setActor(app.actors.assets.first.id);
    addTearDown(app.project.clearActor);

    await pumpEditor(tester);

    // Pressing somebody's name is how every interface says "tell me about this
    // one". It used to throw them off the ad and open the gallery.
    await tester.tap(find.text('Camille').first);
    await settle(tester);

    expect(find.byType(CastPanel), findsOneWidget);
    for (final dial in [
      'Voice',
      'Speed',
      'Stability',
      'Similarity',
      'Style exaggeration',
    ]) {
      expect(find.text(dial), findsOneWidget, reason: dial);
    }

    // The panel is a menu: it hangs over the canvas from the chip, and a press
    // anywhere else puts it away rather than falling through to whatever was
    // under it.
    await tester.tapAt(const Offset(8, 8));
    await settle(tester);
    expect(find.byType(CastPanel), findsNothing);

    // The crossed arrows are the other door: they go to the library to swap
    // them.
    await tester.tap(find.byTooltip('Cast somebody else').first);
    await settle(tester);
    expect(find.text('Select an actor'), findsOneWidget);
  });

  testWidgets('a tooltip inside the cast panel does not throw', (tester) async {
    // The panel used to hang off a CompositedTransformFollower, and a tooltip
    // is an overlay child that has to know where its button is *during layout*
    // -- which a follower layer cannot say, because it only gets its transform
    // when the frame is composited. So hovering the swap button next to the
    // close button threw "the paint transform cannot be reliably computed
    // because of RenderFollowerLayer(s)" and took the frame with it.
    app.actors.save(LibraryAsset(name: 'Hovered', prompt: 'A woman, 30s'));
    app.project.setActor(app.actors.assets.first.id);
    addTearDown(app.project.clearActor);

    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Voice and delivery'));
    await settle(tester);

    final swap = find.descendant(
      of: find.byType(CastPanel),
      matching: find.byTooltip('Cast somebody else'),
    );
    expect(swap, findsOneWidget);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();
    await pointer.moveTo(tester.getCenter(swap));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    // The bubble is really up -- otherwise this would pass by never having
    // asked the tooltip to place itself.
    expect(find.text('Cast somebody else'), findsOneWidget);
    expect(find.byType(CastPanel), findsOneWidget);
  });

  testWidgets("the cast scene's cog opens its four dials", (tester) async {
    app.scenes.save(LibraryAsset(name: 'Kitchen', prompt: 'A small kitchen'));
    app.project.setScene(app.scenes.assets.first.id);
    addTearDown(app.project.clearScene);

    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Light and mood'));
    await settle(tester);

    expect(find.byType(CastPanel), findsOneWidget);
    for (final tweak in SceneTweak.all) {
      expect(find.text(tweak.label), findsOneWidget, reason: tweak.label);
    }
  });
}
