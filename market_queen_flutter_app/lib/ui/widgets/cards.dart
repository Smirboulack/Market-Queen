import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';

/// A titled panel. The studio and settings pages are stacks of these.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title = '',
    this.subtitle = '',
    this.step = 0,
    required this.children,
  });

  final String title;
  final String subtitle;

  /// A numbered badge, when the card is one of an ordered set.
  final int step;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MqTheme.gapLarge),
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step > 0) ...[
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mq.accentSoft,
                      shape: BoxShape.circle,
                      border: Border.all(color: mq.accent),
                    ),
                    child: Text(
                      '$step',
                      style: TextStyle(
                        color: mq.accent,
                        fontSize: MqTheme.fontSmall,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: mq.text,
                          fontSize: MqTheme.fontTitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: mq.textDim,
                            fontSize: MqTheme.fontSmall + 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: MqTheme.gap),
          ],
          for (var i = 0; i < children.length; ++i) ...[
            if (i > 0) const SizedBox(height: MqTheme.gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One step's worth of recap, and the way back to that step.
///
/// Empty blocks stay on screen rather than appearing as they fill: the shape of
/// the whole ad should be readable from the first second, including the parts
/// that are still missing.
class RecapBlock extends StatefulWidget {
  const RecapBlock({
    super.key,
    required this.title,
    required this.filled,
    required this.placeholder,
    required this.children,
    this.stepIndexTap,
  });

  final String title;
  final bool filled;
  final String placeholder;
  final List<Widget> children;

  /// Where this block sends you when clicked, or null when that step is not
  /// reachable yet.
  final VoidCallback? stepIndexTap;

  @override
  State<RecapBlock> createState() => _RecapBlockState();
}

class _RecapBlockState extends State<RecapBlock> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final clickable = widget.stepIndexTap != null;

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: clickable ? (_) => setState(() => _hovered = true) : null,
      onExit: clickable ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.stepIndexTap,
        child: AnimatedContainer(
          duration: MqTheme.hoverDuration,
          width: double.infinity,
          padding: const EdgeInsets.all(MqTheme.gap),
          decoration: BoxDecoration(
            color: _hovered ? mq.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(color: mq.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: mq.textDim,
                      fontSize: MqTheme.fontSmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_hovered)
                    MqIcon('edit-line', size: 14, color: mq.accent),
                ],
              ),
              const SizedBox(height: 6),
              if (widget.filled)
                ...widget.children
              else
                Text(
                  widget.placeholder,
                  style: TextStyle(
                    color: mq.textFaint,
                    fontSize: MqTheme.fontSmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
