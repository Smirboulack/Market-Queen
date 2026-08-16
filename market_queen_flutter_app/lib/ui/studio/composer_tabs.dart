import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../../models/asset_library.dart' show MediaKind;
import '../../models/canvas_feed.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';

/// The six things the composer can be asked for.
///
/// Three of them are on the bar; the other three live behind "See more",
/// because they are what you reach for once something already exists in the
/// canvas rather than what you open the studio to do.
enum ComposerTab { actors, video, image, audio, captions, upscale }

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
        'files by name: @Marie, @Image1, @Video1.',
      ),
      tall: true,
      // The product, as a photo or a clip of it in use. This is the only mode
      // where the cast is addressable, because it is the only mode that has a
      // cast: the avatar model is handed the actor and the scene, and the other
      // two shelves have never heard of either.
      referenceKinds: const {MediaKind.image, MediaKind.video},
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
    ComposerTab.audio => ComposerSpec(
      label: tr('Voice-over'),
      icon: 'volume-up-line',
      category: 'voice',
      kind: CanvasKind.audio,
      placeholder: tr('Write what should be said out loud...'),
      tall: true,
      referenceKinds: const {},
    ),
    ComposerTab.captions => ComposerSpec(
      label: tr('Subtitles'),
      icon: 'check-double-line',
      category: 'captions',
      kind: CanvasKind.video,
      placeholder: tr('Drop in a clip to subtitle it'),
      prompted: false,
      referenceKinds: const {MediaKind.video},
      multipleReferences: false,
    ),
    ComposerTab.upscale => ComposerSpec(
      label: tr('Enlarge'),
      icon: 'gallery-line',
      category: 'upscale',
      kind: CanvasKind.image,
      placeholder: tr('Drop in a picture to enlarge it'),
      prompted: false,
      referenceKinds: const {MediaKind.image},
      multipleReferences: false,
    ),
  };

  /// The three that get a pill of their own, in the order they are reached
  /// for: the actor and the stills come first, and video last, because video is
  /// what you shoot once everything else is settled -- and the most expensive
  /// thing to shoot twice.
  static const List<ComposerTab> primary = [
    ComposerTab.actors,
    ComposerTab.image,
    ComposerTab.video,
  ];

  static const List<ComposerTab> secondary = [
    ComposerTab.audio,
    ComposerTab.captions,
    ComposerTab.upscale,
  ];
}

/// The row of pills above the bar.
///
/// It is a separate object from the bar on purpose -- a frame floating over the
/// canvas rather than a strip inside the input -- so that what you are making
/// reads as a choice you have already made, and the bar underneath is only
/// about what you are saying.
///
/// "See more" adds rather than replaces. It used to *become* the mode you
/// picked out of it, which meant the way back into the menu was the thing you
/// had just taken out of it: choosing Subtitles hid Voice-over and Enlarge
/// behind a pill that no longer said "See more". Now the picked mode arrives as
/// a pill of its own, with a cross to put it away again, and the menu stays
/// where it was.
class ComposerTabBar extends StatelessWidget {
  const ComposerTabBar({
    super.key,
    required this.current,
    required this.extras,
    required this.onPicked,
    required this.onRemoved,
  });

  final ComposerTab current;

  /// The advanced modes pulled out of the menu, in the order they were added.
  final List<ComposerTab> extras;

  final ValueChanged<ComposerTab> onPicked;
  final ValueChanged<ComposerTab> onRemoved;

  static const double _pillHeight = 34;
  static const double _framePadding = 5;

  /// Half the height of a single row of pills. That makes the frame a stadium
  /// while everything is on one line -- which is what it always was -- and a
  /// rounded rectangle the moment it needs two, instead of a stadium whose
  /// curve cuts through the pills at either end.
  static const double _frameRadius = _pillHeight / 10 + _framePadding;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final remaining = [
      for (final tab in ComposerSpec.secondary)
        if (!extras.contains(tab)) tab,
    ];

    return Container(
      padding: const EdgeInsets.all(_framePadding),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(_frameRadius),
        border: Border.all(color: mq.border),
      ),
      // Wrapped, not a row: with all three advanced modes out on the bar the
      // pills are wider than the bar underneath them, and the frame is anchored
      // to the bottom of the page, so a second line grows upward into empty
      // background rather than pushing anything around.
      // Anchored left, because the frame is now at the left end of a row it
      // shares with the settings rather than centred over the bar on its own.
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
          for (final tab in extras)
            _Pill(
              spec: ComposerSpec.of(tab),
              selected: tab == current,
              onTap: () => onPicked(tab),
              onRemove: () => onRemoved(tab),
            ),
          Builder(
            builder: (anchor) => _Pill(
              spec: ComposerSpec(
                label: tr('See more'),
                icon: 'search-line',
                category: '',
                kind: CanvasKind.image,
                placeholder: '',
              ),
              selected: false,
              // Everything is already out on the bar; the menu behind it would
              // be empty.
              enabled: remaining.isNotEmpty,
              onTap: () async {
                final picked = await showChipMenu<ComposerTab>(
                  anchor,
                  options: [
                    for (final tab in remaining)
                      MenuOption(ComposerSpec.of(tab).label, tab),
                  ],
                  current: current,
                  width: 200,
                );
                if (picked != null) onPicked(picked);
              },
            ),
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
    this.onRemove,
    this.enabled = true,
  });

  final ComposerSpec spec;
  final bool selected;
  final VoidCallback onTap;

  /// Set on the advanced pills, which can be put away again.
  final VoidCallback? onRemove;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      enabled: enabled,
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
          padding: EdgeInsets.only(left: 14, right: onRemove == null ? 14 : 6),
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
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                _PillClose(ink: ink, onTap: onRemove!),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The cross on an advanced pill.
///
/// Its own target inside the pill rather than a second meaning for it: pressing
/// the pill always switches to that mode, which is what you do twenty times to
/// the once you put it away.
class _PillClose extends StatelessWidget {
  const _PillClose({required this.ink, required this.onTap});

  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      tooltip: tr('Put this one away'),
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.active
              ? ink.withValues(alpha: 0.16)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: MqIcon('close-line', size: 13, color: ink),
      ),
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
