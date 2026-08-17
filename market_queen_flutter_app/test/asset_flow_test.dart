import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/asset_gallery.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/cast_panels.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/mq_dialog.dart';

/// The way in to an actor or a scene, end to end.
///
/// Every step of it is a modal opening another modal, which is exactly the sort
/// of chain that compiles and then throws on the first frame -- so it is walked
/// here rather than clicked through by hand once and hoped about.
void main() {
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
              onOpenRender: () {},
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

    expect(find.byType(BigChoice), findsNWidgets(2));
    await tester.tap(find.text('Write who they are'));
    await settle(tester);

    // Step one of the wizard is the old studio, with the name field promoted
    // out of the button row.
    expect(find.text("Let's start"), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text("Actor's name"), findsOneWidget);
    // Four steps, and no way past the first until a face has been chosen.
    for (final step in ['Appearance', 'Action', 'Voice', 'Bring them to life']) {
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
    await tester.tap(find.text('Use a photograph'));
    await settle(tester);

    expect(find.text('Drop their picture in'), findsOneWidget);
    expect(find.text('Create the actor'), findsOneWidget);
    expect(find.text('What happens when you press Create'), findsOneWidget);
  });

  testWidgets('a scene still files a picture and nothing else', (tester) async {
    // The plain import survives for scenes, which really are just a picture.
    await pumpEditor(tester);

    await tester.tap(find.text('Add a scene'));
    await settle(tester);
    await tester.tap(find.text('Create a scene'));
    await settle(tester);
    await tester.tap(find.text('Use a photograph'));
    await settle(tester);

    expect(find.text('Drop a picture in'), findsOneWidget);
    expect(find.text('Create the scene'), findsOneWidget);
  });

  testWidgets("the cast actor's cog opens the read, its name swaps them", (
    tester,
  ) async {
    app.actors.save(LibraryAsset(name: 'Camille', prompt: 'A woman, 30s'));
    app.project.setActor(app.actors.assets.first.id);
    addTearDown(app.project.clearActor);

    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Voice and delivery'));
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

    // The panel is a menu now: it hangs over the canvas from the cog, and a
    // press anywhere else puts it away rather than falling through to whatever
    // was under it.
    await tester.tapAt(const Offset(8, 8));
    await settle(tester);
    expect(find.byType(CastPanel), findsNothing);

    // The name is the other door: it goes to the library to swap them.
    await tester.tap(find.text('Camille').first);
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
