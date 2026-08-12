import 'package:flutter/material.dart';

/// One palette, two skins. Light is the default; the choice lives in settings so
/// every window picks it up and it survives a restart.
///
/// Every colour in the interface comes from a token below -- there are no raw
/// hex values and no `Colors.white` anywhere else in `lib/ui`. The tokens are
/// named after their *role*, not their value, which is what lets the two skins
/// share one set of names: [surfaceHover] is "the fill of something the pointer
/// is on", and it happens to be lighter in one skin and darker in the other.
///
/// The rule the palette is built around: the interface is greyscale, full stop.
/// No tinted glyphs, no coloured focus rings, no brand wash on a selected row.
/// [primary] is ink -- near-black on the light skin, near-white on the dark one
/// -- so the thing you are meant to press reads by contrast rather than by hue.
///
/// The one exception is [ctaGradient], the brand ramp -- sky blue into green.
/// It is spent on the two controls that actually commit something: the send
/// button on the composer and the confirm button of a modal. Nothing else in
/// the app is allowed colour.
@immutable
class MqTheme {
  const MqTheme({required this.dark});

  final bool dark;

  // ------------------------------------------------------------- backgrounds
  // Five depths rather than two: with this many steps a panel can sit on a
  // page, a field inside the panel and a chip inside the field, and each edge
  // is legible without a drop shadow anywhere.

  Color get background =>
      dark ? const Color(0xFF111111) : const Color(0xFFFAFAFA);
  Color get surface => dark ? const Color(0xFF181818) : const Color(0xFFFFFFFF);
  Color get surfaceSecondary =>
      dark ? const Color(0xFF202020) : const Color(0xFFF5F5F5);
  Color get surfaceTertiary =>
      dark ? const Color(0xFF282828) : const Color(0xFFEEEEEE);
  Color get surfaceHover =>
      dark ? const Color(0xFF252525) : const Color(0xFFF0F0F0);
  Color get surfaceActive =>
      dark ? const Color(0xFF303030) : const Color(0xFFE8E8E8);

  /// "Standing proud of [surfaceSecondary]" -- the selected segment of a
  /// segmented control, the one tab that is in front. Composed rather than
  /// picked, because depth runs in opposite directions in the two skins: a
  /// raised thing is lighter than its track in the dark and, being already
  /// white, can only get its contrast from the track darkening in the light.
  Color get surfaceRaised => dark ? surfaceActive : surface;

