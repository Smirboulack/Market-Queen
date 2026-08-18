import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/translator.dart';
import '../../models/asset_library.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/media_drop.dart';
import '../widgets/video_poster.dart';

/// Which heading an entry sits under.
///
/// Two, and the split is not cosmetic: a cast handle names somebody the avatar
/// model will be handed, and a file handle names something the prompt is
/// pointing the model at. They are answers to different questions, and a single
/// alphabetical list of five things called "@" hid that.
enum MentionGroup { cast, files }

/// One thing the prompt can address by name, with enough about it to be
/// recognised in a list.
///
/// The composer already knew every handle -- it lights them in the field and
/// writes them on the thumbnails -- but only as a string. Choosing between them
/// takes a face, a frame and a line saying what the thing is, which is what
/// this adds.
@immutable
class MentionEntry {
  const MentionEntry({
    required this.handle,
    required this.label,
    required this.group,
    this.detail = '',
    this.thumbnail = '',
    this.glyph = 'attachment-line',
    this.round = false,
  });

  /// "@Marie", "@Image1" -- with the at sign, because that is what is typed.
  final String handle;

  /// What it stands for: a person's name, a file name.
  final String label;

  final MentionGroup group;

  /// The line under the handle: "24 years old · Female", "PNG · 240 KB".
  final String detail;

  /// A picture of it, when there is one. A clip's poster frame is pulled the
  /// same way the canvas pulls one.
  final String thumbnail;

  /// Drawn when there is no picture, or none yet.
  final String glyph;

  /// People are round and files are not. It is the fastest way to tell the two
  /// groups apart when the list is scrolled past its headings.
  final bool round;

  /// Whether this entry answers to what has been typed after the at sign.
  ///
  /// Matched on both the handle and the name, because they are not always the
  /// same word: a file dropped in second is `@Image2` and called `bottle.png`,
  /// and somebody hunting for it will type either.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    return handle.toLowerCase().contains(needle) ||
        label.toLowerCase().contains(needle);
  }
}

/// The unfinished handle the caret is sitting in, if it is sitting in one.
///
/// [start] is the index of the at sign and [query] is whatever has been typed
/// after it, so a caller can replace exactly that run with a real handle.
///
/// The rules are the ones that stop the menu opening over an email address or
/// halfway through a word: the at sign has to begin a word, and everything
/// between it and the caret has to be a word character. A space closes it --
/// which does mean a cast name with a space in it stops matching once the space
/// is typed, and that is the right trade: picking the name out of the menu is
/// the fast path, and typing the whole of "@Morning kitchen" by hand is the
/// case that already worked.
({int start, String query})? mentionQueryAt(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;

  var index = caret;
  while (index > 0) {
    final code = text.codeUnitAt(index - 1);
    if (code == 0x40) {
      // An at sign only opens a handle at the start of a word. "a@b" is an
      // address, not a mention.
      if (index - 1 > 0 && !_isBlank(text.codeUnitAt(index - 2))) return null;
      return (start: index - 1, query: text.substring(index, caret));
    }
    if (!_isWordCharacter(code)) return null;
    index -= 1;
  }
  return null;
}

