import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets/buttons.dart';

class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.app,
    required this.currentIndex,
    required this.onPicked,
  });

  final AppState app;
  final int currentIndex;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    final entries = [
      (label: tr('Studio'), icon: 'clapperboard-line'),
      (label: tr('Library'), icon: 'movie-2-line'),
      (label: tr('Settings'), icon: 'settings-3-line'),
    ];

    return Container(
      width: 208,
      decoration: BoxDecoration(
        color: mq.surface,
        border: Border(right: BorderSide(color: mq.border)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The one piece of pure brand on the page, and the size of a
              // thumbnail.
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mq.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'MQ',
                  style: TextStyle(
                    color: mq.onPrimary,
                    fontSize: MqTheme.fontSmall,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Product name: never translated.
                    'Market Queen',
                    style: TextStyle(
                      color: mq.textPrimary,
                      fontSize: MqTheme.fontBody,
                      fontWeight: FontWeight.w600,
                      letterSpacing: MqTheme.trackTitle,
                      height: MqTheme.lineTight,
                    ),
                  ),
                  Text(
                    // Company name: never translated.
                    'SegfaultLabs',
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
          const SizedBox(height: 18),
          for (var i = 0; i < entries.length; ++i)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _NavEntry(
                label: entries[i].label,
                icon: entries[i].icon,
                selected: currentIndex == i,
                onTap: () => onPicked(i),
              ),
            ),
          const Spacer(),
          // Bring-your-own-keys means no account, no quota, no subscription.
          ListenableBuilder(
            listenable: app.ffmpegPathChanged,
            builder: (context, _) {
              final ready = app.ffmpegPath.isNotEmpty;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mq.surfaceSecondary,
                  borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
                  border: Border.all(color: mq.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: ready ? mq.success : mq.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          ready ? tr('FFmpeg ready') : tr('FFmpeg missing'),
                          style: TextStyle(
                            color: mq.textSecondary,
                            fontSize: MqTheme.fontSmall,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr('Your keys, your files.\nNothing is uploaded to us.'),
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontSmall,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'v${app.version}',
            style: TextStyle(
              color: mq.textTertiary,
              fontSize: MqTheme.fontMicro,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // Adjacent rows: hover snaps both ways, so sweeping the list never tints
      // two entries at once.
      snap: true,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          // A selected page is a place, not an action: it is marked by a step
          // up the grey ladder, and the pink is left to the icon.
          color: selected
              ? mq.surfaceActive
              : states.pressed
              ? mq.surfaceActive
              : states.hovered
              ? mq.surfaceHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Row(
          children: [
            MqIcon(
              icon,
              size: 18,
              color: selected
                  ? mq.primary
                  : states.active
                  ? mq.textSecondary
                  : mq.textTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected || states.active
                    ? mq.textPrimary
                    : mq.textSecondary,
                fontSize: MqTheme.fontBody,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
