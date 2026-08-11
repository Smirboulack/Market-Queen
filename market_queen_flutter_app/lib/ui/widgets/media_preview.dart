import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../theme.dart';
import 'media_drop.dart';
import 'mq_dialog.dart';
import 'video_player.dart';

/// Opens whatever [path] is, as large as the window allows, inside the app.
///
/// One entry point for all three kinds so that no call site has to work out
/// which lightbox a file wants -- and so that a reference thumbnail and a
/// finished result behave identically when they are pressed.
Future<void> showMediaPreview(BuildContext context, String path) {
  if (path.isEmpty) return Future.value();
  if (isVideoPath(path)) return showVideoLightbox(context, path);
  if (isAudioPath(path)) return showAudioLightbox(context, path);
  return showImageLightbox(context, path);
}

/// One picture, as large as the window will allow.
Future<void> showImageLightbox(BuildContext context, String path) {
  return showMqModal<void>(
    context: context,
    child: Builder(
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 120,
          maxHeight: MediaQuery.sizeOf(context).height - 120,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MqTheme.radiusLarge),
          child: LocalImage(path, fit: BoxFit.contain),
        ),
      ),
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
