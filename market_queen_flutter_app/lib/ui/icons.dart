import 'package:flutter/material.dart';

/// The Qt build shipped the Remix icon set as SVGs and masked them to get the
/// colour right. Flutter bundles Material Icons as a real icon font, so the
/// glyphs come for free -- this maps the names the interface already used onto
/// their closest Material equivalent, and nothing else has to change.
const _iconByName = <String, IconData>{
  'add-line': Icons.add,
  'arrow-down-s-line': Icons.keyboard_arrow_down,
  'arrow-left-line': Icons.arrow_back,
  'arrow-right-s-line': Icons.keyboard_arrow_right,
  'arrow-up-line': Icons.arrow_upward,
  'arrow-up-s-line': Icons.keyboard_arrow_up,
  'attachment-line': Icons.attach_file,
  'check-double-line': Icons.done_all,
  'check-line': Icons.check,
  'clapperboard-line': Icons.movie_creation_outlined,
  'close-line': Icons.close,
  'delete-bin-line': Icons.delete_outline,
  'download-line': Icons.download_outlined,
  'draft-line': Icons.edit_note,
  'edit-line': Icons.edit_outlined,
  'emotion-line': Icons.mood_outlined,
  'equalizer-line': Icons.tune,
  'error-warning-line': Icons.error_outline,
  'external-link-line': Icons.open_in_new,
  'flashlight-line': Icons.bolt_outlined,
  'folder-line': Icons.folder_outlined,
  'fullscreen-exit-line': Icons.fullscreen_exit,
  'fullscreen-line': Icons.fullscreen,
  'gallery-line': Icons.photo_library_outlined,
  'image-add-line': Icons.add_photo_alternate_outlined,
  'image-line': Icons.image_outlined,
  'information-line': Icons.info_outline,
  'layout-line': Icons.dashboard_customize_outlined,
  'lightbulb-line': Icons.lightbulb_outline,
  'loader-4-line': Icons.refresh,
  'magic-line': Icons.auto_awesome,
  'mic-line': Icons.mic_none,
  'more-line': Icons.more_horiz,
  'movie-2-line': Icons.video_library_outlined,
  'pause-fill': Icons.pause,
  'play-fill': Icons.play_arrow,
  'refresh-line': Icons.refresh,
  // The set an ad is filmed on. A framed backdrop rather than a picture frame,
  // so it cannot be mistaken for `image-line` two rows above it in the nav.
  'scene-line': Icons.wallpaper_outlined,
  'search-line': Icons.search,
  'send-plane-fill': Icons.send,
  'settings-3-line': Icons.settings_outlined,
  'shopping-bag-3-line': Icons.shopping_bag_outlined,
  'shuffle-line': Icons.shuffle,
  'sound-module-line': Icons.graphic_eq,
  'sparkling-line': Icons.auto_awesome_outlined,
  'star-fill': Icons.star,
  'star-line': Icons.star_border,
  'subtract-line': Icons.remove,
  'text-shorten': Icons.short_text,
  'timer-line': Icons.timer_outlined,
  'translate-line': Icons.translate,
  'upload-cloud-line': Icons.cloud_upload_outlined,
  'upload-line': Icons.file_upload_outlined,
  'user-add-line': Icons.person_add_alt_1_outlined,
  'user-line': Icons.person_outline,
  'user-smile-line': Icons.sentiment_satisfied_alt_outlined,
  'user-voice-line': Icons.record_voice_over_outlined,
  'volume-up-line': Icons.volume_up_outlined,
};

IconData? mqIcon(String name) => _iconByName[name];

/// One icon, in any colour. A missing name draws nothing rather than a
/// placeholder box.
class MqIcon extends StatelessWidget {
  const MqIcon(this.name, {super.key, this.size = 16, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final data = mqIcon(name);
    if (data == null) return SizedBox(width: size, height: size);
    return Icon(data, size: size, color: color);
  }
}
