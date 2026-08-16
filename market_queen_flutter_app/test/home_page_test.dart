import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/ui/home_page.dart';
import 'package:market_queen/ui/theme.dart';

/// Home is the page the app opens on, which makes a layout error in it the
/// first thing anybody sees -- and the first version of it had one: the three
/// cards were laid out with `CrossAxisAlignment.stretch` on a Row, which
/// stretches the vertical axis, inside a scroll view where vertical is
/// unbounded. Every launch threw before painting a pixel.
///
/// So this pumps the real page at both of its layouts and asserts nothing was
/// thrown. It is a cheap test and it is the exact one that was missing.
void main() {
  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // The stored language too, not just the translator. AppState reapplies
    // `settings.uiLanguage` on every preference write, so a test that changes
    // any setting would otherwise snap the interface back to whatever this
    // machine has saved -- and every label asserted below is the English one.
    app.settings.uiLanguage = 'en';
    await app.translator.applyLanguage('en');
  });

  Future<void> pumpHome(WidgetTester tester, Size size) async {
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
            body: HomePage(
              app: app,
              onCreateUgc: () {},
              onStoryboard: () {},
              onModels: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('it lays out wide, with the cards side by side', (tester) async {
    await pumpHome(tester, const Size(1420, 940));
    expect(tester.takeException(), isNull);

    // The three ways in, and the news block under them.
    for (final label in ['Create UGC', 'Storyboard', 'Models']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text(HomePage.news.first.title), findsOneWidget);
  });

  testWidgets('it lays out narrow, with the cards stacked', (tester) async {
    // Under the breakpoint, where the row becomes a column -- the branch with
    // no measured height above it at all.
    await pumpHome(tester, const Size(640, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Create UGC'), findsWidgets);
  });

  testWidgets('a short window still lays out, and scrolls', (tester) async {
    // The page is taller than this, so the scroll view is doing real work.
    await pumpHome(tester, const Size(1420, 420));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -260));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('each card leads somewhere', (tester) async {
    var ugc = 0;
    var storyboard = 0;
    var models = 0;

    tester.view
      ..physicalSize = const Size(1420, 940)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = MqTheme(dark: false);
    await tester.pumpWidget(
      AppTheme(
        theme: theme,
        child: MaterialApp(
          theme: theme.material,
          home: Scaffold(
            body: HomePage(
              app: app,
              onCreateUgc: () => ugc += 1,
              onStoryboard: () => storyboard += 1,
              onModels: () => models += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Start an ad'));
    await tester.tap(find.text('Open storyboards'));
    await tester.tap(find.text('Set up the models'));
    await tester.pump();

    expect(ugc, 1);
    expect(storyboard, 1);
    expect(models, 1);
  });
}
