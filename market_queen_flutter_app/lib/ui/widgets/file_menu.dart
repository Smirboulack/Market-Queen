import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/clipboard_media.dart';
import '../../core/platform_util.dart';
import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../icons.dart';
import '../theme.dart';

/// One entry a caller adds to the file menu, above the file operations.
///
/// It exists for the actions that are about *this* screen rather than about
/// the file: taking a generated face back into the prompt as a reference means
/// nothing on the canvas and is the point of the menu in the casting studio.
class MediaMenuAction {
  const MediaMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

/// The right-click menu on anything the app produced.
///
/// Every generation is written to disk the moment it lands, so the things
/// anybody wants from a result are file operations -- open it, keep a copy,
/// copy it out -- and none of them belongs on a hover strip that can only hold
/// three glyphs. A context menu is where a desktop keeps them.
///
/// One widget for the canvas and for the casting studio, because a picture that
/// answers the pointer one way in one window and another way in the next is two
/// pictures as far as the user is concerned.
class MediaMenu extends StatelessWidget {
  const MediaMenu({
    super.key,
    required this.child,
    this.path = '',
    this.actions = const [],
    this.onRemove,
    this.removeLabel = '',
  });

  final Widget child;

  /// Empty while the result is still pending or came back empty: the menu then
  /// offers only whatever the caller added.
  final String path;

  /// Screen-specific entries, shown first.
  final List<MediaMenuAction> actions;

  /// Null where there is nothing to take away -- or, on the canvas, while
  /// requests are still out for the batch.
  final VoidCallback? onRemove;

  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Secondary only: the primary tap belongs to whatever is underneath, and
      // both gestures can live on the same pixels without an arena between
      // them.
      onSecondaryTapDown: (details) => _open(context, details.globalPosition),
      child: child,
    );
  }

  Future<void> _open(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasFile = path.isNotEmpty && File(path).existsSync();

    // Negative for the file operations, the index for a caller's own: one menu
    // of one type, and no answer that can be confused with another.
    const reveal = -1;
    const saveAs = -2;
    const copy = -3;
    const remove = -4;

    final picked = await showMenu<int>(
      context: context,
      // Shape, colour and elevation come from `popupMenuTheme`, like every
      // other menu in the app.
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 240),
      items: [
        for (var i = 0; i < actions.length; ++i)
          _entry(
            context,
            i,
            actions[i].icon,
            actions[i].label,
            destructive: actions[i].destructive,
          ),
        if (actions.isNotEmpty && hasFile) const PopupMenuDivider(height: 9),
        if (hasFile) ...[
          _entry(context, reveal, 'folder-line', tr('Show file')),
          _entry(context, saveAs, 'download-line', tr('Save as...')),
          _entry(
            context,
            copy,
            'file-copy-line',
            isVideoPath(path)
                ? tr('Copy the video')
                : isAudioPath(path)
                ? tr('Copy the recording')
                : tr('Copy the picture'),
          ),
        ],
        if (hasFile && onRemove != null) const PopupMenuDivider(height: 9),
        if (onRemove != null)
          _entry(
            context,
            remove,
            'delete-bin-line',
            removeLabel.isEmpty ? tr('Remove') : removeLabel,
            destructive: true,
          ),
      ],
    );

    if (picked == null || !context.mounted) return;

    switch (picked) {
      case reveal:
        await PlatformUtil.revealPath(path);
      case saveAs:
        await _saveAs(path);
      case copy:
        await ClipboardMedia.copyFile(path);
      case remove:
        onRemove?.call();
      default:
        if (picked >= 0 && picked < actions.length) {
          actions[picked].onPressed();
        }
    }
  }

  PopupMenuItem<int> _entry(
    BuildContext context,
    int value,
    String icon,
    String label, {
    bool destructive = false,
  }) {
    final mq = context.mq;
    final ink = destructive ? mq.errorText : mq.textPrimary;

    return PopupMenuItem<int>(
      value: value,
      height: 38,
      child: Row(
        children: [
          MqIcon(icon, size: 16, color: ink),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: ink, fontSize: MqTheme.fontLabel),
          ),
        ],
      ),
    );
  }

  /// A copy, wherever they ask for it. The generated file itself stays where it
  /// was written -- "save as" on something already saved is an export, and
  /// moving the original would break the tile that points at it.
  static Future<void> _saveAs(String path) async {
    final extension = p.extension(path).replaceFirst('.', '');
    final location = await getSaveLocation(
      suggestedName: p.basename(path),
      acceptedTypeGroups: [
        if (extension.isNotEmpty)
          XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return;

    try {
      await File(path).copy(location.path);
    } on FileSystemException {
      // The dialog picked somewhere unwritable. Nothing was moved and nothing
      // was lost; the original is still where it was.
    }
  }
}