bool _isBlank(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;

/// Letters, digits, underscore and hyphen. Deliberately narrow: a full stop
/// closes the run, so a handle at the end of a sentence stops matching before
/// the menu has a chance to reopen on the next word.
bool _isWordCharacter(int code) =>
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    code == 0x5F ||
    code == 0x2D ||
    code >= 0x00C0;

/// A file, in the words a one-line detail has room for: what kind it is and how
/// big it is on disk.
///
/// Read off the file system rather than off the file's contents. A picture's
/// pixel size and a clip's running time would both be better, and both cost a
/// decode or an ffprobe per entry per keystroke -- which is not a price a menu
/// that opens on every "@" can pay.
String describeFile(String path) {
  final kind = path.split('.').last.toUpperCase();
  try {
    final bytes = File(path).lengthSync();
    return '$kind  ·  ${_sizeOf(bytes)}';
  } on FileSystemException {
    return kind;
  }
}

String _sizeOf(int bytes) {
  if (bytes >= 1024 * 1024) {
    //: %1 is a number of megabytes, such as "12.4"
    return tr('%1 MB').arg((bytes / (1024 * 1024)).toStringAsFixed(1));
  }
  //: %1 is a whole number of kilobytes
  return tr('%1 KB').arg((bytes / 1024).round());
}

/// The list that opens when an "@" is typed.
///
/// It exists because the handles were only ever discoverable by reading them
/// off the thumbnails under the prompt -- which works for `@Image1` and not at
/// all for a cast name you have to spell exactly. Typing the at sign is now the
/// question, and this is the answer: everybody and everything this prompt can
/// point at, grouped, with a face or a frame beside each one.
class MentionMenu extends StatelessWidget {
  const MentionMenu({
    super.key,
    required this.entries,
    required this.highlighted,
    required this.onPicked,
    this.ffmpegPath = '',
  });

  final List<MentionEntry> entries;

  /// Which row the keyboard is on. The mouse lights its own row on hover; this
  /// is the one Enter would take.
  final int highlighted;

  final ValueChanged<MentionEntry> onPicked;

  final String ffmpegPath;

  static const double width = 320;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Container(
      decoration: BoxDecoration(
        color: mq.surface,
        borderRadius: BorderRadius.circular(MqTheme.radius),
        border: Border.all(color: mq.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          // A heading whenever the group changes, which with two groups means
          // at most two of them -- and none at all once a query has narrowed
          // the list to one kind.
          final heads = index == 0 || entries[index - 1].group != entry.group;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (heads) _Heading(group: entry.group, first: index == 0),
              _Row(
                entry: entry,
                lit: index == highlighted,
                ffmpegPath: ffmpegPath,
                onTap: () => onPicked(entry),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.group, required this.first});

  final MentionGroup group;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 6 : 10, 12, 4),
      child: Text(
        switch (group) {
          MentionGroup.cast => tr('CAST'),
          MentionGroup.files => tr('FILES'),
        },
        style: TextStyle(
          color: mq.textTertiary,
          fontSize: MqTheme.fontMicro,
          fontWeight: FontWeight.w700,
          letterSpacing: MqTheme.trackOverline,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.lit,
    required this.onTap,
    this.ffmpegPath = '',
  });

  final MentionEntry entry;
  final bool lit;
  final VoidCallback onTap;
  final String ffmpegPath;

  static const double _thumb = 34;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Pressable(
      onTap: onTap,
      // The rows touch, so hover snaps both ways and only one is ever lit.
      snap: true,
      focusRadius: MqTheme.radiusSmall,
      builder: (context, states) => AnimatedContainer(
        duration: states.duration,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          // The keyboard's row and the pointer's row are the same look, because
          // they mean the same thing: this is the one Enter takes.
          color: lit || states.active ? mq.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(MqTheme.radiusSmall),
        ),
        child: Row(
          children: [
            _Thumbnail(entry: entry, size: _thumb, ffmpegPath: ffmpegPath),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      // The same blue the prompt lights it in once it is typed,
                      // so the row and the token read as one thing seen twice.
                      color: mq.info,
                      fontSize: MqTheme.fontLabel,
                      fontWeight: FontWeight.w600,
                      height: MqTheme.lineTight,
                    ),
                  ),
                  if (entry.detail.isNotEmpty)
                    Text(
                      entry.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: mq.textTertiary,
                        fontSize: MqTheme.fontMicro,
                        height: MqTheme.lineTight,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.entry,
    required this.size,
    this.ffmpegPath = '',
  });

  final MentionEntry entry;
  final double size;
  final String ffmpegPath;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    final path = entry.thumbnail;
    final radius = entry.round
        ? BorderRadius.circular(size)
        : BorderRadius.circular(MqTheme.radiusSmall);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: mq.surfaceSecondary,
        borderRadius: radius,
        border: Border.all(color: mq.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: MqIcon(entry.glyph, size: 15, color: mq.textTertiary)),
          if (path.isNotEmpty)
            if (isVideoPath(path))
              VideoPosterImage(ffmpegPath: ffmpegPath, path: path)
            else if (!isAudioPath(path))
              LocalImage(path),
        ],
      ),
    );
  }
}
