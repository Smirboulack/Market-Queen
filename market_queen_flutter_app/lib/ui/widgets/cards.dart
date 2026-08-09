import 'package:flutter/material.dart';

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

