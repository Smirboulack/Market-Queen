import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/buttons.dart';

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
    test('the brand colour is the same in both skins', () {
      expect(
        const MqTheme(dark: false).primary,
        const MqTheme(dark: true).primary,
      );
      expect(
        const MqTheme(dark: false).focusRing,
        const MqTheme(dark: true).focusRing,
      );
    });

    test('text on a primary fill is readable', () {
      // The reason `onPrimary` exists: white on this pink is about 2.4:1.
      const theme = MqTheme(dark: false);
      expect(_contrast(theme.onPrimary, theme.primary), greaterThan(4.5));
      expect(_contrast(const Color(0xFFFFFFFF), theme.primary), lessThan(3.0));
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
}
