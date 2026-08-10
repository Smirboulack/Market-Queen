import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';

/// One rectangle in the studio: a project, or an ad inside one.
///
/// Both lists are the same list -- a name, when it was last touched, and a way
/// in. Drawing them with one widget is what keeps stepping down a level feeling
/// like walking into a folder rather than arriving somewhere new.
///
/// The rename and delete glyphs only exist while the pointer is on the card,
/// and they sit in a slot that is reserved whether or not they are showing, so
/// nothing under them moves when they appear.
class StudioCard extends StatefulWidget {
  const StudioCard({
    super.key,
    required this.name,
    required this.updatedAt,
    required this.onOpen,
    this.detail = '',
    this.icon = 'folder-line',
    this.onRename,
    this.onDuplicate,
    this.onDelete,
  });

  final String name;
  final DateTime updatedAt;

  /// The line under the date: how many ads, or what the ad is about.
  final String detail;

  final String icon;
  final VoidCallback onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  static const double width = 268;
  static const double height = 132;

  @override
  State<StudioCard> createState() => _StudioCardState();
}

class _StudioCardState extends State<StudioCard> {
  bool _hovered = false;

  /// Same asymmetry as everywhere else: appear at once, fade away.
  Duration get _fade => _hovered ? Duration.zero : MqTheme.hoverDuration;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Pressable(
        onTap: widget.onOpen,
        snap: true,
        focusRadius: MqTheme.radius,
        builder: (context, states) => AnimatedContainer(
          duration: states.duration,
          width: StudioCard.width,
          height: StudioCard.height,
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: states.pressed
                ? mq.surfaceTertiary
                : states.hovered
                ? mq.surfaceHover
                : mq.surface,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: states.active ? mq.borderStrong : mq.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MqIcon(
                    widget.icon,
                    size: 18,
                    color: states.active ? mq.primary : mq.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mq.textPrimary,
                        fontSize: MqTheme.fontBody,
                        fontWeight: FontWeight.w600,
                        height: MqTheme.lineTight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.detail.isNotEmpty) ...[
                          Text(
                            widget.detail,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mq.textSecondary,
                              fontSize: MqTheme.fontSmall,
                              height: MqTheme.lineTight,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          //: %1 is a date and time
                          tr('Edited %1').arg(formatStamp(widget.updatedAt)),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mq.textTertiary,
                            fontSize: MqTheme.fontSmall,
                            height: MqTheme.lineTight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Reserved whether or not the glyphs are showing, so the date
                  // beside them never shifts.
                  SizedBox(
                    height: 26,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1 : 0,
                        duration: _fade,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onRename != null)
                              MqIconButton(
                                icon: 'edit-line',
                                tip: tr('Rename'),
                                onPressed: widget.onRename,
                              ),
                            if (widget.onDuplicate != null)
                              MqIconButton(
                                icon: 'draft-line',
                                tip: tr('Duplicate'),
                                onPressed: widget.onDuplicate,
                              ),
                            if (widget.onDelete != null)
                              MqIconButton(
                                icon: 'delete-bin-line',
                                tip: tr('Delete'),
                                destructive: true,
                                onPressed: widget.onDelete,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "8 Aug 2026, 14:20". One format for every date the studio shows.
String formatStamp(DateTime when) =>
    DateFormat('d MMM yyyy, HH:mm').format(when);

/// The button that makes the next thing.
///
/// Small, transparent and hard against the left edge, in every state of the
/// page. It used to be drawn two different ways -- a quiet outline in the
/// corner once the list had something in it, and a full-width filled slab in
/// the middle of an empty one. The slab was the loudest object in the app, for
/// the least consequential act in it, so both states are this now.
///
/// [Row] with [MainAxisSize.min], not [Align]: a button in a stretched box is
/// one careless `crossAxisAlignment` away from filling the window, and that is
/// exactly how it got there the first time.
class StudioNewButton extends StatelessWidget {
  const StudioNewButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [GhostButton(text: label, onPressed: onPressed)],
    );
  }
}

/// What a studio list says while it is empty: one line, where the first card
/// would be. Not a call to action -- the button above it already is one, and
/// two on a page with nothing on it is a page shouting.
class StudioEmptyNote extends StatelessWidget {
  const StudioEmptyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: StudioCard.width,
      height: StudioCard.height,
      padding: const EdgeInsets.all(16),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.borderSubtle),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mq.textTertiary,
          fontSize: MqTheme.fontLabel,
          height: MqTheme.lineBody,
        ),
      ),
    );
  }
}
