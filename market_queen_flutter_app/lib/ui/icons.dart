import 'package:flutter/material.dart';

/// The Qt build shipped the Remix icon set as SVGs and masked them to get the
/// colour right. Flutter bundles Material Icons as a real icon font, so the
/// glyphs come for free -- this maps the names the interface already used onto
/// their closest Material equivalent, and nothing else has to change.
const _iconByName = <String, IconData>{
  'add-line': Icons.add,
  'arrow-down-s-line': Icons.keyboard_arrow_down,
  'arrow-up-s-line': Icons.keyboard_arrow_up,
  'check-double-line': Icons.done_all,
  'check-line': Icons.check,
  'clapperboard-line': Icons.movie_creation_outlined,
  'close-line': Icons.close,
  'delete-bin-line': Icons.delete_outline,
  'draft-line': Icons.edit_note,
  'edit-line': Icons.edit_outlined,
  'image-add-line': Icons.add_photo_alternate_outlined,
  'image-line': Icons.image_outlined,
  'loader-4-line': Icons.refresh,
  'magic-line': Icons.auto_awesome,
  'mic-line': Icons.mic_none,
  'movie-2-line': Icons.video_library_outlined,
  'pause-fill': Icons.pause,
  'play-fill': Icons.play_arrow,
  'refresh-line': Icons.refresh,
  'send-plane-fill': Icons.send,
  'settings-3-line': Icons.settings_outlined,
  'shopping-bag-3-line': Icons.shopping_bag_outlined,
  'star-fill': Icons.star,
  'star-line': Icons.star_border,
  'user-add-line': Icons.person_add_alt_1_outlined,
  'user-smile-line': Icons.sentiment_satisfied_alt_outlined,
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
