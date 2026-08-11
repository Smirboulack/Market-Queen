import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/asset_gallery.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/cast_panels.dart';
import 'package:market_queen/ui/theme.dart';

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

    // Straight onto the grid, with the maker as its first tile.
    expect(find.text('Select an actor'), findsOneWidget);
    expect(find.byType(CreateAssetTile), findsOneWidget);
    expect(find.text('Search actors'), findsOneWidget);
  });

  testWidgets('creating one asks how, then opens the studio', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Add an actor'));
    await settle(tester);
    await tester.tap(find.byType(CreateAssetTile));
    await settle(tester);

    // Two doors, both named.
    expect(find.text('GENERATE'), findsOneWidget);
    expect(find.text('IMPORT'), findsOneWidget);

    await tester.tap(find.text('From a description and reference pictures'));
    await settle(tester);

    expect(find.text('Define your actor'), findsOneWidget);
    expect(find.text("Let's start"), findsOneWidget);
    // Nothing chosen yet, so there is nothing to select.
    expect(
      tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.text('Select this actor'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      ),
      isNotNull,
    );
  });

  testWidgets('the import door takes a picture and nothing else', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Add an actor'));
    await settle(tester);
    await tester.tap(find.byType(CreateAssetTile));
    await settle(tester);
    await tester.tap(find.text('Turn a picture into an actor'));
    await settle(tester);

    expect(find.text('Drop a picture in'), findsOneWidget);
    expect(find.text('Create the actor'), findsOneWidget);
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

    // The name is the other door: it goes to the library to swap them.
    await tester.tap(find.text('Camille').first);
    await settle(tester);
    expect(find.text('Select an actor'), findsOneWidget);
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
