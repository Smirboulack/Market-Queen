import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../../models/asset_library.dart' show MediaKind;
import '../../models/canvas_feed.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';

/// The three things the composer can be asked for.
///
/// All three are on the bar. There were six: a voice-over on its own, a
/// subtitle burner and an enlarger sat behind a "See more" menu, and the
/// cost of that menu was not the clutter -- it was that the voice engine the
/// ad is read with could only be changed from inside it. A setting that
/// decides how the finished film sounds should not be two clicks and a guess
/// away from the ad it belongs to.
enum ComposerTab { actors, image, video }

/// Everything that differs between one tab and the next, in one place.
///
/// The composer is a single widget that reshapes itself, not six widgets: the
/// bar, the settings column and the send button are identical in every mode and
/// only their contents change. This is that difference, written down, so a new
/// mode is a row here instead of a fourth copy of the bar.
class ComposerSpec {
  const ComposerSpec({
    required this.label,
    required this.icon,
    required this.category,
    required this.kind,
    required this.placeholder,
    this.prompted = true,
    this.tall = false,
    this.batched = false,
    this.maxCount = 1,
    this.referenceKinds = const {MediaKind.image},
    this.multipleReferences = true,
    this.picksAspect = false,
    this.picksLength = false,
  });

  final String label;
  final String icon;

  /// Which shelf of the registry its models come off.
  final String category;

  /// How the canvas draws what it produces.
  final CanvasKind kind;

  final String placeholder;

  /// Whether there is anything to type. The two source-only tabs have nothing
  /// to say -- you hand them a file.
  final bool prompted;

  /// A script needs room; a prompt does not.
  final bool tall;

  /// Whether several can be asked for at once.
  final bool batched;
  final int maxCount;

  /// What this mode can be handed at all.
  ///
  /// The model narrows it further -- an image-to-video endpoint takes one
  /// opening frame and no clips at all -- but this is the floor, and it is not
  /// a model's business: dropping a clip on the picture tab is not a limitation
  /// of some endpoint, it is a category error. Each kind in here earns its own
  /// button, with its own glyph, so "add a reference" stops meaning four
  /// different things behind one paperclip.
  final Set<MediaKind> referenceKinds;

  bool get takesReferences => referenceKinds.isNotEmpty;

  /// Off for the tabs that work on exactly one file, where a second reference
  /// would be a second answer to an unambiguous question.
  final bool multipleReferences;

  final bool picksAspect;
  final bool picksLength;

  static ComposerSpec of(ComposerTab tab) => switch (tab) {
    ComposerTab.actors => ComposerSpec(
      label: tr('Talking actors'),
      icon: 'user-voice-line',
      category: 'avatar',
      kind: CanvasKind.ad,
      placeholder: tr(
        'Write the script your actor will read. Point at the cast and your '
        'product by name: @Marie, @Image1.',
      ),
      tall: true,
      // A photograph of the product, and nothing else.
      //
      // It used to take clips as well, and that was a promise the mode does not
      // keep: an avatar model is handed a person, a place and a script, and a
      // reference clip has nowhere to go in that request. Offering the button
      // meant offering an attachment that was carried as far as the send path
      // and dropped. This is the only mode where the cast is addressable,
      // because it is the only one that has a cast.
      referenceKinds: const {MediaKind.image},
      picksAspect: true,
      picksLength: true,
    ),
    ComposerTab.video => ComposerSpec(
      label: tr('Video'),
      icon: 'clapperboard-line',
      category: 'video',
      kind: CanvasKind.video,
      placeholder: tr(
        'Describe the shot, and point at what you dropped in: @Image1, '
        '@Video1, @Audio1.',
      ),
      batched: true,
      maxCount: 4,
      // The ceiling. What the chosen model actually takes is narrower and is
      // read off its own schema -- an image-to-video endpoint has one opening
      // frame and no lists at all.
      referenceKinds: const {MediaKind.image, MediaKind.video, MediaKind.audio},
      picksAspect: true,
      picksLength: true,
    ),
    ComposerTab.image => ComposerSpec(
      label: tr('Image'),
      icon: 'image-line',
      category: 'image',
      kind: CanvasKind.image,
      placeholder: tr(
        'Describe the picture, and point at your references: @Image1.',
      ),
      batched: true,
      maxCount: 10,
      // Pictures only. A clip handed to a picture model is dropped on the way
      // out, so offering to attach one was an invitation to be ignored.
      referenceKinds: const {MediaKind.image},
      picksAspect: true,
    ),
  };

