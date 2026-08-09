import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

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
                      color: mq.primarySubtle,
                      shape: BoxShape.circle,
                      border: Border.all(color: mq.primaryMuted),
                    ),
                    child: Text(
                      '$step',
                      style: TextStyle(
                        color: mq.primaryText,
                        fontSize: MqTheme.fontMicro,
                        fontWeight: FontWeight.w600,
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
                          color: mq.textPrimary,
                          fontSize: MqTheme.fontTitle,
                          fontWeight: FontWeight.w600,
                          letterSpacing: MqTheme.trackTitle,
                          height: MqTheme.lineTight,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: mq.textSecondary,
                            fontSize: MqTheme.fontLabel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: MqTheme.gap + 2),
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

/// The title of a page and the one line under it explaining what the page is
/// for. One widget so the five pages cannot drift apart by a pixel of tracking.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle = ''});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: mq.textPrimary,
            fontSize: MqTheme.fontHeading,
            fontWeight: FontWeight.w600,
            letterSpacing: MqTheme.trackHeading,
            height: MqTheme.lineTight,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(
              color: mq.textSecondary,
              fontSize: MqTheme.fontBody,
            ),
          ),
        ],
      ],
    );
  }
}

/// A section heading that is not a title: small, spaced, upper case, and never
/// competing with the text under it. The only place the interface sets caps.
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.mq.textTertiary,
        fontSize: MqTheme.fontMicro,
        fontWeight: FontWeight.w600,
        letterSpacing: MqTheme.trackOverline,
      ),
    );
  }
}

/// One step's worth of recap, and the way back to that step.
///
/// Empty blocks stay on screen rather than appearing as they fill: the shape of
/// the whole ad should be readable from the first second, including the parts
/// that are still missing.
class RecapBlock extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: stepIndexTap,
      cursor: SystemMouseCursors.click,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: double.infinity,
        padding: const EdgeInsets.all(MqTheme.gap),
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: states.active ? mq.borderStrong : mq.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: mq.textTertiary,
                    fontSize: MqTheme.fontMicro,
                    fontWeight: FontWeight.w600,
                    letterSpacing: MqTheme.trackOverline,
                  ),
                ),
                const Spacer(),
                // Always in the layout, only ever faded. Revealing it on hover
                // reflowed the title line under the pointer.
                AnimatedOpacity(
                  opacity: states.active ? 1 : 0,
                  duration: states.duration,
                  child: MqIcon('edit-line', size: 14, color: mq.primaryText),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (filled)
              ...children
            else
              Text(
                placeholder,
                style: TextStyle(
                  color: mq.textTertiary,
                  fontSize: MqTheme.fontSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
