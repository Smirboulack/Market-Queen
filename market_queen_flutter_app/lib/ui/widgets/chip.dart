import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// A pill. The one control this interface leans on.
///
/// It replaces the dropdowns, checkboxes and labelled fields the studio used to
/// stack: a chip is off until you touch it, shows its value once you do, and
/// takes exactly the room its own text needs. Ten of them read as a sentence;
/// ten dropdowns read as a form.
class MqChip extends StatelessWidget {
  const MqChip({
    super.key,
    this.label = '',
    this.value = '',
    this.detail = '',
    this.icon = '',
    this.portrait = '',
    this.opensMenu = false,
    this.accent = false,
    this.enabled = true,
    this.active,
    this.onPressed,
  });

  final String label;

  /// Set once chosen; the chip then shows this instead of the label.
  final String value;

  /// Shown *after* the label rather than in place of it -- for a chip that
  /// keeps its name and carries a figure, like an action and its price.
  final String detail;
  final String icon;

  /// A round thumbnail on the left -- used by the actor chip.
  final String portrait;
  final bool opensMenu;
  final bool accent;
  final bool enabled;
  final VoidCallback? onPressed;

  /// Lit or not. Left unset, a chip lights up as soon as it carries a value --
  /// which is what every chip but the voice presets wants.
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final lit = active ?? (value.isNotEmpty || detail.isNotEmpty);

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Pressable(
        enabled: enabled,
        onTap: onPressed,
        builder: (context, hovered, pressed) {
          final fill = accent
              ? mq.accent
              : lit
                  ? mq.accentSoft
                  : hovered
                      ? mq.surfaceHover
                      : Colors.transparent;
          final line = accent || lit
              ? mq.accent
              : hovered
                  ? mq.borderStrong
                  : mq.border;

          final foreground = accent
              ? Colors.white
              : lit
                  ? mq.text
                  : mq.textDim;

          return AnimatedContainer(
            duration: MqTheme.hoverDuration,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (portrait.isNotEmpty) ...[
                  ClipOval(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: File(portrait).existsSync()
                          ? Image.file(File(portrait), fit: BoxFit.cover)
                          : ColoredBox(color: mq.surfaceAlt),
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else if (icon.isNotEmpty) ...[
                  MqIcon(
                    icon,
                    size: 15,
                    color: accent
                        ? Colors.white
                        : lit
                            ? mq.accent
                            : mq.textFaint,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  value.isNotEmpty ? value : label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: MqTheme.fontSmall,
                    fontWeight:
                        lit || accent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    detail,
                    style: TextStyle(
                      color: accent
                          ? Colors.white.withValues(alpha: 0.75)
                          : mq.textFaint,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ],
                if (opensMenu) ...[
                  const SizedBox(width: 6),
                  MqIcon(
                    'arrow-down-s-line',
                    size: 14,
                    color: accent ? Colors.white : mq.textFaint,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class MenuOption<T> {
  const MenuOption(this.label, this.value);

  final String label;
  final T value;
}

/// A chip that opens its options underneath.
///
/// This is what the four stacked dropdowns became. Unset, it is a faint
/// "+ Age" taking twenty pixels; set, it says "35 years old" and lights up. The
/// options only exist while you are looking at them.
class MqChoiceChip extends StatelessWidget {
  const MqChoiceChip({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final List<MenuOption<String>> options;
  final String value;
  final ValueChanged<String> onPicked;

  String get _currentLabel {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MqChip(
      label: label,
      value: _currentLabel,
      icon: value.isEmpty ? 'add-line' : '',
      opensMenu: true,
      onPressed: () async {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;

        final origin = box.localToGlobal(Offset(0, box.size.height + 4),
            ancestor: overlay);

        final picked = await showMenu<String>(
          context: context,
          color: mq.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            side: BorderSide(color: mq.border),
          ),
          position: RelativeRect.fromLTRB(
            origin.dx,
            origin.dy,
            overlay.size.width - origin.dx - 190,
            0,
          ),
          items: [
            // "Doesn't matter" is an option, not the absence of one: taking a
            // trait back off has to be as easy as putting it on.
            for (final option in [
              MenuOption(tr("doesn't matter"), ''),
              ...options,
            ])
              PopupMenuItem<String>(
                value: option.value,
                height: 34,
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: option.value == value ? mq.accent : mq.text,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: option.value == value
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        );

        if (picked != null) onPicked(picked);
      },
    );
  }
}
