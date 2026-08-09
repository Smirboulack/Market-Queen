import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'icons.dart';
import 'theme.dart';

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
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mq.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'MQ',
                  style: TextStyle(
                    color: mq.accent,
                    fontSize: MqTheme.fontSmall + 1,
                    fontWeight: FontWeight.bold,
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
                      color: mq.text,
                      fontSize: MqTheme.fontBody + 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    // Company name: never translated.
                    'SegfaultLabs',
                    style: TextStyle(
                      color: mq.textFaint,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < entries.length; ++i)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
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
                  color: mq.surfaceAlt,
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
                        const SizedBox(width: 6),
                        Text(
                          ready ? tr('FFmpeg ready') : tr('FFmpeg missing'),
                          style: TextStyle(
                            color: mq.textDim,
                            fontSize: MqTheme.fontSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('Your keys, your files.\nNothing is uploaded to us.'),
                      style: TextStyle(
                        color: mq.textFaint,
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
            style: TextStyle(color: mq.textFaint, fontSize: MqTheme.fontSmall),
          ),
        ],
      ),
    );
  }
}

class _NavEntry extends StatefulWidget {
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
  State<_NavEntry> createState() => _NavEntryState();
}

class _NavEntryState extends State<_NavEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // Adjacent rows: hover snaps both ways, so sweeping the list never
            // tints two entries at once.
            color: widget.selected
                ? mq.accentSoft
                : _hovered
                    ? mq.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          ),
          child: Row(
            children: [
              MqIcon(
                widget.icon,
                size: 18,
                color: widget.selected ? mq.accent : mq.textFaint,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected ? mq.text : mq.textDim,
                  fontSize: MqTheme.fontBody,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
