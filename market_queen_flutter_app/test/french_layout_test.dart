import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/i18n/translator.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/ui/dialogs/asset_gallery.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/mq_dialog.dart';
import 'package:market_queen/ui/widgets/video_poster.dart';

import 'support/sandbox.dart';

/// The studio, walked in French.
///
/// Every label in here is between a third and a half longer than its English
/// source, and that is where the layout gives: a filter pill that fits "Window
/// daylight" overflows by two hundred pixels on "Lumière du jour par la
/// fenêtre", in stripes, on every frame the modal is open. The test framework
/// fails on a laid-out overflow by itself, so walking the screens is the whole
/// assertion.
void main() {
  // Never the real profile: see useSandboxConfig.
  useSandboxConfig();

  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // Stored as well as applied: AppState reapplies the saved language on
    // every preference write, so a French test that changes a setting has to
    // have French saved or it flips to English mid-test.
    app.settings.uiLanguage = 'fr';
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

        // One maker tile, which asks which way in. Both doors are on that
        // modal, and both of them are a paragraph long in French.
        expect(find.byType(CreateAssetTile), findsOneWidget);
        await tester.tap(find.byType(CreateAssetTile));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'doors $kind $size');

        expect(find.byType(IllustratedChoice), findsNWidgets(2));
        await tester.tap(find.byType(IllustratedChoice).first);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'studio $kind $size');
      }
    });
  }

  testWidgets('every composer tab and its settings fit', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpEditor(tester, sizes.last);

    // The narrowest window drops the pill labels and keeps the glyphs, which
    // is the point of the compact mode: French mode names are the longest on
    // the row and they share it with the settings, which cannot shrink. So a
    // pill is reached by its label where there is one and by its tooltip
    // where the label has stood down.
    Finder pill(ComposerTab tab) {
      final label = find.text(ComposerSpec.of(tab).label);
      return label.evaluate().isEmpty
          ? find.byTooltip(ComposerSpec.of(tab).label)
          : label;
    }

    for (final tab in ComposerTab.values) {
      if (ComposerSpec.secondary.contains(tab)) {
        // "See more" is a pill like the others and loses its label too.
        final more = find.text(tr('See more'));
        await tester.tap(
          more.evaluate().isEmpty ? find.byTooltip(tr('See more')) : more,
        );
        await settle(tester);
        // The menu spells them out whatever the pills are doing.
        await tester.tap(find.text(ComposerSpec.of(tab).label).last);
      } else {
        await tester.tap(pill(tab).first);
      }
      await settle(tester);
      // The settings are chips on the bar itself now, so a bar that lays out
      // without overflowing *is* the settings laying out: the French labels
      // are on screen already rather than behind a cog.
      expect(tester.takeException(), isNull, reason: '${tab.name} bar');

      // And each one opens its own menu without overflowing either.
      final model = find.byTooltip(tr('Change the %1').arg(tr('Model').toLowerCase()));
      if (model.evaluate().isNotEmpty) {
        await tester.tap(model);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '${tab.name} model menu');
        await dismiss(tester);
      }
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