  // ----------------------------------------------------------------- borders
  Color get border => dark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E5E5);
  Color get borderSubtle =>
      dark ? const Color(0xFF242424) : const Color(0xFFEEEEEE);
  Color get borderStrong =>
      dark ? const Color(0xFF404040) : const Color(0xFFD4D4D4);
  Color get divider => dark ? const Color(0xFF292929) : const Color(0xFFEAEAEA);

  // -------------------------------------------------------------------- text
  // Not pure black on white: #171717 carries the same information and stops the
  // page from vibrating after twenty minutes of use.

  Color get textPrimary =>
      dark ? const Color(0xFFF5F5F5) : const Color(0xFF171717);
  Color get textSecondary =>
      dark ? const Color(0xFFA3A3A3) : const Color(0xFF666666);
  Color get textTertiary =>
      dark ? const Color(0xFF737373) : const Color(0xFF8A8A8A);
  Color get textDisabled =>
      dark ? const Color(0xFF555555) : const Color(0xFFB5B5B5);
  Color get textInverse =>
      dark ? const Color(0xFF111111) : const Color(0xFFFFFFFF);

  // ----------------------------------------------------------------- primary
  // Ink, not a hue. A filled button is black on the light skin and white on the
  // dark one, which is the strongest signal a greyscale interface has and the
  // reason it needs no brand colour to say "press this".
  //
  // The names are kept from the days this was pink so the forty call sites that
  // ask for "the emphatic colour" keep working; what they get is now ink.

  Color get primary => dark ? const Color(0xFFF5F5F5) : const Color(0xFF171717);
  Color get primaryHover =>
      dark ? const Color(0xFFFFFFFF) : const Color(0xFF2E2E2E);
  Color get primaryActive =>
      dark ? const Color(0xFFE0E0E0) : const Color(0xFF404040);

  /// The faintest possible "this one is selected": one step off the surface,
  /// never a wash.
  Color get primarySubtle =>
      dark ? const Color(0xFF232323) : const Color(0xFFF0F0F0);
  Color get primaryMuted =>
      dark ? const Color(0xFF3A3A3A) : const Color(0xFFDCDCDC);

  /// Emphatic *text* on a normal background -- a link, the picked row of a
  /// menu. Plain ink; it earns its emphasis from weight, not colour.
  Color get primaryText => textPrimary;

  /// What goes on top of a [primary] fill: the opposite ink.
  Color get onPrimary =>
      dark ? const Color(0xFF111111) : const Color(0xFFFFFFFF);

  // --------------------------------------------------------------------- CTA
  // The brand ramp, and the only colour left in the interface: sky blue into
  // green, laid across the button rather than sampled from.
  //
  // It used to be ten stops running from that same sky blue all the way to red.
  // Two is better: a ten-stop ramp reads as a rainbow at 140px and as a muddy
  // orange at 40, and the one stop a small control actually shows was never a
  // colour anybody chose.
  //
  // Identical in both skins: an identity that changed with the theme would not
  // be one.

  static const List<Color> ctaColors = [
    Color(0xFF60D1F8),
    Color(0xFF00DF9A),
  ];

  static const LinearGradient ctaGradient = LinearGradient(
    colors: ctaColors,
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// The same ramp turned 45°, for square-ish targets (the send disc) where a
  /// left-to-right sweep across 32px would barely leave the blue end.
  static const LinearGradient ctaGradientDiagonal = LinearGradient(
    colors: ctaColors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// What is legible on top of the ramp.
  ///
  /// Near-black, and it has to be: both ends are light enough that white gives
  /// under 2:1 and cannot be read at all, while this holds 10:1 against either.
  static const Color onCta = Color(0xFF0F0F0F);

  /// The ramp dimmed to a disabled fill, so a CTA that cannot be pressed still
  /// reads as the same control rather than turning into a grey chip.
  LinearGradient get ctaGradientMuted => LinearGradient(
    colors: [
      for (final colour in ctaColors)
        Color.alphaBlend(colour.withValues(alpha: 0.22), surfaceSecondary),
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // -------------------------------------------------------- system feedback
  // Kept in colour even though the rest is monochrome: "it failed" is the one
  // thing that must not need reading to be noticed.

  Color get success => dark ? const Color(0xFF61C58A) : const Color(0xFF3F9B68);
  Color get successSubtle =>
      dark ? const Color(0xFF1D3427) : const Color(0xFFE8F5EE);
  Color get successText =>
      dark ? const Color(0xFF8AD9A8) : const Color(0xFF28734A);

  Color get warning => dark ? const Color(0xFFE5AE5C) : const Color(0xFFC98A32);
  Color get warningSubtle =>
      dark ? const Color(0xFF382B19) : const Color(0xFFFFF4DF);
  Color get warningText =>
      dark ? const Color(0xFFF0C57D) : const Color(0xFF8A5B18);

  Color get error => dark ? const Color(0xFFF07878) : const Color(0xFFD65353);
  Color get errorSubtle =>
      dark ? const Color(0xFF3A2020) : const Color(0xFFFCEAEA);
  Color get errorText =>
      dark ? const Color(0xFFF59B9B) : const Color(0xFFA43838);

  Color get info => dark ? const Color(0xFF79A9E5) : const Color(0xFF4C82C4);
  Color get infoSubtle =>
      dark ? const Color(0xFF1E2C3D) : const Color(0xFFEAF2FC);
  Color get infoText =>
      dark ? const Color(0xFFA7C8F2) : const Color(0xFF315F96);

  // ------------------------------------------------------------ interaction

  /// Keyboard focus. Ink, so it reads as "you are here" without putting a
  /// second colour on a page that has one.
  Color get focusRing =>
      dark ? const Color(0xFF8A8A8A) : const Color(0xFF171717);

  Color get selection =>
      dark ? const Color(0xFF3F3F3F) : const Color(0xFFD6D6D6);

  /// The scrim a modal drops over the page. There is no blur behind it any
  /// more: a `BackdropFilter` over a live tree cost a full-window raster on
  /// every frame and, when a dialog closed mid-frame, took the composition down
  /// with it. Darkening says the same thing for nothing.
  Color get overlay => dark ? const Color(0xB3000000) : const Color(0x66000000);

  /// Status text on its own tinted pill, in the matching subtle fill.
  Color levelColor(int level) => switch (level) {
    1 => successText,
    2 => warningText,
    3 => errorText,
    _ => textSecondary,
  };

  Color levelTint(int level) => switch (level) {
    1 => successSubtle,
    2 => warningSubtle,
    3 => errorSubtle,
    _ => surfaceSecondary,
  };

  // ------------------------------------------------------------------ metrics
  static const double radius = 10;
  static const double radiusSmall = 6;

  /// Cards that hold other cards: the script sheet, the composer.
  static const double radiusLarge = 14;
  static const double radiusPill = 999;
  static const double gap = 12;
  static const double gapLarge = 20;
  static const double pagePadding = 28;
  static const double fieldHeight = 40;

  /// How wide the studio's own column is allowed to get, whatever the monitor.
  ///
  /// The prompt bar and the feed above it are one column and share this number,
  /// which is what makes them read as one object: a feed that spans a 27" screen
  /// while the bar underneath stops at 1180 is two things that happen to be on
  /// the same page. Past this the send button ends up at the far edge of the
  /// desk while the caret is in the middle of it, and a picture ends up four
  /// feet from the prompt that asked for it.
  static const double contentMaxWidth = 1180;

  // The three columns of the window. Fixed, because all three carry labels that
  // must not wrap: the nav's own entries, the crumb trail, and the rail's
  // two-across trait pickers.
  static const double navWidth = 240;
  static const double railWidth = 400;
  static const double topBarHeight = 64;

  /// Interaction spec, applied by every clickable in the app:
  ///  - three looks and no more: at rest, under the pointer, held down. Every
  ///    change between them is instant in both directions, so the item under the
  ///    pointer is the only tinted one at any instant and leaving a control
  ///    leaves nothing behind;
  ///  - a fill and its border always change together;
  ///  - nothing moves. Hover changes colour, never size or position, and never
  ///    reveals a control that pushes its neighbours around.
  ///
  /// [MqStates.duration] is what enforces the first rule. This constant is only
  /// for the few places that fade something *other* than a control's own state:
  /// a field's focus ring, a drop zone taking a drag, a badge appearing on a
  /// thumbnail.
  static const hoverDuration = Duration(milliseconds: 120);

  // -------------------------------------------------------------- typography
  // Inter, bundled. It was drawn for interfaces at exactly these sizes: tall
  // x-height, open apertures, unambiguous 1/l/I -- which is the difference
  // between reading a model id and squinting at one.

  static const String fontFamily = 'Inter';

  /// Inter covers Latin, Greek and Cyrillic. Chinese and Arabic are not in the
  /// file, so name what should carry them instead of letting the shaper draw
  /// boxes. Families that do not exist on the machine are skipped.
  static const List<String> fontFallback = [
    'Segoe UI Variable Text',
    'Segoe UI',
    'SF Pro Text',
    'Noto Sans',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Geeza Pro',
    'Noto Sans Arabic',
    'DejaVu Sans',
  ];

  /// A ladder, not a set of arbitrary numbers. Each step is far enough from the
  /// last to be read as a different rank, and the bottom of it is 11px rather
  /// than the 8 or 9 an interface ends up at when captions are added one at a
  /// time.
  ///
  /// [fontMicro] is for the things that are not sentences: overlines, badge
  /// numbers, a duration in the corner of a thumbnail.
  static const double fontMicro = 11;
  static const double fontSmall = 12;
  static const double fontLabel = 13;
  static const double fontBody = 14;
  static const double fontTitle = 16;
  static const double fontHeading = 24;

  /// Line height as a multiple of the size. Body text gets room to breathe;
  /// headings are tightened, because a 24px line with 1.45 leading reads as two
  /// separate objects rather than one title.
  static const double lineBody = 1.45;
  static const double lineTight = 1.25;

  /// Inter is drawn slightly wide for small sizes and slightly loose for large
  /// ones; a touch of tracking in each direction is what makes it look set
  /// rather than typed.
  static const double trackHeading = -0.4;
  static const double trackTitle = -0.2;
  static const double trackSmall = 0.1;

  /// The overline ("YOUR AD"): small, spaced, and the only place caps are used.
  static const double trackOverline = 0.9;

  /// Tinted background for a status pill, readable in both skins.
  Color tint(Color base) => base.withValues(alpha: dark ? 0.18 : 0.12);

  /// The Material theme the app is wrapped in, so stock widgets (text fields,
  /// scrollbars, tooltips, popup menus) land on the same palette as the
  /// hand-drawn ones.
  ThemeData get material {
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primarySubtle,
      onPrimaryContainer: primaryText,
      secondary: textSecondary,
      onSecondary: textInverse,
      error: error,
      onError: textInverse,
      errorContainer: errorSubtle,
      onErrorContainer: errorText,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceTertiary,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: borderSubtle,
      shadow: const Color(0xFF000000),
      scrim: overlay,
    );

    // The one style the whole tree inherits. `Text` merges its own style over
    // the ambient `DefaultTextStyle`, so setting the family, the line height and
    // the fallback chain once here reaches every label in the app -- call sites
    // only ever name a size, a colour and a weight.
    final body = TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      fontSize: fontBody,
      height: lineBody,
      leadingDistribution: TextLeadingDistribution.even,
      color: textPrimary,
    );

    final typography = Typography.material2021(
      platform: TargetPlatform.windows,
      colorScheme: scheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: divider,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: (dark ? typography.white : typography.black)
          .apply(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            bodyColor: textPrimary,
            displayColor: textPrimary,
          )
          .copyWith(
            // What every `Text` without an explicit style inherits.
            bodyMedium: body,
            // What `TextField` measures itself against.
            bodyLarge: body,
          ),
      // The hand-drawn controls paint their own hover and press states, so the
      // ripple and the press highlight are turned off -- letting Material draw
      // them underneath would give half the app two of each.
      //
      // Hover is the exception and must stay real: the one thing in here that
      // Material still draws by itself is the popup menu, and its rows are
      // `InkWell`s that take their hover tint from exactly this colour. Blanking
      // it left every dropdown in the app with no rollover at all.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: surfaceHover,
      focusColor: Colors.transparent,
      splashColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: selection,
        selectionHandleColor: primary,
      ),
      dividerTheme: DividerThemeData(color: divider, space: 1, thickness: 1),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: surfaceTertiary,
          borderRadius: BorderRadius.circular(radiusSmall),
          border: Border.all(color: border),
        ),
        textStyle: TextStyle(
          color: textPrimary,
          fontSize: fontSmall,
          height: lineTight,
        ),
      ),
      // Set once, so the four `showMenu` call sites stop describing a menu.
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: dark ? const Color(0x66000000) : const Color(0x1A000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MqTheme.radius),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: fontLabel),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? textTertiary
              : borderStrong,
        ),
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
  bool updateShouldNotify(AppTheme oldWidget) =>
      oldWidget.theme.dark != theme.dark;
}

extension ThemeContext on BuildContext {
  MqTheme get mq => AppTheme.of(this);
}
