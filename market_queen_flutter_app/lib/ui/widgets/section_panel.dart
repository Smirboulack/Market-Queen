import 'package:flutter/material.dart';

import '../theme.dart';
import 'buttons.dart';

/// One block of the ad canvas: a heading, a line under it, and a fold.
///
/// Boxed rather than ruled, unlike the rail this replaces. On a page that is
/// one wide column the frame is what tells you where the product stops and the
/// casting starts -- there is no panel edge left to do it.
///
/// The fold is a single glyph on the right and it is the whole point of the
/// layout: everything above the scenario bar collapses out of the way, so a
/// second pass at the words never means scrolling past a form you have already
/// filled in.
class SectionPanel extends StatelessWidget {
  const SectionPanel({
    super.key,
    required this.title,
    required this.open,
    required this.onToggled,
    required this.children,
    this.subtitle = '',
    this.required = false,
    this.trailing,
  });

  final String title;
  final String subtitle;

  /// Marks the sections worth filling in. Nothing on this page is enforced --
  /// the star is advice, not a validator.
  final bool required;

  final bool open;
  final VoidCallback onToggled;

  /// Sits left of the fold: a summary while the section is closed, usually.
  final Widget? trailing;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
        border: Border.all(color: mq.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole heading toggles, not just the glyph: a 26px target for
          // something you open twenty times a session is mean.
          Pressable(
            onTap: onToggled,
            canRequestFocus: false,
            focusRadius: MqTheme.radiusLarge,
            builder: (context, states) => Padding(
              padding: const EdgeInsets.fromLTRB(MqTheme.gapLarge, 16, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: title),
                              if (required)
                                TextSpan(
                                  text: ' *',
                                  style: TextStyle(color: mq.primaryText),
                                ),
                            ],
                          ),
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
                              color: mq.textTertiary,
                              fontSize: MqTheme.fontSmall,
                              height: MqTheme.lineTight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: MqTheme.gap),
                    trailing!,
                  ],
                  const SizedBox(width: 6),
                  // Drawn rather than an icon: a minus and a plus are what the
                  // two states are, and the arrow glyphs read as navigation.
                  _FoldMark(open: open, lit: states.active),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MqTheme.gapLarge,
                0,
                MqTheme.gapLarge,
                MqTheme.gapLarge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; ++i) ...[
                    if (i > 0) const SizedBox(height: 10),
                    children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FoldMark extends StatelessWidget {
  const _FoldMark({required this.open, required this.lit});

  final bool open;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final ink = lit ? mq.textPrimary : mq.textSecondary;

    return SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 1.6, width: 14, color: ink),
              if (!open) Container(width: 1.6, height: 14, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}
