import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/i18n/translator.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/asset_gallery.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/video_poster.dart';

/// The studio, walked in French.
///
/// Every label in here is between a third and a half longer than its English
/// source, and that is where the layout gives: a filter pill that fits "Window
/// daylight" overflows by two hundred pixels on "Lumière du jour par la
/// fenêtre", in stripes, on every frame the modal is open. The test framework
/// fails on a laid-out overflow by itself, so walking the screens is the whole
/// assertion.
void main() {
  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    await app.translator.applyLanguage('fr');
    VideoPosterImage.extraction = false;
  });

  Future<void> pumpEditor(WidgetTester tester, Size size) async {
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
  /// for it forever.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(6, 6));
    await settle(tester);
  }

  // The last one is `minimumSize` from main.dart: the smallest window the app
  // can be dragged to, and the one everything has to still fit in.
  const sizes = [
    Size(1420, 940),
    Size(1280, 800),
    Size(1020, 700),
  ];

  for (final size in sizes) {
    testWidgets('the library and the studio open cleanly at $size', (
      tester,
    ) async {
      for (final kind in AssetKind.values) {
        final adding = kind == AssetKind.actor
            ? tr('Add an actor')
            : tr('Add a scene');

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpEditor(tester, size);

        // The gallery, with its filter rail.
        await tester.tap(find.text(adding));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'gallery $kind $size');

        // Straight into the maker: the modal that used to ask which of the two
        // you meant is gone, and both doors are tiles in the grid.
        expect(find.byType(CreateAssetTile), findsNWidgets(2));
        await tester.tap(find.byType(CreateAssetTile).first);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'studio $kind $size');
      }
    });
  }

  testWidgets('every composer tab and its settings fit', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpEditor(tester, sizes.last);

    for (final tab in ComposerTab.values) {
      if (ComposerSpec.secondary.contains(tab)) {
        await tester.tap(find.text(tr('See more')));
        await settle(tester);
        await tester.tap(find.text(ComposerSpec.of(tab).label).last);
      } else {
        await tester.tap(find.text(ComposerSpec.of(tab).label));
      }
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '${tab.name} bar');

      await tester.tap(find.byTooltip(tr('Settings')));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '${tab.name} settings');
      await dismiss(tester);
    }
  });

  testWidgets('the cast panels fit', (tester) async {
    final actor = app.actors.save(LibraryAsset(name: 'Amélie Fauconnier'));
    final scene = app.scenes.save(LibraryAsset(name: 'Cuisine du matin'));
    app.project
      ..setActor(actor)
      ..setScene(scene);
    addTearDown(() {
      app.project
        ..clearActor()
        ..clearScene();
      app.actors.remove(actor);
      app.scenes.remove(scene);
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpEditor(tester, sizes.last);

    for (final tip in [tr('Voice and delivery'), tr('Light and mood')]) {
      await tester.tap(find.byTooltip(tip));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: tip);
      await dismiss(tester);
    }
  });
}
