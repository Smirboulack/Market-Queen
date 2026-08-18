import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../brand.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// What a model row says when its account has no key yet.
///
/// One string, read by every menu that lists models, so the sentence is the same
/// wherever you hit it.
String get lockedByKeyLabel => tr('Add the API key');

/// A pill. The one control this interface leans on.
///
/// It replaces the dropdowns, checkboxes and labelled fields the studio used to
/// stack: a chip is off until you touch it, shows its value once you do, and
/// takes exactly the room its own text needs. Ten of them read as a sentence;
/// ten dropdowns read as a form.
///
/// A chip that carries a value is *not* filled with pink -- ten set chips would
/// put more brand colour on screen than the Generate button. It goes one shade
/// up the grey ladder, and the pink appears only in its icon.
class MqChip extends StatelessWidget {
  const MqChip({
    super.key,
    this.label = '',
    this.value = '',
    this.detail = '',
    this.icon = '',
    this.portrait = '',
    this.leading,
    this.opensMenu = false,
    this.accent = false,
    this.enabled = true,
    this.active,
    this.tooltip = '',
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

  /// Anything else in the glyph slot, outranking [icon] and [portrait]. It
  /// exists for the one thing a glyph name cannot express: a spinner.
  final Widget? leading;

  final bool opensMenu;

  /// The one chip on screen that is really a call to action.
  final bool accent;
  final bool enabled;
  final VoidCallback? onPressed;

  /// Lit or not. Left unset, a chip lights up as soon as it carries a value --
  /// which is what every chip but the voice presets wants.
  final bool? active;

  /// For a chip whose two states are not self-evident from its label.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final lit = active ?? (value.isNotEmpty || detail.isNotEmpty);

    return Pressable(
      enabled: enabled,
      onTap: onPressed,
      tooltip: tooltip,
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) {
        final Color fill;
        final Color line;
        final Color ink;
        final Color glyph;

        if (!states.enabled) {
          fill = Colors.transparent;
          line = mq.borderSubtle;
          ink = mq.textDisabled;
          glyph = mq.textDisabled;
        } else if (accent) {
          fill = states.pressed
              ? mq.primaryActive
              : states.hovered
              ? mq.primaryHover
              : mq.primary;
          line = fill;
          ink = mq.onPrimary;
          glyph = mq.onPrimary;
        } else {
          fill = states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : lit
              ? mq.surfaceSecondary
              : Colors.transparent;
          line = (states.active || lit) ? mq.borderStrong : mq.border;
          ink = lit ? mq.textPrimary : mq.textSecondary;
          // The chip's whole allowance of brand colour.
          glyph = lit ? mq.primary : mq.textTertiary;
        }

        return AnimatedContainer(
          duration: states.duration,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radiusPill),
            border: Border.all(color: line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (portrait.isNotEmpty) ...[
                ClipOval(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: File(portrait).existsSync()
                        ? Image.file(File(portrait), fit: BoxFit.cover)
                        : ColoredBox(color: mq.surfaceTertiary),
                  ),
                ),
                const SizedBox(width: 6),
              ] else if (icon.isNotEmpty) ...[
                MqIcon(icon, size: 15, color: glyph),
                const SizedBox(width: 6),
              ],
              // Flexible: a chip carrying a model name is at the mercy of
              // whatever the provider called it, and one long enough to
              // overflow its row must give in before the row does.
              Flexible(
                child: Text(
                  value.isNotEmpty ? value : label,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: ink,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: lit || accent
                        ? FontWeight.w500
                        : FontWeight.w400,
                    letterSpacing: MqTheme.trackSmall,
                  ),
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  detail,
                  style: TextStyle(
                    color: accent
                        ? mq.onPrimary.withValues(alpha: 0.7)
                        : mq.textTertiary,
                    fontSize: MqTheme.fontLabel,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (opensMenu) ...[
                const SizedBox(width: 5),
                MqIcon(
                  'arrow-down-s-line',
                  size: 14,
                  color: accent ? mq.onPrimary : mq.textTertiary,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class MenuOption<T> {
  const MenuOption(
    this.label,
    this.value, {
    this.mark = '',
    this.locked = false,
    this.note = '',
  });

  final String label;
  final T value;

  /// A credential id, for the menus whose entries belong to an account: the
  /// model list is a hundred names off fifteen shelves, and the mark is what
  /// tells you which shelf you are looking at without reading the prefix.
  /// Empty everywhere else, and the menu then has no glyph column at all.
  final String mark;

  /// Set on an entry the user cannot have yet -- a model on an account with no
  /// key.
  ///
  /// Locked rather than hidden, and that is the whole point: a menu that quietly
  /// omits Veo because there is no Google key is a menu that says the app cannot
  /// do Veo. The row stays, greyed, saying what is missing, and pressing it is
  /// how you fix it.
  final bool locked;

  /// The grey line at the right of the row, saying why it is locked.
  final String note;
}

/// The entry's own label inside a menu row.
///
/// Keyed because it is no longer the only text in the row: an account with no
/// logo dropped in draws its initials beside the name, and anything looking for
/// "the label of this menu entry" would otherwise find the two letters first.
const Key chipMenuLabelKey = ValueKey('mq.chipMenu.label');

/// Opens [options] under [anchor] and returns what was picked.
///
/// One implementation for every chip menu in the app, so they cannot drift
/// apart in width, offset or how the current value is marked.
///
/// [onLocked] is how a menu offers something the user cannot have yet. A locked
/// row is drawn greyed with its note beside it, and picking one calls this
/// instead of returning: hand it a dialog that removes the obstacle -- for a
/// model, the account's API key -- and return whether it worked. True and the
/// option is returned as though it had been picked normally, which is what the
/// user was trying to do in the first place; false and the menu closes having
/// changed nothing. Without it, a locked row is simply inert.
Future<T?> showChipMenu<T>(
  BuildContext anchor, {
  required List<MenuOption<T>> options,
  required T current,
  double width = 220,
  Future<bool> Function(MenuOption<T> option)? onLocked,
}) async {
  final mq = anchor.mq;
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return null;

  final origin = box.localToGlobal(
    Offset(0, box.size.height + 4),
    ancestor: overlay,
  );
  final left = origin.dx.clamp(0.0, overlay.size.width - width);

  // Shape, colour and elevation come from `popupMenuTheme`.
  final picked = await showMenu<T>(
    context: anchor,
    constraints: BoxConstraints(minWidth: width, maxHeight: 360),
    position: RelativeRect.fromLTRB(
      left,
      origin.dy,
      overlay.size.width - left - width,
      0,
    ),
    items: [
      for (final option in options)
        PopupMenuItem<T>(
          value: option.value,
          height: 34,
          // Still selectable: `enabled: false` would make the row unpressable,
          // and pressing it is the way to unlock it. The grey is the whole of
          // the "not yet".
          child: Row(
            children: [
              if (option.mark.isNotEmpty) ...[
                // Dimmed with the row it belongs to, so a page of locked
                // accounts does not read as a page of live ones.
                Opacity(
                  opacity: option.locked ? 0.45 : 1,
                  child: ProviderMark(credential: option.mark, size: 18),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(
                  option.label,
                  key: chipMenuLabelKey,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: option.locked
                        ? mq.textDisabled
                        : option.value == current
                        ? mq.primaryText
                        : mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: option.value == current && !option.locked
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (option.locked && option.note.isNotEmpty) ...[
                const SizedBox(width: 10),
                MqIcon('key-line', size: 12, color: mq.warningText),
                const SizedBox(width: 4),
                Text(
                  option.note,
                  style: TextStyle(
                    color: mq.warningText,
                    fontSize: MqTheme.fontMicro,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
    ],
  );

  if (picked == null) return null;

  for (final option in options) {
    if (option.value != picked || !option.locked) continue;
    // A locked row was pressed. Nothing is chosen unless whatever [onLocked]
    // asks for actually arrives.
    if (onLocked == null) return null;
    return await onLocked(option) ? picked : null;
  }
  return picked;
}

/// A chip that opens a fixed list of options, all of them real.
///
/// Unlike [MqChoiceChip] there is no "doesn't matter" entry: this is for the
/// settings that always have a value -- the shape of the video, the ceiling on
/// its length -- where an empty choice would mean nothing.
class MqPickChip extends StatelessWidget {
  const MqPickChip({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onPicked,
    this.icon = '',
    this.menuWidth = 220,
    this.compact = false,
    this.onLocked,
  });

  final String label;
  final List<MenuOption<String>> options;
  final String value;
  final ValueChanged<String> onPicked;
  final String icon;
  final double menuWidth;

  /// What to do when a locked row is pressed -- see [showChipMenu]. Set on the
  /// chips whose entries belong to an account, so hitting the wall opens the
  /// key dialog instead of doing nothing.
  final Future<bool> Function(MenuOption<String> option)? onLocked;

  /// Carry the value alone and let the glyph name the field.
  ///
  /// For a row of chips that is read as one sentence -- a casting brief, where
  /// five of them have to fit on one line. "Language · Same as the ad" three
  /// times over is the field names taking two thirds of the room to say what
  /// the icons already say, and it is the *values* somebody is scanning. The
  /// name is still there on hover, and the empty option carries its own words
  /// ("Any age") so an unset chip is never a mystery.
  ///
  /// Off by default: everywhere a chip stands on its own, the name is the only
  /// thing that says what it is.
  final bool compact;

  String get _currentLabel {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentLabel;

    return Builder(
      builder: (anchor) => MqChip(
        label: compact
            ? (current.isEmpty ? label : current)
            //: %1 is a setting's name, %2 the value it currently holds
            : current.isEmpty
            ? label
            : tr('%1 · %2').arg(label).arg(current),
        icon: icon,
        opensMenu: true,
        active: current.isNotEmpty,
        tooltip: compact ? label : '',
        onPressed: () async {
          final picked = await showChipMenu<String>(
            anchor,
            options: options,
            current: value,
            width: menuWidth,
            onLocked: onLocked,
          );
          if (picked != null) onPicked(picked);
        },
      ),
    );
  }
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

        final origin = box.localToGlobal(
          Offset(0, box.size.height + 4),
          ancestor: overlay,
        );

        // Shape, colour and elevation come from `popupMenuTheme`.
        final picked = await showMenu<String>(
          context: context,
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
                    color: option.value == value
                        ? mq.primaryText
                        : mq.textPrimary,
                    fontSize: MqTheme.fontLabel,
                    fontWeight: option.value == value
                        ? FontWeight.w600
                        : FontWeight.w400,
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