  /// In the order they are reached for: the actor and the stills come first,
  /// and video last, because video is what you shoot once everything else is
  /// settled -- and the most expensive thing to shoot twice.
  static const List<ComposerTab> primary = [
    ComposerTab.actors,
    ComposerTab.image,
    ComposerTab.video,
  ];
}

/// The row of pills above the bar.
///
/// It is a separate object from the bar on purpose -- a frame floating over the
/// canvas rather than a strip inside the input -- so that what you are making
/// reads as a choice you have already made, and the bar underneath is only
/// about what you are saying.
class ComposerTabBar extends StatelessWidget {
  const ComposerTabBar({
    super.key,
    required this.current,
    required this.onPicked,
  });

  final ComposerTab current;
  final ValueChanged<ComposerTab> onPicked;

  static const double _pillHeight = 34;
  static const double _framePadding = 5;

  /// Half the height of a single row of pills, so the frame is a stadium
  /// while everything is on one line and a rounded rectangle if it ever needs
  /// two, instead of a stadium whose curve cuts through the end pills.
  static const double _frameRadius = _pillHeight / 10 + _framePadding;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.all(_framePadding),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(_frameRadius),
        border: Border.all(color: mq.border),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tab in ComposerSpec.primary)
            _Pill(
              spec: ComposerSpec.of(tab),
              selected: tab == current,
              onTap: () => onPicked(tab),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final ComposerSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // The pills touch, so hover snaps both ways and only one is ever lit.
      snap: true,
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) {
        // The chosen one is filled with ink and the rest are bare. It is the
        // strongest contrast a greyscale interface has, which is what a "you
        // are here" needs to be when it sits above everything else on screen.
        final fill = selected
            ? mq.primary
            : states.pressed
            ? mq.surfaceActive
            : states.hovered
            ? mq.surfaceHover
            : Colors.transparent;
        final ink = !states.enabled && !selected
            ? mq.textDisabled
            : selected
            ? mq.onPrimary
            : states.active
            ? mq.textPrimary
            : mq.textSecondary;

        return AnimatedContainer(
          duration: states.duration,
          height: ComposerTabBar._pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MqIcon(spec.icon, size: 15, color: ink),
              const SizedBox(width: 7),
              Text(
                spec.label,
                style: TextStyle(
                  color: ink,
                  fontSize: MqTheme.fontLabel,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: MqTheme.trackSmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The provider's own quality value, said in words.
///
/// They are the same steps everywhere they exist, and they are prices as much
/// as looks -- a third of a cent against twenty on the same model and the same
/// frame. "Auto" is the API's own default on the models that have it: the
/// model picks the effort from the prompt.
String qualityLabel(String value) => switch (value) {
  'auto' => tr('Auto'),
  'low' => tr('Draft'),
  'medium' => tr('Standard'),
  'high' => tr('Best'),
  _ => value,
};

/// A shape, named where it has a name.
///
/// The three the app has always offered are what an ad is usually cut to, so
/// they keep their words. The other seven Gemini draws are just ratios, and
/// "4:5" is already the clearest thing anyone could write for 4:5.
String ratioLabel(String value) => switch (value) {
  '9:16' => tr('Vertical 9:16'),
  '1:1' => tr('Square 1:1'),
  '16:9' => tr('Wide 16:9'),
  _ => value,
};

/// A frame, as something readable.
///
/// The shorthand sizes -- "1K", "2K" -- are already readable and pass through.
/// The literal ones become "1536 x 1024 · landscape", with the shape named
/// after the numbers: "1024x1536" and "1536x1024" differ by two characters in
/// the middle, and picking the wrong one is a vertical ad shot in landscape.
String sizeLabel(String value) {
  if (value == 'auto') return tr('Auto');

  final parts = value.split('x');
  if (parts.length != 2) return value;

  final width = int.tryParse(parts[0]) ?? 0;
  final height = int.tryParse(parts[1]) ?? 0;
  if (width <= 0 || height <= 0) return value;

  final shape = width == height
      ? tr('square')
      : width > height
      ? tr('landscape')
      : tr('portrait');
  //: %1 and %2 are pixel counts, %3 is "square", "landscape" or "portrait"
  return tr('%1 x %2  ·  %3').arg(width).arg(height).arg(shape);
}
