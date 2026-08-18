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
import 'buttons.dart';

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
      onSecondaryTapDown: (details) => showMediaMenu(
        context,
        position: details.globalPosition,
        path: path,
        actions: actions,
        onRemove: onRemove,
        removeLabel: removeLabel,
      ),
      child: child,
    );
  }

  /// What can be done to the file itself, as data.
  ///
  /// Handed out rather than kept private, because the menu is no longer the
  /// only place these are offered: the full-screen player draws the same list
  /// as a row of buttons, and a lightbox that could do less to a clip than the
  /// thumbnail behind it could is a lightbox people close again to get at the
  /// menu. One list, two surfaces.
  ///
  /// Empty when there is no file yet -- a result still generating, or one whose
  /// file has since been moved.
  static List<MediaMenuAction> fileActions(String path) {
    if (path.isEmpty || !File(path).existsSync()) return const [];

    return [
      MediaMenuAction(
        icon: 'external-link-line',
        label: tr('Open in my player'),
        onPressed: () => PlatformUtil.openPath(path),
      ),
      MediaMenuAction(
        icon: 'folder-line',
        label: tr('Show file'),
        onPressed: () => PlatformUtil.revealPath(path),
      ),
      MediaMenuAction(
        icon: 'download-line',
        label: tr('Save as...'),
        onPressed: () => _saveAs(path),
      ),
      MediaMenuAction(
        icon: 'file-copy-line',
        label: isVideoPath(path)
            ? tr('Copy the video')
            : isAudioPath(path)
            ? tr('Copy the recording')
            : tr('Copy the picture'),
        onPressed: () => ClipboardMedia.copyFile(path),
      ),
    ];
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

/// Opens the file menu at [position] without a [MediaMenu] around anything.
///
/// The same menu, reachable from a button as well as from a right-click: the
/// full-screen player has no thumbnail to right-click through and needs every
/// one of these, and a second menu written for it would be a second menu to
/// keep in step.
Future<void> showMediaMenu(
  BuildContext context, {
  required Offset position,
  String path = '',
  List<MediaMenuAction> actions = const [],
  VoidCallback? onRemove,
  String removeLabel = '',
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final entries = [...actions, ...MediaMenu.fileActions(path)];
  if (entries.isEmpty && onRemove == null) return;

  final picked = await showMenu<int>(
    context: context,
    // Shape, colour and elevation come from `popupMenuTheme`, like every other
    // menu in the app.
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 240),
    items: [
      for (var i = 0; i < entries.length; ++i) ...[
        // A rule where the caller's own actions end and the file operations
        // begin: "another take" and "show file" are different kinds of verb.
        if (i == actions.length && i > 0) const PopupMenuDivider(height: 9),
        _menuEntry(
          context,
          i,
          entries[i].icon,
          entries[i].label,
          destructive: entries[i].destructive,
        ),
      ],
      if (entries.isNotEmpty && onRemove != null)
        const PopupMenuDivider(height: 9),
      if (onRemove != null)
        _menuEntry(
          context,
          -1,
          'delete-bin-line',
          removeLabel.isEmpty ? tr('Remove') : removeLabel,
          destructive: true,
        ),
    ],
  );

  if (picked == null) return;
  if (picked < 0) {
    onRemove?.call();
    return;
  }
  if (picked < entries.length) entries[picked].onPressed();
}

PopupMenuItem<int> _menuEntry(
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
        Text(label, style: TextStyle(color: ink, fontSize: MqTheme.fontLabel)),
      ],
    ),
  );
}


/// The file menu as a row of buttons, for the surfaces that have no thumbnail
/// to right-click.
///
/// It draws exactly what [showMediaMenu] would list, in the same order, from
/// the same two lists -- so "the same actions as the context menu" is a fact
/// about the code rather than a promise. The labels become tooltips: at this
/// size a row of six words is a menu bar, and what is wanted is a toolbar.
class MediaActionBar extends StatelessWidget {
  const MediaActionBar({
    super.key,
    this.path = '',
    this.actions = const [],
    this.onRemove,
    this.removeLabel = '',
    this.onClose,
  });

  final String path;
  final List<MediaMenuAction> actions;
  final VoidCallback? onRemove;
  final String removeLabel;

  /// Drawn last, hard against the edge, because closing is the one thing here
  /// that is about the window rather than about the file.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final entries = [...actions, ...MediaMenu.fileActions(path)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: mq.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(MqTheme.radiusPill),
        border: Border.all(color: mq.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            MqIconButton(
              icon: entry.icon,
              tip: entry.label,
              size: 28,
              destructive: entry.destructive,
              onPressed: entry.onPressed,
            ),
          if (onRemove != null)
            MqIconButton(
              icon: 'delete-bin-line',
              tip: removeLabel.isEmpty ? tr('Remove') : removeLabel,
              size: 28,
              destructive: true,
              onPressed: onRemove,
            ),
          if (onClose != null) ...[
            if (entries.isNotEmpty || onRemove != null)
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                color: mq.border,
              ),
            MqIconButton(
              icon: 'fullscreen-exit-line',
              tip: tr('Close'),
              size: 28,
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}
