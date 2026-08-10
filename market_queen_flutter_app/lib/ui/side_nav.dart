import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'brand.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';

/// One entry in the nav.
class NavEntry {
  const NavEntry({
    required this.label,
    required this.icon,
    required this.page,
    this.expansion,
  });

  final String label;
  final String icon;

  /// Index into the window's page stack.
  final int page;

  /// Unfolded beneath the row while this is the page you are on.
  ///
  /// Only the studio uses it, and only because the studio is the one page with
  /// somewhere to go: projects, then ads, then the ad. Walking back up that
  /// with the crumb trail alone means two clicks and a page load to look at the
  /// ad next door.
  final Widget? expansion;
}

/// The left column: the mark, the pages, and the one status line that matters
/// before anything is generated.
///
/// There is no account, plan or credit block here and there never will be while
/// the app is bring-your-own-keys: there is nothing to sign into and nothing to
/// meter. The only thing worth reserving the bottom corner for is whether the
/// machine can actually render a video.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.app,
    required this.entries,
    required this.currentPage,
    required this.onPicked,
  });

  final AppState app;
  final List<NavEntry> entries;
  final int currentPage;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      width: MqTheme.navWidth,
      decoration: BoxDecoration(
        color: mq.surface,
        border: Border(right: BorderSide(color: mq.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The rows and whatever is unfolded under them share the space above
          // the status line; the tree gives its room back before anything else
          // has to be pushed off the bottom.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    children: [
                      const BrandMark(size: 70),
                      const SizedBox(width: 11),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // Product name: never translated.
                            'Market Queen',
                            style: TextStyle(
                              color: mq.textPrimary,
                              fontSize: MqTheme.fontTitle,
                              fontWeight: FontWeight.w600,
                              letterSpacing: MqTheme.trackTitle,
                              height: MqTheme.lineTight,
                            ),
                          ),
                          Text(
                            tr('studio'),
                            style: TextStyle(
                              color: mq.textTertiary,
                              fontSize: MqTheme.fontSmall,
                              height: MqTheme.lineTight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                for (final entry in entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _NavRow(
                      entry: entry,
                      selected: entry.page == currentPage,
                      onTap: () => onPicked(entry.page),
                    ),
                  ),
                  if (entry.expansion != null && entry.page == currentPage)
                    Flexible(child: entry.expansion!),
                ],
              ],
            ),
          ),
          const SizedBox(height: MqTheme.gap),
          ListenableBuilder(
            listenable: app.ffmpegPathChanged,
            builder: (context, _) {
              final ready = app.ffmpegPath.isNotEmpty;
              return Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: ready ? mq.success : mq.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ready ? tr('FFmpeg ready') : tr('FFmpeg missing'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ready ? mq.textTertiary : mq.warningText,
                        fontSize: MqTheme.fontSmall,
                      ),
                    ),
                  ),
                  Text(
                    'v${app.version}',
                    style: TextStyle(
                      color: mq.textTertiary,
                      fontSize: MqTheme.fontMicro,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final NavEntry entry;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      focusRadius: MqTheme.radius,
      // Adjacent rows: hover snaps both ways, so sweeping the list never tints
      // two entries at once.
      snap: true,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          // The page you are on is the one place in the nav that is worth
          // spending brand colour on -- a faint tint, not a fill, so it still
          // reads as a place rather than as a button waiting to be pressed.
          color: selected
              ? mq.primarySubtle
              : states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radius),
        ),
        child: Row(
          children: [
            MqIcon(
              entry.icon,
              size: 19,
              color: !states.enabled && !selected
                  ? mq.textDisabled
                  : selected
                  ? mq.primary
                  : states.active
                  ? mq.textSecondary
                  : mq.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: !states.enabled && !selected
                      ? mq.textDisabled
                      : selected || states.active
                      ? mq.textPrimary
                      : mq.textSecondary,
                  fontSize: MqTheme.fontBody,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
