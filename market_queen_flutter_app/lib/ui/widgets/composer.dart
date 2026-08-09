import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';
import 'chip.dart';
import 'script_line.dart';

/// One of the three things the model can do to a line you have already typed.
class RewriteAction {
  const RewriteAction(this.id, this.label, this.icon, this.instruction);

  final String id;
  final String label;
  final String icon;

  /// What the model is actually told. Kept next to the label so the button and
  /// the prompt cannot say different things.
  final String instruction;

  static List<RewriteAction> get all => [
    RewriteAction(
      'enhance',
      tr('Enhance with AI'),
      'magic-line',
      'Rewrite this line so it lands harder, without inventing any claim that '
          'is not already in it. Keep it roughly the same length.',
    ),
    RewriteAction(
      'shorten',
      tr('Shorten'),
      'text-shorten',
      'Cut this line to the shortest version that still says the same thing. '
          'Aim for at most twelve words.',
    ),
    RewriteAction(
      'punchier',
      tr('Make punchier'),
      'flashlight-line',
      'Rewrite this line with more bite: stronger verbs, no hedging, no filler '
          'words. Same meaning, same length or shorter.',
    ),
  ];
}

/// The bar you write in.
///
/// A tab for the beat, a field, and the three things worth doing to a sentence
/// before it is committed. It floats over the foot of the script sheet because
/// it belongs to the sheet -- what you type here becomes the next line up there,
/// and the two should read as one object rather than as a form under a list.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.beat,
    required this.onBeatPicked,
    required this.onSubmitted,
    required this.onAction,
    required this.onClose,
    this.busyAction = '',
    this.error = '',
    this.canAct = true,
  });

  final TextEditingController controller;

  /// Owned by the workspace, so "New scene" can put the caret in here.
  final FocusNode focusNode;

  /// The beat the next line will play, or empty for none.
  final String beat;
  final ValueChanged<String> onBeatPicked;
  final ValueChanged<String> onSubmitted;

  /// Fired with a [RewriteAction] id.
  final ValueChanged<RewriteAction> onAction;
  final VoidCallback onClose;

  /// Which rewrite is in flight, so only that button spins.
  final String busyAction;
  final String error;

  /// False while a rewrite is running: two at once would race for the field.
  final bool canAct;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onText() => setState(() {});

  void _onFocus() => setState(() {});

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  void _submit() {
    if (!_hasText || !widget.canAct) return;
    widget.onSubmitted(widget.controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final beats = Beat.all;
    final placeholder =
        Beat.find(widget.beat)?.placeholder ??
        tr('Write the next line. One line, one scene.');

    return Container(
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
        border: Border.all(
          color: widget.focusNode.hasFocus ? mq.primary : mq.border,
        ),
        // The one place in the app that casts a shadow, because it is the one
        // thing that genuinely floats above something else.
        boxShadow: [
          BoxShadow(
            color: mq.dark ? const Color(0x8C000000) : const Color(0x14000000),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final beat in beats)
                        _BeatTab(
                          label: beat.label,
                          selected: widget.beat == beat.id,
                          // Picking the tab you are already on takes the beat
                          // back off, which is the only way to write a line
                          // that plays none.
                          onTap: () => widget.onBeatPicked(
                            widget.beat == beat.id ? '' : beat.id,
                          ),
                        ),
                      _MoreTab(onPicked: widget.onBeatPicked),
                    ],
                  ),
                ),
                MqIconButton(
                  icon: 'close-line',
                  tip: tr('Hide the composer'),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Container(height: 1, color: mq.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52, maxHeight: 132),
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
                    focusNode: widget.focusNode,
                    maxLines: null,
                    cursorColor: mq.primary,
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontBody,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: placeholder,
                      hintStyle: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontBody,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                widget.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mq.error, fontSize: MqTheme.fontSmall),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final action in RewriteAction.all)
                        MqChip(
                          label: action.label,
                          icon: action.icon,
                          leading: widget.busyAction == action.id
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      mq.primary,
                                    ),
                                  ),
                                )
                              : null,
                          // A rewrite with nothing to rewrite is not an action.
                          enabled: _hasText && widget.canAct,
                          onPressed: () => widget.onAction(action),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tr('Enter'),
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(
                  enabled: _hasText && widget.canAct,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BeatTab extends StatelessWidget {
  const _BeatTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // Tabs touch each other: hover snaps both ways so sliding along the strip
      // never lights two.
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? mq.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? mq.primaryText
                : states.active
                ? mq.textPrimary
                : mq.textSecondary,
            fontSize: MqTheme.fontLabel,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// The overflow tab. It carries the beats that did not fit and the way back to
/// writing a line that plays none.
class _MoreTab extends StatelessWidget {
  const _MoreTab({required this.onPicked});

  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      onTap: () async {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;

        final origin = box.localToGlobal(
          Offset(0, box.size.height + 4),
          ancestor: overlay,
        );

        final picked = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            origin.dx,
            origin.dy,
            overlay.size.width - origin.dx - 200,
            0,
          ),
          items: [
            PopupMenuItem<String>(
              value: '',
              height: 34,
              child: Text(
                tr('No beat'),
                style: TextStyle(
                  color: mq.textPrimary,
                  fontSize: MqTheme.fontLabel,
                ),
              ),
            ),
          ],
        );

        if (picked != null) onPicked(picked);
      },
      builder: (context, states) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: MqIcon(
          'more-line',
          size: 17,
          color: states.active ? mq.textPrimary : mq.textTertiary,
        ),
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: enabled,
      onTap: onPressed,
      focusRadius: MqTheme.radiusSmall + 2,
      builder: (context, states) {
        // Empty bar, nothing to send: the button reads as part of the frame
        // rather than a dimmed pink block.
        final fill = !states.enabled
            ? mq.surfaceTertiary
            : states.pressed
            ? mq.primaryActive
            : states.hovered
            ? mq.primaryHover
            : mq.primary;

        return AnimatedContainer(
          duration: states.duration,
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall + 2),
          ),
          child: MqIcon(
            'send-plane-fill',
            size: 16,
            color: states.enabled ? mq.onPrimary : mq.textDisabled,
          ),
        );
      },
    );
  }
}
