import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/canvas_view.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/chip.dart';

/// The three geometric promises the composer makes.
///
/// They are asserted rather than eyeballed because all three broke silently the
/// first time: the bar drifted half a settings column left of centre, the panel
/// stole its height from the feed above, and the prompt was two different sizes
/// depending on which tab you were on. None of that shows up in a screenshot of
/// one tab with the panel shut.
///
/// The window is sized to the real one (1420x940, from `main.dart`).
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

  Future<void> pumpEditor(WidgetTester tester, {Size size = window}) async {
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
            backgroundColor: theme.background,
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

  /// The prompt bar itself -- the drop target the whole thing is wrapped in.
  Rect barRect(WidgetTester tester) => tester.getRect(find.byType(DropTarget));

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
  }

  testWidgets('the bar is centred on the page, panel open or shut', (
    tester,
  ) async {
    await pumpEditor(tester);

    final shut = barRect(tester);
    expect(shut.center.dx, moreOrLessEquals(window.width / 2, epsilon: 1));

    await openSettings(tester);
    expect(find.byType(ComposerSettings), findsOneWidget);

    // It may well be narrower -- a panel beside it has to come out of
    // somewhere -- but its middle is still the middle of the page.
    final open = barRect(tester);
    expect(open.center.dx, moreOrLessEquals(window.width / 2, epsilon: 1));
  });

  testWidgets('the shut bar gets the whole width', (tester) async {
    await pumpEditor(tester);

    // The bar is what the studio is used through, so it holds the room until
    // something actually needs it: no gutter is reserved for a panel that is
    // shut. What is left over is the page's own padding and the bar's cap.
    final available = window.width - 2 * MqTheme.pagePadding;
    expect(barRect(tester).width, greaterThan(available * 0.85));
  });

  testWidgets('the settings panel takes no height from the canvas', (
    tester,
  ) async {
    await pumpEditor(tester);

    final before = tester.getRect(find.byType(CanvasView));
    final bottom = barRect(tester).bottom;

    await openSettings(tester);

    expect(tester.getRect(find.byType(CanvasView)), before);
    // The bar stays welded to the bottom of the page whatever grows above it.
    expect(barRect(tester).bottom, moreOrLessEquals(bottom, epsilon: 0.5));
  });

  testWidgets('opening the panel never changes the bar', (tester) async {
    // The promise the panel used to break at both ends of the range: a wide
    // window took 340px off the bar to stand a column beside it, and a narrow
    // one stacked the column over the prompt. Either way the caret moved when
    // the cog was pressed. The panel is in the overlay now, so the bar is the
    // same object before and after on any window.
    for (final size in [
      const Size(2200, 940),
      window,
      const Size(1040, 900),
    ]) {
      await pumpEditor(tester, size: size);

      final shut = barRect(tester);
      await openSettings(tester);

      expect(find.byType(ComposerSettings), findsOneWidget, reason: '$size');
      expect(barRect(tester), shut, reason: '$size');

      // And a press anywhere else puts it away, the way a menu does. Also what
      // leaves the state clean for the next size: the tree survives the next
      // `pumpWidget`, so a panel left open would still be open in it.
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(find.byType(ComposerSettings), findsNothing, reason: '$size');
    }
  });

  testWidgets('the panel hangs above the button that opened it', (tester) async {
    await pumpEditor(tester);
    await openSettings(tester);

    final button = tester.getRect(find.byTooltip('Hide the settings'));
    final panel = tester.getRect(find.byType(ComposerSettings));

    // Bottom edge just above the cog, right edge lined up with it: it grows
    // upward over the canvas rather than downward off the page.
    expect(panel.bottom, lessThanOrEqualTo(button.top));
    expect(button.top - panel.bottom, lessThan(16));
    expect(panel.right, moreOrLessEquals(button.right, epsilon: 0.5));
    expect(panel.top, greaterThan(0));
  });


  testWidgets('the prompt is the same height on every tab', (tester) async {
    // The *prompt*, not the bar around it. The clip shelf now carries a framed
    // reference well underneath its field, so the bars are deliberately
    // different heights -- but the thing the caret lands in must not change
    // size when you switch modes, which is what made the layout jump.
    await pumpEditor(tester);

    final heights = <String, double>{};
    for (final tab in ComposerSpec.primary) {
      final spec = ComposerSpec.of(tab);
      await tester.tap(find.text(spec.label));
      await tester.pump();
      heights[spec.label] = tester
          .getRect(find.byType(EditableText).first)
          .height;
    }

    expect(heights.values.toSet(), hasLength(1));
  });

  testWidgets('an advanced mode is added beside "See more", not over it', (
    tester,
  ) async {
    await pumpEditor(tester);

    final subtitles = ComposerSpec.of(ComposerTab.captions).label;

    // Pumped by hand rather than settled: the canvas runs a shimmer that never
    // stops, so `pumpAndSettle` waits for it forever.
    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text(subtitles).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Both on the bar: the mode that was picked, and the way back to the rest.
    expect(find.text(subtitles), findsOneWidget);
    expect(find.text('See more'), findsOneWidget);

    // And it can be put away again.
    await tester.tap(find.byTooltip('Put this one away'));
    await tester.pump();
    expect(find.text(subtitles), findsNothing);
    expect(find.text('See more'), findsOneWidget);
  });

  testWidgets('all three advanced modes fit on the pill row at once', (
    tester,
  ) async {
    // The worst case, and the one that overflowed: seven pills is wider than
    // the bar they sit above. The test framework fails on a laid-out overflow
    // by itself, so pulling all three out is the whole assertion.
    await pumpEditor(tester);

    for (final tab in ComposerSpec.secondary) {
      await tester.tap(find.text('See more'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(ComposerSpec.of(tab).label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final tab in ComposerSpec.secondary) {
      expect(find.text(ComposerSpec.of(tab).label), findsOneWidget);
    }
    // Nothing left to offer, so the menu is dead but still on the bar.
    expect(find.text('See more'), findsOneWidget);
  });

  testWidgets('picking a model changes the row there and then', (tester) async {
    // The one that had to be closed and reopened before it took: `setPref`
    // wrote the value and told nobody, so the row kept drawing the old name.
    await pumpEditor(tester);
    await tester.tap(find.text(ComposerSpec.of(ComposerTab.video).label));
    await tester.pump();
    await openSettings(tester);

    // Worked out the way the row itself works it out: the name of the model
    // the saved preference names, or the provider's default when there is none.
    String shownModel() {
      final registry = app.registry;
      final providerId = app.runner.providerFor('video');
      final saved = app.settings.prefString('videoModel');
      final modelId = saved.isEmpty
          ? registry.provider(providerId)?.defaultModel ?? ''
          : saved;
      return registry.modelLabel(providerId, modelId);
    }

    final before = shownModel();
    expect(find.text(before), findsOneWidget);

    await tester.tap(find.text(before));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Whichever entry in the menu is not the one already showing. The label
    // rather than every Text in the row: each entry also carries its account's
    // mark, which is two letters until a logo is dropped in.
    final other = find
        .descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.byKey(chipMenuLabelKey),
        )
        .evaluate()
        .map((element) => (element.widget as Text).data ?? '')
        .firstWhere((label) => !label.contains(before), orElse: () => '');
    expect(other, isNotEmpty, reason: 'needs two models to switch between');

    await tester.tap(find.text(other));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final after = shownModel();
    expect(after, isNot(before));
    // The point of the test: the row redrew without being reopened.
    expect(find.text(after), findsOneWidget);
  });

  testWidgets('the picture and video columns end on a price', (tester) async {
    await pumpEditor(tester);

    for (final tab in [ComposerTab.image, ComposerTab.video]) {
      // The panel is a menu now: it covers the pill row while it is up, so it
      // has to be put away before the next tab can be reached.
      if (find.byType(ComposerSettings).evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(8, 8));
        await tester.pump();
      }

      await tester.tap(find.text(ComposerSpec.of(tab).label));
      await tester.pump();
      await openSettings(tester);

      expect(find.text('Cost'), findsOneWidget, reason: '${tab.name} tab');

      // Last in the column, with nothing ruled underneath it.
      final panel = tester.getRect(find.byType(ComposerSettings));
      final cost = tester.getRect(find.text('Cost'));
      expect(cost.bottom, lessThan(panel.bottom));
      expect(panel.bottom - cost.bottom, lessThan(30));
    }
  });
}
