import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// The one input shape this app uses now: a field that grows, a row of chips
/// under it, and a send button.
///
/// Everything the old panels asked for in labelled fields is either typed here
/// or carried by a chip. The chips sit inside the bar rather than above it so
/// the whole thing reads as one object you are addressing, which is what makes
/// it a prompt bar and not a form with a border.
class PromptBar extends StatefulWidget {
  const PromptBar({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.placeholder = '',
    this.minHeight = 44,
    this.maxHeight = 160,
    this.busy = false,
    this.submitIcon = 'send-plane-fill',
    this.onChanged,
    this.chips = const [],
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final String placeholder;
  final double minHeight;
  final double maxHeight;
  final bool busy;
  final String submitIcon;
  final ValueChanged<String>? onChanged;
  final List<Widget> chips;

  @override
  State<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends State<PromptBar>
    with SingleTickerProviderStateMixin {
  final FocusNode _focus = FocusNode();
  late final AnimationController _spinner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_onText);
    if (widget.busy) _spinner.repeat();
  }

  @override
  void didUpdateWidget(PromptBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (widget.busy && !_spinner.isAnimating) {
      _spinner.repeat();
    } else if (!widget.busy && _spinner.isAnimating) {
      _spinner
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    _spinner.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  bool get _canSubmit => widget.controller.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit || widget.busy) return;
    widget.onSubmitted(widget.controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: _focus.hasFocus || _hovered
            ? Duration.zero
            : MqTheme.hoverDuration,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mq.surfaceSecondary,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(
            color: _focus.hasFocus
                ? mq.primary
                : _hovered
                ? mq.borderStrong
                : mq.border,
          ),
          // The bar is the thing you are addressing; when the caret is in it,
          // it should be unmistakably the live object on the page.
          boxShadow: _focus.hasFocus
              ? [
                  BoxShadow(
                    color: mq.focusRing.withValues(alpha: 0.22),
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.minHeight,
                maxHeight: widget.maxHeight,
              ),
              // Enter sends, Shift+Enter breaks the line. That is the contract
              // every chat input has taught people, and it is the reason this
              // needs no "add" button.
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): _SubmitIntent(),
                  SingleActivator(LogicalKeyboardKey.numpadEnter):
                      _SubmitIntent(),
                },
                child: Actions(
                  actions: {
                    _SubmitIntent: CallbackAction<_SubmitIntent>(
                      onInvoke: (_) {
                        _submit();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    maxLines: null,
                    onChanged: widget.onChanged,
                    cursorColor: mq.primary,
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontBody,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: widget.placeholder,
                      hintStyle: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontBody,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.chips,
                  ),
                ),
                const SizedBox(width: 6),
                _SendButton(
                  enabled: _canSubmit && !widget.busy,
                  busy: widget.busy,
                  icon: widget.submitIcon,
                  spinner: _spinner,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.busy,
    required this.icon,
    required this.spinner,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final String icon;
  final AnimationController spinner;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: enabled,
      onTap: onPressed,
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) {
        // Empty bar, nothing to send: the button reads as part of the frame
        // rather than a dimmed pink disc.
        final fill = !states.enabled
            ? mq.surfaceTertiary
            : states.pressed
            ? mq.primaryActive
            : states.hovered
            ? mq.primaryHover
            : mq.primary;
        final ink = states.enabled ? mq.onPrimary : mq.textDisabled;

        return AnimatedContainer(
          duration: states.duration,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: busy
              ? RotationTransition(
                  turns: spinner,
                  child: MqIcon('loader-4-line', size: 16, color: ink),
                )
              : MqIcon(icon, size: 16, color: ink),
        );
      },
    );
  }
}
