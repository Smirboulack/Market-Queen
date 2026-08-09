import 'package:flutter/material.dart';

import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';

/// One segment of the trail. A crumb without an [onTap] is where you already
/// are, or a label with nowhere to go -- both are drawn as plain text rather
/// than as a link that does nothing.
class Crumb {
  const Crumb(this.label, {this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// The strip above the content: where you are on the left, the one action that
/// applies to the whole window on the right.
///
/// Deliberately almost empty. There is no autosave badge -- the draft is written
/// to disk 400ms after every keystroke and has been since the first build, and a
/// permanent "saved 2m ago" only ever teaches people to worry about it. There is
/// no Preview and no settings glyph either: preview is the render itself, and
/// settings is a page in the nav.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.crumbs, this.trailing});

  final List<Crumb> crumbs;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      height: MqTheme.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: MqTheme.pagePadding),
      decoration: BoxDecoration(
        color: mq.background,
        border: Border(bottom: BorderSide(color: mq.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < crumbs.length; ++i) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: MqIcon(
                        'arrow-right-s-line',
                        size: 16,
                        color: mq.textDisabled,
                      ),
                    ),
                  Flexible(
                    child: _CrumbLabel(
                      crumb: crumbs[i],
                      last: i == crumbs.length - 1,
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
        ],
      ),
    );
  }
}

class _CrumbLabel extends StatelessWidget {
  const _CrumbLabel({required this.crumb, required this.last});

  final Crumb crumb;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: crumb.onTap != null,
      onTap: crumb.onTap,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Text(
          crumb.label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            // Where you are is the only crumb in full contrast; the trail
            // behind it is context, not a heading.
            color: last || states.active ? mq.textPrimary : mq.textSecondary,
            fontSize: MqTheme.fontBody,
            fontWeight: last ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: MqTheme.trackTitle,
          ),
        ),
      ),
    );
  }
}
