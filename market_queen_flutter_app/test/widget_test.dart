import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/buttons.dart';
import 'package:market_queen/ui/widgets/mq_dialog.dart';

/// Puts a widget under an [AppTheme], which every control in `lib/ui` expects
/// to find above it.
Widget _skin(Widget child, {bool dark = false}) {
  final theme = MqTheme(dark: dark);
  return AppTheme(
    theme: theme,
    child: MaterialApp(
      theme: theme.material,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// WCAG relative luminance, for the contrast claims the palette makes.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : pow((value + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  group('palette', () {
    test('the brand ramp is the same in both skins', () {
      // The interface is greyscale and reverses between the skins; the CTA
      // gradient is the identity and must not. It is a constant on the class
      // rather than a getter for exactly that reason.
      expect(MqTheme.ctaColors.length, 10);
      expect(MqTheme.ctaGradient.colors, MqTheme.ctaColors);
    });

    test('the ink on the CTA is readable on every stop of it', () {
      // Why `onCta` is near-black rather than the reflexive white: the ramp
      // runs from a pale sky blue to a red, and white fails at the pale end
      // badly enough to be unreadable.
      for (final stop in MqTheme.ctaColors) {
        expect(
          _contrast(MqTheme.onCta, stop),
          greaterThan(4.5),
          reason: 'onCta against $stop',
        );
      }
      expect(
        _contrast(const Color(0xFFFFFFFF), MqTheme.ctaColors.first),
        lessThan(3.0),
      );
    });

    test('text on a primary fill is readable in both skins', () {
      // `primary` is ink now, not a hue: black on the light skin, white on the
      // dark one. Both need their opposite on top.
      for (final dark in [false, true]) {
        final theme = MqTheme(dark: dark);
        expect(
          _contrast(theme.onPrimary, theme.primary),
          greaterThan(7.0),
          reason: 'onPrimary, dark=$dark',
        );
      }
    });

    test('body text is readable on its own background', () {
      for (final dark in [false, true]) {
        final theme = MqTheme(dark: dark);
        expect(
          _contrast(theme.textPrimary, theme.background),
          greaterThan(7.0),
          reason: 'primary text, dark=$dark',
        );
        expect(
          _contrast(theme.textSecondary, theme.surface),
          greaterThan(4.5),
          reason: 'secondary text, dark=$dark',
        );
      }
    });

    test('the surface ladder is ordered in both directions', () {
      final light = MqTheme(dark: false);
      // Light: each step down the ladder is darker than the last.
      expect(
        _luminance(light.surface),
        greaterThan(_luminance(light.surfaceSecondary)),
      );
      expect(
        _luminance(light.surfaceSecondary),
        greaterThan(_luminance(light.surfaceTertiary)),
      );

      final dark = MqTheme(dark: true);
      // Dark: the same steps run the other way.
      expect(
        _luminance(dark.surface),
        lessThan(_luminance(dark.surfaceSecondary)),
      );
      expect(
        _luminance(dark.surfaceSecondary),
        lessThan(_luminance(dark.surfaceTertiary)),
      );
    });
  });

  group('interaction spec', () {
    test('a control changes state instantly, in both directions', () {
      // Three looks and no more: at rest, under the pointer, held down. A fade
      // back to rest is a fourth state trailing behind the pointer.
      for (final states in const [
        MqStates(),
        MqStates(hovered: true),
        MqStates(pressed: true),
        MqStates(snap: true),
        MqStates(snap: true, hovered: true),
        MqStates(focused: true),
        MqStates(enabled: false),
      ]) {
        expect(states.duration, Duration.zero);
      }
    });
  });

  group('Pressable', () {
    testWidgets('reports hover, and drops it when the pointer leaves', (
      tester,
    ) async {
      var seen = const MqStates();

      await tester.pumpWidget(
        _skin(
          Pressable(
            onTap: () {},
            builder: (context, states) {
              seen = states;
              return const SizedBox(width: 80, height: 30);
            },
          ),
        ),
      );

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await tester.pump();
      expect(seen.hovered, isFalse);

      await pointer.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pumpAndSettle();
      expect(seen.hovered, isTrue);

      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(seen.hovered, isFalse);
    });

    testWidgets('a disabled control never reports hover or fires', (
      tester,
    ) async {
      var taps = 0;
      var seen = const MqStates();

      await tester.pumpWidget(
        _skin(
          Pressable(
            enabled: false,
            onTap: () => taps++,
            builder: (context, states) {
              seen = states;
              return const SizedBox(width: 80, height: 30);
            },
          ),
        ),
      );

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pumpAndSettle();

      expect(seen.hovered, isFalse);
      expect(seen.enabled, isFalse);

      await tester.tap(find.byType(SizedBox), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('Enter and Space fire it from the keyboard', (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        _skin(
          Pressable(
            onTap: () => taps++,
            builder: (context, states) => const SizedBox(width: 80, height: 30),
          ),
        ),
      );

      // Tab to it, then activate.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(taps, 2);
    });

    testWidgets('a control that goes inert under the pointer goes dark', (
      tester,
    ) async {
      var seen = const MqStates();

      Widget build({required bool enabled}) => _skin(
        Pressable(
          enabled: enabled,
          onTap: () {},
          builder: (context, states) {
            seen = states;
            return const SizedBox(width: 80, height: 30);
          },
        ),
      );

      await tester.pumpWidget(build(enabled: true));

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pumpAndSettle();
      expect(seen.hovered, isTrue);

      // The pointer has not moved; the button simply stopped being one.
      await tester.pumpWidget(build(enabled: false));
      await tester.pumpAndSettle();
      expect(seen.hovered, isFalse);
    });
  });

  // The naming dialogs took the whole window down with them, twice over, and
  // both routes into it were the same defect: one user action reaching the
  // navigator twice. The first pop closed the dialog and the second popped the
  // page underneath, leaving a black screen -- and on the way past, returned a
  // name the user had not confirmed.
  group('naming dialog', () {
    /// What the dialog handed back, once it has closed. Written by the button
    /// that opened it, read by the test afterwards.
    late List<String?> answers;

    /// Opens the prompt from a page that stays on the navigator, so a stray
    /// second pop shows up as that page disappearing.
    Future<void> open(WidgetTester tester) async {
      answers = [];

      await tester.pumpWidget(
        _skin(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await askForName(
                  context,
                  title: 'New project',
                  label: 'Project name',
                  placeholder: 'e.g. Lumen',
                  confirmLabel: 'Create',
                  initial: 'Project 1',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Create'), findsOneWidget);
    }

    testWidgets('Enter accepts once, and leaves the page standing', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(EditableText), 'Lumen glow');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(answers, ['Lumen glow']);
      // The dialog is gone and the page it opened from is not.
      expect(find.text('Create'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('Cancel returns nothing, even from inside the field', (
      tester,
    ) async {
      await open(tester);

      // Type first, so the field holds a name and has the focus. This is the
      // exact sequence that used to create the project on the way out of it:
      // the click blurred the field before the button's own handler ran.
      await tester.enterText(find.byType(EditableText), 'Lumen glow');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(answers, [null]);
      expect(find.text('Create'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
