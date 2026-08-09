import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';

/// Tracks hover and press for the hand-drawn controls, and gives the pointer
/// cursor. One hover source per control, as the interaction spec requires.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.cursor = SystemMouseCursors.click,
    this.tooltip = '',
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final VoidCallback? onTap;
  final bool enabled;
  final MouseCursor cursor;
  final String tooltip;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;

    Widget child = MouseRegion(
      cursor: active ? widget.cursor : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => setState(() => _pressed = true) : null,
        onTapUp: active ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: active ? () => setState(() => _pressed = false) : null,
        onTap: active ? widget.onTap : null,
        child: widget.builder(context, _hovered && widget.enabled, _pressed),
      ),
    );

    if (widget.tooltip.isNotEmpty) {
      child = Tooltip(message: widget.tooltip, child: child);
    }
    return child;
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.loading = false,
    this.enabled = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final active = enabled && !loading && onPressed != null;

    return Pressable(
      enabled: active,
      onTap: onPressed,
      builder: (context, hovered, pressed) {
        final color = !active
            ? mq.surfaceAlt
            : pressed
                ? Color.lerp(mq.accent, Colors.black, 0.18)!
                : hovered
                    ? mq.accentHover
                    : mq.accent;

        return AnimatedContainer(
          duration: MqTheme.hoverDuration,
          height: 42,
          constraints: const BoxConstraints(minWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(MqTheme.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(mq.textFaint),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: TextStyle(
                  color: active ? Colors.white : mq.textFaint,
                  fontSize: MqTheme.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
      builder: (context, hovered, pressed) {
        // One authority for the visual state: hover and press land instantly,
        // only the way back to rest fades, and fill and border move together.
        final fill = pressed || checked ? mq.surfaceHover : Colors.transparent;
        final line = (pressed || hovered || checked) ? mq.borderStrong : mq.border;

        return AnimatedContainer(
          duration: MqTheme.hoverDuration,
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
              color: !active
                  ? mq.textFaint
                  : destructive
                      ? mq.danger
                      : mq.text,
              fontSize: MqTheme.fontSmall + 1,
            ),
          ),
        );
      },
    );
  }
}

/// A bare glyph that only exists on hover. Used for the per-scene controls,
/// where a row of labelled buttons would weigh more than the line it acts on.
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
      builder: (context, hovered, pressed) => Opacity(
        opacity: active ? 1.0 : 0.3,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? mq.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          ),
          child: MqIcon(
            icon,
            size: 16,
            color: destructive && hovered ? mq.danger : mq.textDim,
          ),
        ),
      ),
    );
  }
}
