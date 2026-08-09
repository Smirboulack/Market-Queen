import 'dart:async';

import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';

/// Everything a control needs to know about the pointer and the keyboard.
///
/// Handed to every [Pressable] builder so that no control has to track its own
/// booleans, and -- more to the point -- so that no control can decide on its
/// own how fast a state change should be.
@immutable
class MqStates {
  const MqStates({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.enabled = true,
    this.snap = false,
  });

  /// The pointer is over the control. Never true while it is disabled.
  final bool hovered;

  /// The primary button is down on it, or the keyboard just activated it.
  final bool pressed;

  /// Focused *and* reached by keyboard. Clicking a control focuses it without
  /// lighting the ring, which is what stops a desktop app from looking like it
  /// is covered in outlines after every click.
  final bool focused;

  final bool enabled;

  /// Set on controls that touch their neighbours.
  ///
  /// It no longer changes the timing -- every control snaps now -- but it still
  /// marks the grouped rows, so it is kept rather than swept out of forty call
  /// sites.
  final bool snap;

  /// Lit: the pointer is on it or holding it down.
  bool get active => hovered || pressed;

  /// How long a visual change should take: no time at all, in either direction.
  ///
  /// A control has exactly three looks -- at rest, under the pointer, held down
  /// -- and it is in exactly one of them at any instant. Fading back to rest
  /// used to leave a tint trailing behind the pointer for 120ms, which reads as
  /// a fourth, ghost state on the control you have just left.
  Duration get duration => Duration.zero;
}

/// The one place hover, press and focus are tracked.
///
/// Every clickable thing in the app is built on this, which is what makes the
/// behaviour uniform: the same three states, the same pointer cursor, the same
/// focus ring, and the same guarantee that a control which stops being clickable
/// -- mid-press, mid-hover -- goes dark instead of staying lit forever.
///
/// It is keyboard-operable for free. Tab reaches it, Enter and Space fire it,
/// and the ring only appears when the focus actually arrived from the keyboard.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.cursor = SystemMouseCursors.click,
    this.tooltip = '',
    this.snap = false,
    this.focusRadius = MqTheme.radiusSmall,
    this.canRequestFocus = true,
  });

  final Widget Function(BuildContext context, MqStates states) builder;
  final VoidCallback? onTap;
  final bool enabled;
  final MouseCursor cursor;
  final String tooltip;

  /// For controls that sit against their neighbours: hover snaps both ways.
  final bool snap;

  /// Corner radius of the focus ring. Should match the control's own.
  final double focusRadius;

  /// Off for controls whose parent already takes the focus, so Tab does not
  /// stop twice in the same place.
  final bool canRequestFocus;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  /// Raw pointer presence, tracked whether or not the control is currently
  /// clickable.
  ///
  /// Enabledness is applied when the state is handed out, not when it is
  /// recorded, and that is the whole trick: a button that becomes live under a
  /// stationary pointer gets no enter event, because the pointer did not move.
  /// The only way it can light up is to have been watching all along. The same
  /// bookkeeping covers the other direction -- a Cancel that finishes under the
  /// cursor goes dark without waiting for an exit that is never coming.
  bool _pointerInside = false;
  bool _pressed = false;
  bool _focused = false;

  /// Whether the focus this control currently holds arrived from a click.
  ///
  /// Clicking a button focuses it, and on a desktop the focus manager calls that
  /// a "traditional" highlight and asks for the ring -- so every button you
  /// pressed kept a pink outline after the pointer had gone, which is the fourth
  /// state this widget is not supposed to have. The ring is for keyboard
  /// navigation; a pointer press suppresses it until focus leaves and comes back
  /// some other way.
  bool _focusFromPointer = false;

  /// Keeps the flash from a keyboard activation on screen long enough to see.
  Timer? _flash;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active && _pressed) _pressed = false;
  }

  @override
  void dispose() {
    _flash?.cancel();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  /// Enter and Space. The press state is flashed by hand because there is no
  /// pointer to release it.
  void _activate() {
    if (!_active) return;
    // Reached from the keyboard, so the ring is wanted again.
    _focusFromPointer = false;
    _flash?.cancel();
    _setPressed(true);
    _flash = Timer(const Duration(milliseconds: 110), () => _setPressed(false));
    widget.onTap!.call();
  }

  @override
  Widget build(BuildContext context) {
    final states = MqStates(
      hovered: _pointerInside && _active,
      pressed: _pressed && _active,
      focused: _focused && _active,
      enabled: _active,
      snap: widget.snap,
    );

    Widget child = widget.builder(context, states);

    // Drawn here rather than by each control, so none of them can forget it.
    if (states.focused) {
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.focusRadius),
          border: Border.all(color: context.mq.focusRing, width: 2),
        ),
        child: child,
      );
    }

    child = FocusableActionDetector(
      enabled: _active,
      // Descendants stay focusable on purpose: a library card is a target and
      // so is the "Show file" underneath it, and Tab has to reach both.
      mouseCursor: _active ? widget.cursor : MouseCursor.defer,
      // Only the *focus* ring goes through the highlight policy -- that is what
      // the policy is for, and why a click does not leave an outline behind.
      // Hover deliberately does not: `onShowHoverHighlight` is suppressed
      // whenever the focus manager believes the last input was a touch, which
      // would leave a mouse pointer moving over a dead interface.
      onShowFocusHighlight: (value) {
        if (!mounted) return;
        // Focus leaving clears the suppression, so tabbing back to this control
        // lights the ring as it should.
        if (!value) _focusFromPointer = false;
        final next = value && !_focusFromPointer;
        if (_focused == next) return;
        setState(() => _focused = next);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) {
          if (_pointerInside || !mounted) return;
          setState(() => _pointerInside = true);
        },
        onExit: (_) {
          if (!_pointerInside || !mounted) return;
          setState(() {
            _pointerInside = false;
            // Releasing outside the control cancels the tap, but the pointer
            // can also leave while it is still down.
            _pressed = false;
          });
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _active
              ? (_) {
                  _focusFromPointer = true;
                  if (_focused) setState(() => _focused = false);
                  _setPressed(true);
                }
              : null,
          onTapUp: _active ? (_) => _setPressed(false) : null,
          onTapCancel: _active ? () => _setPressed(false) : null,
          onTap: _active ? widget.onTap : null,
          child: child,
        ),
      ),
    );

    if (!widget.canRequestFocus) {
      child = ExcludeFocus(child: child);
    }
    if (widget.tooltip.isNotEmpty) {
      child = Tooltip(message: widget.tooltip, child: child);
    }
    return child;
  }
}

