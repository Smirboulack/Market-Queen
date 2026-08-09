import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../icons.dart';
import '../theme.dart';
import 'buttons.dart';

const imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
);

/// Every picture of the product, not just one.
///
/// The first image is the primary: it is the one handed to a model that only
/// accepts a single reference. That makes ordering meaningful, so promoting an
/// image is an explicit act -- the star -- rather than a side effect of dragging
/// things around.
class ImageDropGrid extends StatefulWidget {
  const ImageDropGrid({
    super.key,
    required this.images,
    required this.onFilesAdded,
    required this.onRemoveRequested,
    required this.onPrimaryRequested,
  });

  final List<String> images;
  final ValueChanged<List<String>> onFilesAdded;
  final ValueChanged<int> onRemoveRequested;
  final ValueChanged<int> onPrimaryRequested;

  @override
  State<ImageDropGrid> createState() => _ImageDropGridState();
}

class _ImageDropGridState extends State<ImageDropGrid> {
  static const _tileSize = 88.0;

  bool _dragging = false;

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: const [imageTypeGroup]);
    if (files.isEmpty) return;
    widget.onFilesAdded([for (final file in files) file.path]);
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final empty = widget.images.isEmpty;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        final paths = [for (final file in detail.files) file.path];
        if (paths.isNotEmpty) widget.onFilesAdded(paths);
      },
      child: AnimatedContainer(
        // Drag-over works like hover: instant in, fill and border together,
        // fade only on the way out.
        duration: MqTheme.hoverDuration,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dragging ? mq.accentSoft : mq.surfaceAlt,
          borderRadius: BorderRadius.circular(MqTheme.radius),
          border: Border.all(color: _dragging ? mq.accent : mq.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (empty) ...[
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    MqIcon('image-add-line', size: 30, color: mq.textFaint),
                    const SizedBox(height: 4),
                    Text(
                      tr('Drop your product pictures here'),
                      style: TextStyle(
                        color: mq.text,
                        fontSize: MqTheme.fontBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('As many as you like. Packshot, in use, close-up on the label.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: mq.textDim,
                        fontSize: MqTheme.fontSmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < widget.images.length; ++i)
                    _Tile(
                      path: widget.images[i],
                      primary: i == 0,
                      size: _tileSize,
                      onPrimary: () => widget.onPrimaryRequested(i),
                      onRemove: () => widget.onRemoveRequested(i),
                    ),
                  // Add one more, in place, without hunting for the button.
                  _AddTile(size: _tileSize, onTap: _browse),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    empty
                        ? ''
                        : widget.images.length == 1
                            ? tr('1 picture. It is the reference.')
                            //: %1 is a number of pictures
                            : tr('%1 pictures. The starred one is the main reference.')
                                .arg(widget.images.length),
                    style: TextStyle(
                      color: mq.textFaint,
                      fontSize: MqTheme.fontSmall,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GhostButton(text: tr('Browse'), onPressed: _browse),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.path,
    required this.primary,
    required this.size,
    required this.onPrimary,
    required this.onRemove,
  });

  final String path;
  final bool primary;
  final double size;
  final VoidCallback onPrimary;
  final VoidCallback onRemove;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final borderWidth = widget.primary ? 2.0 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: mq.background,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(
            color: widget.primary
                ? mq.accent
                : _hovered
                    ? mq.borderStrong
                    : mq.border,
            width: borderWidth,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MqTheme.radiusSmall - 1),
              child: LocalImage(widget.path, fit: BoxFit.cover),
            ),
            // Primary marker. Always lit on the first tile, offered on the
            // others only while the pointer is on them.
            if (widget.primary || _hovered)
              Positioned(
                left: 4,
                top: 4,
                child: _Badge(
                  icon: widget.primary ? 'star-fill' : 'star-line',
                  filled: widget.primary,
                  onTap: widget.primary ? null : widget.onPrimary,
                ),
              ),
            if (_hovered)
              Positioned(
                right: 4,
                top: 4,
                child: _Badge(
                  icon: 'close-line',
                  danger: true,
                  onTap: widget.onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    this.filled = false,
    this.danger = false,
    this.onTap,
  });

  final String icon;
  final bool filled;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      enabled: onTap != null,
      onTap: onTap,
      builder: (context, hovered, pressed) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? mq.accent : mq.background.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: filled ? mq.accent : mq.borderStrong),
        ),
        child: MqIcon(
          icon,
          size: 12,
          color: filled
              ? Colors.white
              : danger
                  ? mq.danger
                  : mq.text,
        ),
      ),
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
      builder: (context, hovered, pressed) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? mq.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
          border: Border.all(color: hovered ? mq.borderStrong : mq.border),
        ),
        child: MqIcon('add-line', size: 20, color: mq.textFaint),
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
