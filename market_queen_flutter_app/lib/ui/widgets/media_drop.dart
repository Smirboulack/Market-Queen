import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

const imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
);

const videoTypeGroup = XTypeGroup(
  label: 'Video',
  extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv'],
);

/// Pictures and clips in one dialog: the two are dropped into the same place,
/// so they should be browsed for in the same place too.
const mediaTypeGroup = XTypeGroup(
  label: 'Images & video',
  extensions: [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'mp4',
    'mov',
    'm4v',
    'webm',
    'mkv',
  ],
);

/// Where references go in: drop them, or click to browse.
///
/// It stays a drop target once it has something -- the tiles appear inside it
/// rather than replacing it, so adding a second reference is the same gesture
/// as the first.
///
/// One widget, two sizes. [tall] is the big empty panel on the ad canvas; the
/// compact one is what the editors use, where the zone is one control among
/// several rather than the point of the card.
class MediaDropZone extends StatefulWidget {
  const MediaDropZone({
    super.key,
    required this.paths,
    required this.onAdded,
    required this.onRemoved,
    this.onPrimary,
    this.title = '',
    this.hint = '',
    this.tall = false,
    this.tileSize = 76,
  });

  final List<String> paths;
  final ValueChanged<List<String>> onAdded;
  final ValueChanged<int> onRemoved;

  /// Set when order matters -- the first picture is the one a model that takes
  /// a single reference is handed. Leaving it null hides the star.
  final ValueChanged<int>? onPrimary;

  final String title;
  final String hint;
  final bool tall;
  final double tileSize;

  @override
  State<MediaDropZone> createState() => _MediaDropZoneState();
}

class _MediaDropZoneState extends State<MediaDropZone> {
  bool _dragging = false;

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: const [mediaTypeGroup]);
    if (files.isEmpty) return;
    widget.onAdded([for (final file in files) file.path]);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final empty = widget.paths.isEmpty;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        final paths = [for (final file in detail.files) file.path];
        if (paths.isNotEmpty) widget.onAdded(paths);
      },
      child: Pressable(
        onTap: _browse,
        focusRadius: MqTheme.radius,
        builder: (context, states) => AnimatedContainer(
          // Drag-over works like hover: instant in, fill and border together,
          // fade only on the way out.
          duration: _dragging ? Duration.zero : states.duration,
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: empty && widget.tall ? 190 : 0,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: empty ? 18 : 12,
          ),
          decoration: BoxDecoration(
            color: _dragging
                ? mq.primarySubtle
                : states.active
                ? mq.surfaceHover
                : mq.surfaceSecondary,
            borderRadius: BorderRadius.circular(MqTheme.radius),
            border: Border.all(
              color: _dragging
                  ? mq.primary
                  : states.active
                  ? mq.borderStrong
                  : mq.border,
            ),
          ),
          child: empty
              ? _prompt(states.active)
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < widget.paths.length; ++i)
                      MediaTile(
                        path: widget.paths[i],
                        size: widget.tileSize,
                        primary: widget.onPrimary != null && i == 0,
                        onPrimary: widget.onPrimary == null || i == 0
                            ? null
                            : () => widget.onPrimary!(i),
                        onRemove: () => widget.onRemoved(i),
                      ),
                    _AddTile(size: widget.tileSize, onTap: _browse),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _prompt(bool active) {
    final mq = context.mq;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MqIcon(
                'image-add-line',
                size: widget.tall ? 24 : 19,
                color: active ? mq.textSecondary : mq.textTertiary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mq.textPrimary,
                    fontSize: widget.tall
                        ? MqTheme.fontTitle
                        : MqTheme.fontBody,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (widget.hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontSmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One reference. A picture shows itself; a clip shows a film glyph and its
/// name, because there is no frame to pull out of it without ffmpeg and a
/// grey rectangle says less than a filename does.
class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.path,
    required this.size,
    required this.onRemove,
    this.primary = false,
    this.onPrimary,
  });

  final String path;
  final double size;
  final VoidCallback onRemove;
  final bool primary;
  final VoidCallback? onPrimary;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final video = isVideoPath(widget.path);

    // The badges fade rather than appear: on a grid, a pointer crossing four
    // tiles used to fire eight of them like a string of lights.
    final fade = _hovered ? Duration.zero : MqTheme.hoverDuration;
    final showStar = widget.primary || (widget.onPrimary != null && _hovered);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: p.basename(widget.path),
        child: AnimatedContainer(
          duration: fade,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: mq.background,
            borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
            border: Border.all(
              color: widget.primary
                  ? mq.primary
                  : _hovered
                  ? mq.borderStrong
                  : mq.border,
              width: widget.primary ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
                child: video
                    ? _VideoTile(path: widget.path)
                    : LocalImage(widget.path),
              ),
              if (widget.onPrimary != null || widget.primary)
                Positioned(
                  left: 4,
                  top: 4,
                  child: IgnorePointer(
                    ignoring: !showStar,
                    child: AnimatedOpacity(
                      opacity: showStar ? 1 : 0,
                      duration: fade,
                      child: _Badge(
                        icon: widget.primary ? 'star-fill' : 'star-line',
                        filled: widget.primary,
                        tip: widget.primary
                            ? tr('The main reference')
                            : tr('Use as the main reference'),
                        onTap: widget.primary ? null : widget.onPrimary,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 4,
                top: 4,
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: fade,
                    child: _Badge(
                      icon: 'close-line',
                      danger: true,
                      tip: tr('Remove'),
                      onTap: widget.onRemove,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ColoredBox(
      color: mq.surfaceTertiary,
      child: Center(
        child: MqIcon('movie-2-line', size: 20, color: mq.textSecondary),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    this.filled = false,
    this.danger = false,
    this.tip = '',
    this.onTap,
  });

  final String icon;
  final bool filled;
  final bool danger;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: onTap != null,
      onTap: onTap,
      tooltip: tip,
      focusRadius: MqTheme.radiusPill,
      builder: (context, states) {
        final Color fill;
        if (filled) {
          fill = mq.primary;
        } else if (states.active) {
          fill = danger ? mq.errorSubtle : mq.surfaceActive;
        } else {
          fill = mq.surface.withValues(alpha: 0.88);
        }

        return AnimatedContainer(
          duration: states.duration,
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: filled
                  ? mq.primary
                  : states.active && danger
                  ? mq.error
                  : mq.borderStrong,
            ),
          ),
          child: MqIcon(
            icon,
            size: 12,
            color: filled
                ? mq.onPrimary
                : danger
                ? mq.error
                : mq.textPrimary,
          ),
        );
      },
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      tooltip: tr('Add more'),
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        width: size,
        height: size,
        alignment: Alignment.center,
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
        child: MqIcon(
          'add-line',
          size: 20,
          color: states.active ? mq.textSecondary : mq.textTertiary,
        ),
      ),
    );
  }
}

/// An image loaded from disk, with the empty state the tiles fall back to.
///
/// Paths point at freshly written files, so the widget is keyed on the path and
/// the file's own modification time -- otherwise a re-shot frame keeps showing
/// the previous render out of Flutter's image cache.
class LocalImage extends StatelessWidget {
  const LocalImage(this.path, {super.key, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();

    final file = File(path);
    if (!file.existsSync()) return const SizedBox.shrink();

    return Image.file(
      file,
      key: ValueKey('$path:${file.statSync().modified.microsecondsSinceEpoch}'),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
