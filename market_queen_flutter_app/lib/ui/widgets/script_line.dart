import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

/// The five beats a UGC ad is built from, in the order they are written.
///
/// One list, used by the composer's tabs, by the line's own badge and by the
/// prompt the rewrite buttons send -- so the label on screen and the word the
/// model is given can never drift apart.
class Beat {
  const Beat(this.id, this.label, this.placeholder, this.advice);

  final String id;
  final String label;

  /// What the composer says while this tab is selected.
  final String placeholder;

  /// One line of why the beat exists, for the tips popup.
  final String advice;

  static List<Beat> get all => [
    Beat(
      'hook',
      tr('Hook'),
      tr('Describe the hook of your ad in one powerful sentence…'),
      tr('The first three seconds. Name the frustration, not the product.'),
    ),
    Beat(
      'problem',
      tr('Problem'),
      tr('What did they try that did not work?'),
      tr('Make it concrete. One thing that failed, not a category of things.'),
    ),
    Beat(
      'solution',
      tr('Solution'),
      tr('How does it come in? Casually, not as an advert.'),
      tr('Introduce it as what finally worked, not as a product launch.'),
    ),
    Beat(
      'benefit',
      tr('Benefit'),
      tr('One specific result. A number, a timeframe, a moment.'),
      tr('One detail beats three adjectives. "Two weeks", not "fast".'),
    ),
    Beat(
      'cta',
      tr('CTA'),
      tr('Say what to do next, casually.'),
      tr('Casual and singular. One action, said the way a friend would.'),
    ),
  ];

  static Beat? find(String id) {
    for (final beat in all) {
      if (beat.id == id) return beat;
    }
    return null;
  }
}

/// One line of the script, in the sheet.
///
/// At rest it is text: a number, the beat it plays, the words, how long they
/// take. Everything else -- reordering, the shot type, deleting -- only exists
/// while the pointer is on it. A row of five always-visible buttons per line is
/// what made the old editor look like a spreadsheet.
class ScriptLine extends StatefulWidget {
  const ScriptLine({
    super.key,
    required this.position,
    required this.total,
    required this.line,
    required this.kind,
    required this.beat,
    required this.imagePrompt,
    required this.seconds,
    required this.directed,
    required this.selected,
    required this.onSelected,
    required this.onLineEdited,
    required this.onKindToggled,
    required this.onMoveRequested,
    required this.onRemoveRequested,
  });

  final int position;
  final int total;
  final String line;
  final String kind;
  final String beat;
  final String imagePrompt;
  final double seconds;
  final bool directed;

  /// The line the scene picker is pointing at.
  final bool selected;

  final VoidCallback onSelected;
  final ValueChanged<String> onLineEdited;
  final VoidCallback onKindToggled;
  final ValueChanged<int> onMoveRequested;
  final VoidCallback onRemoveRequested;

  @override
  State<ScriptLine> createState() => _ScriptLineState();
}

class _ScriptLineState extends State<ScriptLine> {
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
    final beat = Beat.find(widget.beat);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editing ? null : widget.onSelected,
        onDoubleTap: _editing ? null : _beginEdit,
        child: AnimatedContainer(
          duration: _hovered || _editing
              ? Duration.zero
              : MqTheme.hoverDuration,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _editing
                ? mq.surfaceSecondary
                : _hovered
                ? mq.surfaceHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: _editing
                  ? mq.primary
                  : widget.selected
                  ? mq.primaryMuted
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The gutter. A plain number, like a script: a list of eight lines
              // numbered in pink would spend the whole colour budget on
              // counting.
              SizedBox(
                width: 22,
                child: _isBroll
                    ? MqIcon('image-line', size: 15, color: mq.textTertiary)
                    : Text(
                        '${widget.position + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: mq.textTertiary,
                          fontSize: MqTheme.fontLabel,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.5,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
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
                      Text.rich(
                        TextSpan(
                          children: [
                            if (beat != null)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 8,
                                  ),
                                  child: _BeatTag(label: beat.label),
                                ),
                              ),
                            TextSpan(text: widget.line),
                          ],
                        ),
                        style: TextStyle(
                          color: mq.textPrimary,
                          fontSize: MqTheme.fontBody,
                        ),
                      ),
                    // On screen whether or not the pointer is here. Revealing it
                    // on hover grew the row, which shoved every line below it
                    // down the page -- under a pointer that was, by definition,
                    // aiming at one of them.
                    if (widget.directed && !_editing) ...[
                      const SizedBox(height: 3),
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
              // which is what this used to do -- resized the row the instant the
              // pointer arrived, so the text next to it jumped sideways and the
              // button you were reaching for was somewhere else.
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

/// Which beat a line plays, on the line itself. Grey, not pink: there can be
/// eight of these on screen at once.
class _BeatTag extends StatelessWidget {
  const _BeatTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: mq.surfaceTertiary,
        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: mq.textSecondary,
          fontSize: MqTheme.fontMicro - 1,
          fontWeight: FontWeight.w600,
          letterSpacing: MqTheme.trackOverline,
          height: 1.2,
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
