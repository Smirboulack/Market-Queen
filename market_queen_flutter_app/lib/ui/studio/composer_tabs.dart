import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/translator.dart';
import '../../models/canvas_feed.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';

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
    this.takesReferences = true,
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

  final bool takesReferences;

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
      placeholder: tr('Write the script your actor will read...'),
      tall: true,
      picksAspect: true,
      picksLength: true,
    ),
    ComposerTab.video => ComposerSpec(
      label: tr('Video'),
      icon: 'clapperboard-line',
      category: 'video',
      kind: CanvasKind.video,
      placeholder: tr(
        'Describe the shot. Drop a picture in to use as its first frame.',
      ),
      batched: true,
      maxCount: 4,
      picksAspect: true,
      picksLength: true,
    ),
    ComposerTab.image => ComposerSpec(
      label: tr('Image'),
      icon: 'image-line',
      category: 'image',
      kind: CanvasKind.image,
      placeholder: tr('Describe the picture. Drop references in to guide it.'),
      batched: true,
      maxCount: 10,
      picksAspect: true,
    ),
    ComposerTab.audio => ComposerSpec(
      label: tr('Voice-over'),
      icon: 'volume-up-line',
      category: 'voice',
      kind: CanvasKind.audio,
      placeholder: tr('Write what should be said out loud...'),
      tall: true,
      takesReferences: false,
    ),
    ComposerTab.captions => ComposerSpec(
      label: tr('Subtitles'),
      icon: 'check-double-line',
      category: 'captions',
      kind: CanvasKind.video,
      placeholder: tr('Drop in a clip to subtitle it'),
      prompted: false,
      multipleReferences: false,
    ),
    ComposerTab.upscale => ComposerSpec(
      label: tr('Enlarge'),
      icon: 'gallery-line',
      category: 'upscale',
      kind: CanvasKind.image,
      placeholder: tr('Drop in a picture to enlarge it'),
      prompted: false,
      multipleReferences: false,
    ),
  };

  /// The three that get a pill of their own.
  static const List<ComposerTab> primary = [
    ComposerTab.actors,
    ComposerTab.video,
    ComposerTab.image,
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
class ComposerTabBar extends StatelessWidget {
  const ComposerTabBar({
    super.key,
    required this.current,
    required this.onPicked,
  });

  final ComposerTab current;
  final ValueChanged<ComposerTab> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final inMenu = ComposerSpec.secondary.contains(current);

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in ComposerSpec.primary) ...[
            _Pill(
              spec: ComposerSpec.of(tab),
              selected: tab == current,
              onTap: () => onPicked(tab),
            ),
            const SizedBox(width: 4),
          ],
          Builder(
            builder: (anchor) => _Pill(
              spec: inMenu
                  ? ComposerSpec.of(current)
                  : ComposerSpec(
                      label: tr('See more'),
                      icon: 'search-line',
                      category: '',
                      kind: CanvasKind.image,
                      placeholder: '',
                    ),
              selected: inMenu,
              onTap: () async {
                final picked = await showChipMenu<ComposerTab>(
                  anchor,
                  options: [
                    for (final tab in ComposerSpec.secondary)
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
        final ink = selected
            ? mq.onPrimary
            : states.active
            ? mq.textPrimary
            : mq.textSecondary;

        return AnimatedContainer(
          duration: states.duration,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radiusPill),
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

/// The column that appears to the right of the bar.
///
/// Everything here is a property of what will be generated rather than of what
/// is being written, which is why it is beside the bar and not in it -- and why
/// it is closed by default. A studio that opens onto twelve dropdowns is a
/// studio nobody writes anything in.
class ComposerSettings extends StatelessWidget {
  const ComposerSettings({
    super.key,
    required this.app,
    required this.tab,
    required this.onClose,
  });

  final AppState app;
  final ComposerTab tab;
  final VoidCallback onClose;

  ComposerSpec get spec => ComposerSpec.of(tab);

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  //: %1 is the name of a composer tab, e.g. "Video"
                  tr('%1 settings').arg(spec.label),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontBody,
                    fontWeight: FontWeight.w600,
                    letterSpacing: MqTheme.trackTitle,
                  ),
                ),
              ),
              MqIconButton(
                icon: 'close-line',
                tip: tr('Close'),
                size: 24,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: MqTheme.gap),
          ..._rows(context),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context) {
    final project = app.project;

    final rows = <Widget>[
      if (spec.category.isNotEmpty)
        _Row(
          label: tr('Model'),
          child: _ModelPicker(app: app, category: spec.category),
        ),
      if (spec.picksAspect)
        _Row(
          label: tr('Format'),
          child: _Pick(
            value: _aspect,
            options: [
              MenuOption(tr('Vertical 9:16'), '9:16'),
              MenuOption(tr('Square 1:1'), '1:1'),
              MenuOption(tr('Wide 16:9'), '16:9'),
            ],
            onPicked: (value) {
              if (tab == ComposerTab.actors) {
                project.setAspectRatio(value);
              } else {
                app.settings.setPref('${spec.category}Aspect', value);
              }
            },
          ),
        ),
    ];

    if (tab == ComposerTab.video) {
      rows.add(
        _Row(
          label: tr('Length'),
          child: _Pick(
            value: '$_videoSeconds',
            options: [
              MenuOption(tr('5 s'), '5'),
              MenuOption(tr('10 s'), '10'),
              MenuOption(tr('15 s'), '15'),
              MenuOption(tr('30 s'), '30'),
            ],
            onPicked: (value) =>
                app.settings.setPref('videoSeconds', int.tryParse(value) ?? 5),
          ),
        ),
      );
    }

    if (tab == ComposerTab.actors) {
      rows.addAll([
        _Row(
          label: tr('Max length'),
          child: _Pick(
            value: project.maxSeconds == 0 ? '' : '${project.maxSeconds}',
            options: [
              MenuOption(tr('As long as it takes'), ''),
              MenuOption(tr('15 s'), '15'),
              MenuOption(tr('20 s'), '20'),
              MenuOption(tr('30 s'), '30'),
              MenuOption(tr('45 s'), '45'),
              MenuOption(tr('60 s'), '60'),
            ],
            onPicked: (value) =>
                project.setMaxSeconds(int.tryParse(value) ?? 0),
          ),
        ),
        _Row(
          label: tr('Subtitles'),
          child: MqToggle(
            value: project.captions,
            onChanged: project.setCaptions,
          ),
        ),
        _Row(
          label: tr('Product shots'),
          child: MqToggle(
            value: project.broll,
            tooltip: project.broll
                ? tr('The lines about the product are filmed on the product, '
                    'with your voice over them.')
                : tr('Every line is filmed on the actor.'),
            onChanged: project.setBroll,
          ),
        ),
        _Row(
          label: tr('Cost'),
          child: _Estimate(app: app),
        ),
      ]);
    }

    // A settings column with one row in it looks broken; saying why is better
    // than an empty box.
    if (rows.isEmpty) {
      rows.add(
        Text(
          tr('Nothing to set here -- hand it a file and press send.'),
          style: TextStyle(
            color: context.mq.textTertiary,
            fontSize: MqTheme.fontSmall,
            height: MqTheme.lineBody,
          ),
        ),
      );
    }

    return rows;
  }

  String get _aspect {
    if (tab == ComposerTab.actors) return app.project.aspectRatio;
    final saved = app.settings.prefString('${spec.category}Aspect');
    return saved.isEmpty ? app.project.aspectRatio : saved;
  }

  int get _videoSeconds {
    final saved = app.settings.pref<int>('videoSeconds', 0) ?? 0;
    return saved < 1 ? 5 : saved;
  }
}

/// A label on the left, its control on the right, and a hairline under it.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          // The value is capped at a share of the row and the label takes
          // whatever is left, rather than the two splitting it in a fixed
          // ratio. Both other arrangements truncate something: give the label
          // the room and a model name comes out as "Kling AI Avatar v2 Stand…";
          // give the value the room and a 38px toggle sits beside "Plans pro…".
          // A cap plus the remainder is the only version where a short value
          // hands its space back.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mq.textSecondary,
                      fontSize: MqTheme.fontLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.62,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: mq.borderSubtle),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// The right-hand half of a settings row: the current value, and a chevron.
class _Pick extends StatelessWidget {
  const _Pick({
    required this.value,
    required this.options,
    required this.onPicked,
    this.display = '',
    this.menuWidth = 230,
  });

  final String value;
  final List<MenuOption<String>> options;
  final ValueChanged<String> onPicked;

  /// Shown in place of the picked option's own label, for the one row where
  /// they differ: the model menu carries a price next to every entry, which is
  /// what you want while choosing and pure noise afterwards -- and long enough
  /// to push the model's actual name out of the column.
  final String display;

  final double menuWidth;

  String get _label {
    if (display.isNotEmpty) return display;
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return options.isEmpty ? '' : options.first.label;
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Builder(
      builder: (anchor) => Pressable(
        onTap: () async {
          final picked = await showChipMenu<String>(
            anchor,
            options: options,
            current: value,
            width: menuWidth,
          );
          if (picked != null) onPicked(picked);
        },
        focusRadius: MqTheme.radiusSmall,
        builder: (context, states) => AnimatedContainer(
          duration: states.duration,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: states.active ? mq.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              MqIcon(
                'arrow-down-s-line',
                size: 15,
                color: states.active ? mq.textPrimary : mq.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Provider and model in one menu.
///
/// They used to be two dropdowns on a settings page. They are one line here
/// because nobody chooses a provider -- they choose a model, and the provider
/// is a fact about it. Only models the Models page has left switched on appear.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.app, required this.category});

  final AppState app;
  final String category;

  @override
  Widget build(BuildContext context) {
    final registry = app.registry;
    final settings = app.settings;

    final providers = registry.providers(category);
    final named = providers.length > 1;

    final options = <MenuOption<String>>[];
    for (final provider in providers) {
      for (final model in provider.models) {
        if (settings.modelHidden(provider.id, model.id)) continue;

        final price = Format.unitPriceLabel(app.pricing.unitPrice(model.id));
        final label = [
          if (named) '${provider.label} · ',
          model.label,
          if (price.isNotEmpty) '   $price',
        ].join();

        options.add(MenuOption(label, '${provider.id}|${model.id}'));
      }
    }

    if (options.isEmpty) {
      return Text(
        tr('None enabled'),
        style: TextStyle(
          color: context.mq.warningText,
          fontSize: MqTheme.fontLabel,
        ),
      );
    }

    final providerId = app.runner.providerFor(category);
    final saved = settings.prefString('${category}Model');
    final modelId = saved.isEmpty
        ? registry.provider(providerId)?.defaultModel ?? ''
        : saved;

    return _Pick(
      value: '$providerId|$modelId',
      options: options,
      // The name alone once it is chosen. Which provider it came from is a
      // detail the menu shows and the row does not need to repeat.
      display: registry.modelLabel(providerId, modelId),
      menuWidth: 340,
      onPicked: (value) {
        final parts = value.split('|');
        if (parts.length != 2) return;
        settings
          ..setPref('${category}Provider', parts[0])
          ..setPref('${category}Model', parts[1]);
      },
    );
  }
}

/// What the ad would cost if it were shot right now.
class _Estimate extends StatelessWidget {
  const _Estimate({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final breakdown = app.pricing.estimate(app.request());

    return Text(
      Format.estimated(breakdown.total),
      style: TextStyle(
        color: context.mq.textPrimary,
        fontSize: MqTheme.fontLabel,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
