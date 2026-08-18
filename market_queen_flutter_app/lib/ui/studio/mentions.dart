import 'package:flutter/material.dart';

import '../../models/asset_library.dart';
import '../../providers/capabilities.dart' show DeliveryTags;
import '../theme.dart';

/// The handle for every reference in [paths], index for index.
///
/// Numbered within its own kind and in path order, because that is how
/// `StudioRunner` sorts them before uploading: every picture, then every clip,
/// then every recording. Getting this wrong would point the prompt at the wrong
/// file, which is worse than not naming them at all.
List<String> referenceHandles(List<String> paths) {
  var images = 0;
  var videos = 0;
  var audios = 0;

  final handles = <String>[];
  for (final path in paths) {
    if (isVideoPath(path)) {
      handles.add('@Video${++videos}');
    } else if (isAudioPath(path)) {
      handles.add('@Audio${++audios}');
    } else {
      handles.add('@Image${++images}');
    }
  }
  return handles;
}

/// What an actor or a scene is called in a prompt: their own name.
///
/// Spaces and all -- "@Morning kitchen" is what somebody who named a scene
/// "Morning kitchen" will type, and a handle you have to guess the spelling of
/// is not a handle. [findMentions] matches the longest one that fits, so a name
/// with a space in it is no harder to recognise than a word.
String castHandle(String name) => '@${name.trim()}';

/// A character that continues a word, so `@Image1` does not light up inside
/// `@Image10`.
final _wordCharacter = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// Where every known handle appears in [text].
///
/// Longest first at each position: with both "@Marie" and "@Marie Curie" cast,
/// the longer one has to win or the surname is left hanging outside the token.
List<({int start, int length})> findMentions(
  String text,
  List<String> handles,
) {
  if (text.isEmpty || handles.isEmpty) return const [];

  final needles = [for (final handle in handles) handle.toLowerCase()]
    ..sort((a, b) => b.length.compareTo(a.length));
  final haystack = text.toLowerCase();

  final found = <({int start, int length})>[];
  var index = 0;

  while (index < text.length) {
    if (text.codeUnitAt(index) == 0x40) {
      var matched = 0;
      for (final needle in needles) {
        if (needle.length < 2 || !haystack.startsWith(needle, index)) continue;

        // A handle has to end where a word ends. Punctuation, a space or the
        // end of the prompt all close it; another letter means this was a
        // longer word that merely starts the same way.
        final after = index + needle.length;
        if (after < text.length && _wordCharacter.hasMatch(text[after])) {
          continue;
        }

        matched = needle.length;
        break;
      }

      if (matched > 0) {
        found.add((start: index, length: matched));
        index += matched;
        continue;
      }
    }
    index += 1;
  }

  return found;
}

/// Whether [text] points at [handle] at least once.
bool promptMentions(String text, String handle) =>
    findMentions(text, [handle]).isNotEmpty;

/// A prompt field that colours the two things in it that are not prose.
///
/// The only colour in a greyscale interface that is not the send button, and it
/// earns it twice over:
///
///  * A **handle** -- `@Marie`, `@Image1` -- raises exactly one question: did
///    that land, or am I typing at nothing? The answer has to be visible in the
///    glance you give the prompt before pressing send, and an unrecognised
///    `@word` staying plain grey is the other half of the same answer.
///  * A **delivery mark** -- `[excited]`, `[whispers]` -- is the opposite kind
///    of token: it is not pointing at anything, it is an instruction to the
///    voice engine that is never read aloud. Undistinguished, it looked like
///    words the actor was about to say, which is precisely the mistake it
///    causes -- somebody deletes half of one and ships a script with a stray
///    bracket in the middle of a sentence.
///
/// Two colours rather than one, because they are two different claims. Neither
/// can overlap the other: one starts with an at sign and the other with a
/// bracket.
class MentionController extends TextEditingController {
  MentionController({super.text});

  /// Every handle currently attached to the bar. Rewritten on each build --
  /// dropping a reference has to unlight the token that named it.
  List<String> handles = const [];

  /// Whether this field is a script, and its brackets are therefore direction.
  ///
  /// Off on the picture and clip shelves: nothing there is read aloud, so
  /// `[foo]` in a prompt for a still is a bracket like any other and lighting
  /// it up would be inventing a meaning the model has never heard of.
  bool directs = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing =
        withComposing && !value.composing.isCollapsed && value.isComposingRangeValid;

    // While an input method is mid-word its underline is the only sign the
    // keystrokes have not landed yet, and the base implementation is what draws
    // it. Colour can wait for the character to be committed.
    if (composing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final mq = context.mq;
    final base = style ?? const TextStyle();

    final marked = <({int start, int length, TextStyle style})>[
      for (final match in findMentions(text, handles))
        (
          start: match.start,
          length: match.length,
          style: base.copyWith(color: mq.info, fontWeight: FontWeight.w600),
        ),
      if (directs)
        for (final match in DeliveryTags.spansIn(text))
          (
            start: match.start,
            length: match.length,
            // A wash behind it as well as a colour on it. A mark is a token
            // rather than a word -- it has an inside and an outside -- and the
            // tint is what makes a bracket somebody has half-deleted read as
            // broken instead of as ordinary text.
            style: base.copyWith(
              color: mq.delivery,
              backgroundColor: mq.deliverySubtle,
              fontWeight: FontWeight.w600,
            ),
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    if (marked.isEmpty) return TextSpan(text: text, style: style);

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in marked) {
      // The two kinds cannot overlap -- one opens on an at sign and the other
      // on a bracket -- but a defensive skip costs nothing and a negative
      // substring is a crash in the field somebody is typing into.
      if (match.start < cursor) continue;
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.start + match.length),
          style: match.style,
        ),
      );
      cursor = match.start + match.length;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: style, children: spans);
  }
}
