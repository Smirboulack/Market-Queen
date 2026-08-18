import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/buttons.dart';
import 'package:market_queen/ui/widgets/chip.dart';

import 'support/sandbox.dart';

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
            // A fresh tree per test. Without it Flutter reuses the previous
            // test's State -- same widget type, same position -- so the
            // composer starts each test on whatever tab, with whatever
            // advanced pills, the one before it left behind.
            body: AdEditorPage(
              key: UniqueKey(),
              app: app,
              onGenerate: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The prompt bar itself -- the drop target the whole thing is wrapped in.
  Rect barRect(WidgetTester tester) => tester.getRect(find.byType(DropTarget));

  /// A menu's open and close animations, with room to spare.
  ///
  /// Generously long on purpose. `pumpAndSettle` cannot be used here -- the
  /// canvas runs a shimmer that never stops, so it would wait forever -- so
  /// the frames are pumped by hand, and a menu that has not finished opening
  /// when the next tap lands stays up and swallows it. A second is far longer
  /// than the ~300ms the route takes, and it costs the test nothing: pumped
  /// time is not real time.
  Future<void> menuSettles(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Opens one setting's menu by pressing its chip.
  Future<void> openSetting(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Change the ${label.toLowerCase()}'));
    await menuSettles(tester);
  }

  /// Puts an open menu away again.
  ///
  /// Checked first, and that is the point: the dismissing tap lands at the top
  /// left of the page, which is only harmless while a menu's barrier is there
  /// to swallow it. With no menu up it reaches whatever is actually at those
  /// coordinates and navigates away from the composer entirely.
  Future<void> closeMenu(WidgetTester tester) async {
    if (find.byType(PopupMenuItem<String>).evaluate().isEmpty) return;
    await tester.tapAt(const Offset(8, 8));
    await menuSettles(tester);
  }

  testWidgets('the bar is centred on the page', (tester) async {
    await pumpEditor(tester);

    final bar = barRect(tester);
    expect(bar.center.dx, moreOrLessEquals(window.width / 2, epsilon: 1));
  });

  testWidgets('the shut bar gets the whole width', (tester) async {
    await pumpEditor(tester);

    // The bar is what the studio is used through, so it holds the room until
    // something actually needs it: no gutter is reserved for a panel that is
    // shut. What is left over is the page's own padding and the bar's cap.
    final available = window.width - 2 * MqTheme.pagePadding;
    expect(barRect(tester).width, greaterThan(available * 0.85));
  });

  testWidgets('every setting is on the bar, showing its value', (
    tester,
  ) async {
    // The point of the change: no cog, and nothing to open before you can see
    // what the next generation is set to.
    await pumpEditor(tester);
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.tap(find.text(ComposerSpec.of(ComposerTab.image).label));
    await tester.pump();

    // The model the bar will spend at, named on the bar itself.
    expect(find.text(app.runner.modelLabel('image')), findsOneWidget);
    expect(find.byTooltip('Change the model'), findsOneWidget);
  });

  testWidgets('a chip opens its own menu and no other', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text(ComposerSpec.of(ComposerTab.image).label));
    await tester.pump();

    // Restored afterwards: the settings store is a real file shared with every
    // other test file running at the same time.
    final provider = app.settings.prefString('imageProvider');
    final model = app.settings.prefString('imageModel');
    final size = app.settings.prefString('imageSize');
    addTearDown(() => app.settings
      ..setPref('imageProvider', provider)
      ..setPref('imageModel', model)
      ..setPref('imageSize', size));

    app.settings
      ..setPref('imageProvider', 'bytedance-image')
      ..setPref('imageModel', 'seedream-4-5-251128');
    await tester.pump();

    // Pressing Size asks about the frame. It does not also offer the model,
    // the format or the quality, which is what the old panel did.
    await openSetting(tester, 'Size');
    for (final size in ['1K', '2K', '4K']) {
      expect(find.text(size), findsWidgets, reason: size);
    }
    expect(find.text('Best'), findsNothing);

    await tester.tap(find.text('4K').last);
    await menuSettles(tester);
    expect(app.settings.prefString('imageSize'), '4K');

    // The tree survives the next `pumpWidget`, so anything left open here is
    // still open in the test after it.
    await closeMenu(tester);
  });

  testWidgets('the bar is the same height on every tab', (tester) async {
    // The whole bar, not just the field in it. The clip shelf used to carry a
    // framed reference well under its prompt that nothing else had, so pressing
    // "Video" grew the bar by the height of that well and pushed the caret, the
    // send button and the feed above them all down the page -- for a mode
    // switch, before anything had been typed. Everything that made the two
    // differ has been moved onto rows that already exist.
    await pumpEditor(tester);

    final fields = <String, double>{};
    final bars = <String, double>{};
    for (final tab in ComposerSpec.primary) {
      final spec = ComposerSpec.of(tab);
      await tester.tap(find.text(spec.label));
      await tester.pump();
      fields[spec.label] =
          tester.getRect(find.byType(EditableText).first).height;
      bars[spec.label] = barRect(tester).height;
    }

    expect(fields.values.toSet(), hasLength(1));
    expect(bars.values.toSet(), hasLength(1), reason: '$bars');
  });

  testWidgets('the footer is one row at every width', (tester) async {
    // The regression this pins. Squeezed, the cast chips used to wrap onto a
    // line *above* the price and the send button, which changed the bar's
    // height as the window was dragged -- so the canvas above it moved, and the
    // actor panel, which hangs off the chip's own position, ended up pointing
    // at where the chip had been.
    //
    // Three widths across the fold: 1120 is wide enough for everything, 880 is
    // where the settings have already folded into a button, 700 is a window
    // dragged to half a laptop screen.
    final heights = <double, double>{};

    for (final width in [1120.0, 880.0, 700.0]) {
      await pumpEditor(tester, size: Size(width, 900));

      // Flutter reports an overflow as a rendering exception, which the harness
      // collects rather than throws. Nothing here may produce one.
      expect(tester.takeException(), isNull, reason: '$width');

      final bar = barRect(tester);
      heights[width] = bar.height;

      // Everything the footer holds is inside the bar it belongs to.
      final send = tester.getRect(find.byType(GradientSendButton));
      expect(send.right, lessThanOrEqualTo(bar.right + 1), reason: '$width');
      expect(send.bottom, lessThanOrEqualTo(bar.bottom + 1), reason: '$width');
      expect(send.left, greaterThanOrEqualTo(bar.left - 1), reason: '$width');
    }

    // One row means one height: an empty prompt is the same bar however wide
    // the window is.
    expect(heights.values.toSet(), hasLength(1), reason: '$heights');
  });

  testWidgets('a narrow window folds the actions behind one button', (
    tester,
  ) async {
    // What replaced the wrapping: the cast stays on the bar, because it is what
    // the ad *is* and it carries the panels, and the verbs go behind a button.
    await pumpEditor(tester, size: const Size(1420, 940));
    expect(find.byTooltip('More actions'), findsNothing);
    expect(find.byTooltip('Add a photo of the product'), findsOneWidget);

    await pumpEditor(tester, size: const Size(700, 900));
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.byTooltip('Add a photo of the product'), findsNothing);

    // And the cast is still on the bar, not inside the sheet.
    expect(find.text('Add an actor'), findsOneWidget);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pump();
    expect(find.byTooltip('Add a photo of the product'), findsOneWidget);
  });

  testWidgets('nothing on the footer is separated by a rule', (tester) async {
    // A hairline between the price and the wand said nothing -- they are
    // already four objects with space around them -- and it only appeared at
    // some widths, which made the bar look like it was rendering differently
    // rather than fitting differently.
    await pumpEditor(tester);

    final bar = barRect(tester);
    final rules = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final constraints = widget.constraints;
      return constraints != null &&
          constraints.maxWidth == 1 &&
          constraints.maxHeight == 24;
    });

    for (final rule in rules.evaluate()) {
      final rect = tester.getRect(find.byWidget(rule.widget));
      expect(
        bar.contains(rect.center),
        isFalse,
        reason: 'a 1px rule at $rect is inside the bar',
      );
    }
  });

  testWidgets('every mode the composer offers is on the bar', (tester) async {
    // There is no menu behind the pills any more. The three modes are the three
    // pills, which is the whole point: a setting that decides how the finished
    // ad sounds is not allowed to live two clicks inside an overflow.
    await pumpEditor(tester);
    await closeMenu(tester);

    for (final tab in ComposerSpec.primary) {
      expect(find.text(ComposerSpec.of(tab).label), findsOneWidget);
    }
    expect(ComposerSpec.primary.length, ComposerTab.values.length);
    expect(find.text('See more'), findsNothing);
  });

  testWidgets('picking a model changes the row there and then', (tester) async {
    // The one that had to be closed and reopened before it took: `setPref`
    // wrote the value and told nobody, so the row kept drawing the old name.
    //
    // Keys first: a model on a keyless account is offered locked, and pressing
    // one asks for the key rather than selecting the model. That is the right
    // behaviour and it is asserted elsewhere; this test is about the row
    // redrawing, which needs a model it is allowed to switch to.
    unlockEveryProvider(app);
    await pumpEditor(tester);
    await closeMenu(tester);
    await tester.tap(find.text(ComposerSpec.of(ComposerTab.video).label));
    await tester.pump();

    // Worked out the way the chip itself works it out: the name of the model
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

    await openSetting(tester, 'Model');

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
    await menuSettles(tester);

    final after = shownModel();
    expect(after, isNot(before));
    // The point of the test: the row redrew without being reopened.
    expect(find.text(after), findsOneWidget);
  });

  testWidgets('the settings row ends on the price', (tester) async {
    await pumpEditor(tester);

    for (final tab in [ComposerTab.image, ComposerTab.video]) {
      await closeMenu(tester);
      await tester.tap(find.text(ComposerSpec.of(tab).label));
      await tester.pump();

      // Nothing to price with an empty prompt -- that rule is asserted in
      // composer_actions_test. Typing one brings the figure back.
      await tester.enterText(
        find.byType(EditableText).first,
        'a bottle on a windowsill',
      );
      await tester.pump();

      final price = find.textContaining(r'$');
      expect(price, findsWidgets, reason: '${tab.name} tab');

      // At the end of the chips, on the same line as them, and left of the
      // send button.
      final bar = barRect(tester);
      final tag = tester.getRect(price.first);
      expect(tag.right, lessThan(bar.right));
      expect(tag.bottom, lessThanOrEqualTo(bar.bottom));
    }
  });
}
