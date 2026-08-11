import 'package:flutter/material.dart';

import '../../models/asset_library.dart';
import '../theme.dart';

/// One thing attached to the composer that the prompt can point at by name.
///
/// The handles are not an invention of the interface: `@Image1`, `@Video1` and
/// `@Audio1` are exactly what the reference video models are handed, in exactly
/// the order the runner uploads them. What was missing was any way to find that
/// out without reading the log after the fact -- so the same names are now on
/// the tiles, in the placeholder, and lit up in the prompt as you type them.
@immutable
class Mention {
  const Mention({required this.handle, required this.label});

  /// "@Image1", "@Marie" -- with the at sign, because that is what is typed.
  final String handle;

  /// What it stands for, for the tooltip: a file name, or a cast name.
  final String label;
}

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

/// A prompt field that colours the handles it recognises.
///
/// The one piece of colour in a greyscale interface that is not the send
/// button, and it earns it: the whole question a handle raises is "did that
/// land, or am I typing at nothing", and the answer has to be visible in the
/// glance you give the prompt before pressing send. An unrecognised `@word`
/// stays plain grey, which is the other half of the same answer.
class MentionController extends TextEditingController {
  MentionController({super.text});

  /// Every handle currently attached to the bar. Rewritten on each build --
  /// dropping a reference has to unlight the token that named it.
  List<String> handles = const [];

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
    if (composing || handles.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final matches = findMentions(text, handles);
    if (matches.isEmpty) return TextSpan(text: text, style: style);

    final lit = (style ?? const TextStyle()).copyWith(
      color: context.mq.info,
      fontWeight: FontWeight.w600,
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.start + match.length),
          style: lit,
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
