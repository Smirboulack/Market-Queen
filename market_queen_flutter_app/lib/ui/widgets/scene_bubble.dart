import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// One line, already written.
///
/// At rest it is text: a number, the words, how long they take. Everything else
/// -- reordering, the type, the visual, deleting -- only exists while the
/// pointer is on it. A row of six always-visible buttons per scene is what made
/// the old editor look like a spreadsheet.
class SceneBubble extends StatefulWidget {
  const SceneBubble({
    super.key,
    required this.position,
    required this.total,
    required this.line,
    required this.kind,
    required this.imagePrompt,
    required this.seconds,
    required this.directed,
    required this.onLineEdited,
    required this.onKindToggled,
    required this.onMoveRequested,
    required this.onRemoveRequested,
  });

  final int position;
  final int total;
  final String line;
  final String kind;
  final String imagePrompt;
  final double seconds;
  final bool directed;

  final ValueChanged<String> onLineEdited;
  final VoidCallback onKindToggled;
  final ValueChanged<int> onMoveRequested;
  final VoidCallback onRemoveRequested;

  @override
  State<SceneBubble> createState() => _SceneBubbleState();
}

class _SceneBubbleState extends State<SceneBubble> {
  final TextEditingController _editor = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _hovered = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _editor.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _beginEdit() {
    setState(() {
      _editing = true;
      _editor.text = widget.line;
      _editor.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editor.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _commit() {
    if (!_editing) return;
    setState(() => _editing = false);
    final text = _editor.text.trim();
    if (text != widget.line) widget.onLineEdited(text);
  }

  bool get _isBroll => widget.kind == 'broll';

  /// Five 26px glyphs. The slot is this wide whether or not they are showing.
  static const double _controlsWidth = 5 * 26;

  bool get _showControls => _hovered && !_editing;

  /// Same asymmetry as everywhere else: appear at once, fade away.
  Duration get _fade => _showControls ? Duration.zero : MqTheme.hoverDuration;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _editing ? null : _beginEdit,
        child: AnimatedContainer(
          duration: _hovered || _editing
              ? Duration.zero
              : MqTheme.hoverDuration,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered || _editing
                ? mq.surfaceSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: _editing
                  ? mq.primary
                  : _hovered
                  ? mq.borderStrong
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Number, or the b-roll marker: the one thing about a scene worth
              // seeing without hovering.
              // Neutral: a list of eight scenes numbered in pink would spend
              // the whole colour budget on counting.
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isBroll ? Colors.transparent : mq.surfaceTertiary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isBroll ? mq.borderStrong : Colors.transparent,
                  ),
                ),
                child: _isBroll
                    ? MqIcon('image-line', size: 14, color: mq.textTertiary)
                    : Text(
                        '${widget.position + 1}'.padLeft(2, '0'),
                        style: TextStyle(
                          color: mq.textSecondary,
                          fontSize: MqTheme.fontSmall,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_editing)
                      Shortcuts(
                        shortcuts: const {
                          SingleActivator(LogicalKeyboardKey.enter):
                              _CommitIntent(),
                          SingleActivator(LogicalKeyboardKey.escape):
                              _CancelIntent(),
                        },
                        child: Actions(
                          actions: {
                            _CommitIntent: CallbackAction<_CommitIntent>(
                              onInvoke: (_) {
                                _commit();
                                return null;
                              },
                            ),
                            _CancelIntent: CallbackAction<_CancelIntent>(
                              onInvoke: (_) {
                                setState(() => _editing = false);
                                return null;
                              },
                            ),
                          },
                          child: TextField(
                            controller: _editor,
                            focusNode: _focus,
                            maxLines: null,
                            cursorColor: mq.primary,
                            style: TextStyle(
                              color: mq.textPrimary,
                              fontSize: MqTheme.fontBody,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        widget.line,
                        style: TextStyle(
                          color: mq.textPrimary,
                          fontSize: MqTheme.fontBody,
                        ),
                      ),
                    // On screen whether or not the pointer is here. Revealing
                    // it on hover grew the row, which shoved every scene below
                    // it down the page -- under a pointer that was, by
                    // definition, aiming at one of them.
                    if (widget.directed && !_editing) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.imagePrompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontSmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The controls and the duration share one fixed slot and cross-
              // fade inside it. Swapping a 30px label for a 130px toolbar --
              // which is what this used to do -- resized the row the instant
              // the pointer arrived, so the text next to it jumped sideways
              // and the button you were reaching for was somewhere else.
              SizedBox(
                width: _controlsWidth,
                height: 26,
                child: Stack(
                  alignment: AlignmentDirectional.centerEnd,
                  children: [
                    AnimatedOpacity(
                      opacity: _showControls ? 0 : 1,
                      duration: _fade,
                      child: Text(
                        //: %1 is a duration in seconds
                        tr('%1 s').arg(widget.seconds.toStringAsFixed(1)),
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontSmall,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: !_showControls,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1 : 0,
                        duration: _fade,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MqIconButton(
                              icon: _isBroll ? 'image-line' : 'user-smile-line',
                              tip: _isBroll
                                  ? tr('Product shot')
                                  : tr('Talking'),
                              onPressed: widget.onKindToggled,
                            ),
                            MqIconButton(
                              icon: 'arrow-up-s-line',
                              enabled: widget.position > 0,
                              onPressed: () =>
                                  widget.onMoveRequested(widget.position - 1),
                            ),
                            MqIconButton(
                              icon: 'arrow-down-s-line',
                              enabled: widget.position < widget.total - 1,
                              onPressed: () =>
                                  widget.onMoveRequested(widget.position + 1),
                            ),
                            MqIconButton(
                              icon: 'edit-line',
                              tip: tr('Edit'),
                              onPressed: _beginEdit,
                            ),
                            MqIconButton(
                              icon: 'delete-bin-line',
                              tip: tr('Delete'),
                              destructive: true,
                              onPressed: widget.onRemoveRequested,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitIntent extends Intent {
  const _CommitIntent();
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}
