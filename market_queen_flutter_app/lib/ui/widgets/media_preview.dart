import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../theme.dart';
import 'file_menu.dart';
import 'media_drop.dart';
import 'mq_dialog.dart';
import 'video_player.dart';

/// Opens whatever [path] is, as large as the window allows, inside the app.
///
/// One entry point for all three kinds so that no call site has to work out
/// which lightbox a file wants -- and so that a reference thumbnail and a
/// finished result behave identically when they are pressed.
///
/// [actions] are the caller's own -- another take, use as a reference -- and
/// are drawn above the file operations, exactly as the right-click menu draws
/// them.
Future<void> showMediaPreview(
  BuildContext context,
  String path, {
  List<MediaMenuAction> actions = const [],
  VoidCallback? onRemove,
  String removeLabel = '',
}) {
  if (path.isEmpty) return Future.value();
  if (isVideoPath(path)) {
    return showVideoLightbox(
      context,
      path,
      actions: actions,
      onRemove: onRemove,
      removeLabel: removeLabel,
    );
  }
  if (isAudioPath(path)) return showAudioLightbox(context, path);
  return showImageLightbox(
    context,
    path,
    actions: actions,
    onRemove: onRemove,
    removeLabel: removeLabel,
  );
}

/// One picture, as large as the window will allow.
Future<void> showImageLightbox(
  BuildContext context,
  String path, {
  List<MediaMenuAction> actions = const [],
  VoidCallback? onRemove,
  String removeLabel = '',
}) {
  return showMqModal<void>(
    context: context,
    child: Builder(
      builder: (context) {
        // Anything that removes the picture or asks for another takes the
        // window with it: what is on screen would otherwise be a file that is
        // no longer in the feed.
        void andClose(VoidCallback action) {
          closeMqModal(context);
          action();
        }

        final wrapped = [
          for (final action in actions)
            MediaMenuAction(
              icon: action.icon,
              label: action.label,
              destructive: action.destructive,
              onPressed: () => andClose(action.onPressed),
            ),
        ];

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 120,
            maxHeight: MediaQuery.sizeOf(context).height - 120,
          ),
          child: MediaMenu(
            path: path,
            actions: wrapped,
            onRemove: onRemove == null ? null : () => andClose(onRemove),
            removeLabel: removeLabel,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
                  child: LocalImage(path, fit: BoxFit.contain),
                ),
                // The same list the right-click menu holds -- see
                // [MediaActionBar].
                Positioned(
                  right: 10,
                  top: 10,
                  child: MediaActionBar(
                    path: path,
                    actions: wrapped,
                    onRemove:
                        onRemove == null ? null : () => andClose(onRemove),
                    removeLabel: removeLabel,
                    onClose: () => closeMqModal(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// A recording has nothing to enlarge, so its "preview" is a card with the
/// player in it -- the same row the canvas draws, given a name and some room.
Future<void> showAudioLightbox(BuildContext context, String path) {
  return showMqModal<void>(
    context: context,
    child: MqModalCard(
      title: p.basename(path),
      subtitle: tr('Press to listen.'),
      width: 460,
      child: InlineAudio(path: path),
    ),
  );
}