/// The one thing on the page you are meant to press. Pink, and the only large
/// area of it anywhere.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.loading = false,
    this.enabled = true,
    this.icon = '',
    this.tooltip = '',
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final bool enabled;

  /// A glyph before the label. Reserved for the button that starts the run.
  final String icon;

  /// Mostly for the disabled state: a button that cannot be pressed should say
  /// what would make it pressable.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final active = enabled && !loading && onPressed != null;

    return Pressable(
      enabled: active,
      onTap: onPressed,
      tooltip: tooltip,
      focusRadius: MqTheme.radius,
      builder: (context, states) {
        final fill = !states.enabled
            ? mq.surfaceSecondary
            : states.pressed
            ? mq.primaryActive
            : states.hovered
            ? mq.primaryHover
            : mq.primary;
        final ink = states.enabled ? mq.onPrimary : mq.textDisabled;

        return AnimatedContainer(
          duration: states.duration,
          height: 42,
          constraints: const BoxConstraints(minWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(color: states.enabled ? fill : mq.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(mq.textDisabled),
                  ),
                ),
                const SizedBox(width: 9),
              ] else if (icon.isNotEmpty) ...[
                MqIcon(icon, size: 16, color: ink),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: TextStyle(
                  color: ink,
                  fontSize: MqTheme.fontBody,
                  fontWeight: FontWeight.w600,
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

/// The secondary action. Outlined at rest, filled on hover -- fill and border
/// always moving together.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.text,
    this.onPressed,
    this.destructive = false,
    this.enabled = true,
    this.checked = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool enabled;

  /// For the two-state ghosts (Show / Hide on a key field).
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final active = enabled && onPressed != null;

    return Pressable(
      enabled: active,
      onTap: onPressed,
      builder: (context, states) {
        final (Color fill, Color line) = switch (states) {
          MqStates(enabled: false) => (Colors.transparent, mq.borderSubtle),
          MqStates(pressed: true) when destructive => (
            mq.errorSubtle,
            mq.error,
          ),
          MqStates(pressed: true) => (mq.surfaceActive, mq.borderStrong),
          MqStates(hovered: true) when destructive => (
            mq.errorSubtle,
            mq.error,
          ),
          MqStates(hovered: true) => (mq.surfaceHover, mq.borderStrong),
          _ when checked => (mq.surfaceActive, mq.borderStrong),
          _ => (Colors.transparent, mq.border),
        };

        return AnimatedContainer(
          duration: states.duration,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(color: line),
          ),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: !states.enabled
                  ? mq.textDisabled
                  : destructive
                  ? mq.errorText
                  : mq.textPrimary,
              fontSize: MqTheme.fontLabel,
              fontWeight: FontWeight.w500,
              letterSpacing: MqTheme.trackSmall,
            ),
          ),
        );
      },
    );
  }
}

/// A bare glyph. Used for the per-scene controls, where a row of labelled
/// buttons would weigh more than the line it acts on.
class MqIconButton extends StatelessWidget {
  const MqIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tip = '',
    this.destructive = false,
    this.enabled = true,
    this.size = 26,
  });

  final String icon;
  final VoidCallback? onPressed;
  final String tip;
  final bool destructive;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final active = enabled && onPressed != null;

    return Pressable(
      enabled: active,
      onTap: onPressed,
      tooltip: tip,
      builder: (context, states) {
        final fill = states.pressed
            ? mq.surfaceActive
            : states.hovered
            ? mq.surfaceHover
            : Colors.transparent;

        final ink = !states.enabled
            ? mq.textDisabled
            : destructive && states.active
            ? mq.error
            : states.active
            ? mq.textPrimary
            : mq.textTertiary;

        return AnimatedContainer(
          duration: states.duration,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          ),
          child: MqIcon(icon, size: size * 0.6, color: ink),
        );
      },
    );
  }
}

/// An action that reads as a sentence rather than a control: "Show file",
/// "Fine-tune", "Use my photo".
///
/// Underlined on hover instead of merely recoloured. A pink that only shifts
/// hue is not a state change you can see out of the corner of your eye, and
/// these sit in the middle of paragraphs of grey text.
class MqLink extends StatelessWidget {
  const MqLink({
    super.key,
    required this.text,
    this.onPressed,
    this.destructive = false,
    this.fontSize = MqTheme.fontSmall,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool destructive;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onPressed,
      focusRadius: 3,
      builder: (context, states) => Padding(
        // Room for the underline and the focus ring without moving the text.
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text(
          text,
          style: TextStyle(
            color: !states.enabled
                ? mq.textDisabled
                : destructive
                ? mq.errorText
                : mq.primaryText,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            decoration: states.active
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: destructive ? mq.errorText : mq.primaryText,
          ),
        ),
      ),
    );
  }
}
