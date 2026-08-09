import 'package:flutter/material.dart';

/// One palette, two skins. Light is the default; the choice lives in settings so
/// every window picks it up and it survives a restart.
///
/// Values are the ones the QML `Theme` singleton carried, unchanged: the point
/// of the migration was the layout engine, not a redesign.
@immutable
class MqTheme {
  const MqTheme({required this.dark});

  final bool dark;

  // Surfaces
  Color get background => dark ? const Color(0xFF0B0D12) : const Color(0xFFF4F5F8);
  Color get surface => dark ? const Color(0xFF12151C) : const Color(0xFFFFFFFF);
  Color get surfaceAlt => dark ? const Color(0xFF171C26) : const Color(0xFFF0F2F6);
  Color get surfaceHover => dark ? const Color(0xFF1D2330) : const Color(0xFFE7EAF0);
  Color get border => dark ? const Color(0xFF242B3A) : const Color(0xFFE3E7EE);
  Color get borderStrong => dark ? const Color(0xFF323B4F) : const Color(0xFFC9D0DB);

  // Text
  Color get text => dark ? const Color(0xFFE9EDF6) : const Color(0xFF131720);
  Color get textDim => dark ? const Color(0xFF8A93A8) : const Color(0xFF59616F);
  Color get textFaint => dark ? const Color(0xFF5C6478) : const Color(0xFF8B93A1);

  // Accents. The light variants are darkened so they stay readable on white.
  Color get accent => dark ? const Color(0xFF6C5CE7) : const Color(0xFF5B4BD6);
  Color get accentHover => dark ? const Color(0xFF7D6EF0) : const Color(0xFF4A3BC4);
  Color get accentSoft => dark ? const Color(0xFF211E3D) : const Color(0xFFEDEAFC);
  Color get pink => dark ? const Color(0xFFFF5FA2) : const Color(0xFFE8437F);
  Color get success => dark ? const Color(0xFF2FD07A) : const Color(0xFF0E9F55);
  Color get warning => dark ? const Color(0xFFF5A623) : const Color(0xFFB26A00);
  Color get danger => dark ? const Color(0xFFFF5C5C) : const Color(0xFFD53A3A);

  // Metrics
  static const double radius = 10;
  static const double radiusSmall = 6;
  static const double gap = 12;
  static const double gapLarge = 20;
  static const double pagePadding = 28;
  static const double fieldHeight = 38;

  /// Interaction spec, applied by every clickable in the app:
  ///  - entering hover or pressed is instant, so the item under the pointer is
  ///    always the only fully lit one; only the way back to rest fades, over
  ///    [hoverDuration]. Grouped rows (nav entries, segments, menu options,
  ///    library cards) snap both ways, like native menus, so a fast sweep never
  ///    tints two of them at once;
  ///  - a fill and its border always change together.
  static const hoverDuration = Duration(milliseconds: 120);

  static const double fontSmall = 11;
  static const double fontBody = 13;
  static const double fontTitle = 15;
  static const double fontHeading = 22;

  Color levelColor(int level) => switch (level) {
        1 => success,
        2 => warning,
        3 => danger,
        _ => textDim,
      };

  /// Tinted background for a status pill, readable in both skins.
  Color tint(Color base) => base.withValues(alpha: dark ? 0.18 : 0.12);

  /// The Material theme the app is wrapped in, so stock widgets (text fields,
  /// scrollbars, tooltips) land on the same palette as the hand-drawn ones.
  ThemeData get material {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      surface: surface,
      primary: accent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      fontFamily: 'Segoe UI',
      textTheme: Typography.material2021(
        platform: TargetPlatform.windows,
        colorScheme: scheme,
      ).black.apply(
            bodyColor: text,
            displayColor: text,
            fontFamily: 'Segoe UI',
          ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: surfaceAlt,
          borderRadius: BorderRadius.circular(radiusSmall),
          border: Border.all(color: border),
        ),
        textStyle: TextStyle(color: text, fontSize: fontSmall),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(borderStrong),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
    );
  }
}

/// Makes the palette available without threading it through every constructor.
class AppTheme extends InheritedWidget {
  const AppTheme({super.key, required this.theme, required super.child});

  final MqTheme theme;

  static MqTheme of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(inherited != null, 'No AppTheme above this widget');
    return inherited!.theme;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) => oldWidget.theme.dark != theme.dark;
}

extension ThemeContext on BuildContext {
  MqTheme get mq => AppTheme.of(this);
}
