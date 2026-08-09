import 'dart:math' as math;

/// How a written scenario becomes a list of shots.
///
/// Pure text in, pure text out: the pipeline cuts the real ad with this and the
/// pricer estimates against it, so what is quoted before Generate and what is
/// bought after it are the same list rather than two guesses that happen to
/// agree.
class ShotPlanner {
  ShotPlanner._();

  /// What an energetic UGC read delivers, the figure the whole app plans
  /// against.
  static const wordsPerSecond = 2.6;

  /// The longest one camera setup should hold.
  ///
  /// Past about five seconds a lip-synced still gives itself away: the hands
  /// stop, the head drifts back to where it started, and the eye finds the loop.
  /// Cutting to another angle costs one more frame and hides all of it.
  static const maxShotSeconds = 5.0;

  /// Below this, an ad has nothing to cut away to and the director pass is not
  /// worth buying. The pricer and the pipeline agree because they read it here.
  static const minShotsToDirect = 3;

  static int words(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  /// Seconds of speech in [text].
  static double seconds(String text) => words(text) / wordsPerSecond;

  /// Sentence boundaries, including the ones people actually type.
  ///
  /// An ellipsis ends a spoken thought as surely as a full stop does, and
  /// leaving it out of the set is what used to weld two written beats into one
  /// shot -- which is how a nine-paragraph scenario came back as eight.
  ///
  /// But only when it really is an ending. Written UGC is full of ellipses that
  /// are a breath rather than a stop -- "ce que tu recherches… et l'idée c'est
  /// de", "bon… pourquoi pas" -- and cutting there would hand the engine half a
  /// thought to read as a whole one. What comes next settles it: a capital
  /// letter is a new sentence, a small one is the same sentence still going.
  static final _boundary =
      RegExp(r'(?<=[.!?])\s+|(?<=[…;])\s+(?=\p{Lu})', unicode: true);

  static List<String> sentences(String text) => text
      .split(_boundary)
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.isNotEmpty)
      .toList();

  /// The beats the user wrote, in the order they wrote them.
  ///
  /// Someone who lays a scenario out one thought per line has already done the
  /// cutting, and the app has no business overriding it. So blank-line groups
  /// are read first and single lines second; only a scenario typed as one
  /// unbroken block is cut by punctuation alone.
  static List<String> units(String script) {
    final paragraphs = script
        .split(RegExp(r'\n[ \t]*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
    if (paragraphs.length > 1) return paragraphs;

    final lines = script
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length > 1) return lines;

    final single = script.trim();
    return single.isEmpty ? const [] : [single];
  }

  /// Cuts [script] into the lines of the shots it should be filmed as.
  ///
  /// Two rules, and they are the whole of it. A sentence is never cut in half,
  /// because each shot's audio is recorded from its own line and half a
  /// sentence is read as half a thought. And a written beat is never welded to
  /// the next one, because that beat is where the user wanted the cut.
  ///
  /// Within one beat, short sentences are packed together until the shot
  /// reaches [maxShotSeconds] -- so writing "Bon… pourquoi pas ?" on its own
  /// line does not buy a one-second clip of someone shrugging.
  static List<String> split(String script) {
    final maxWords = math.max(1, (maxShotSeconds * wordsPerSecond).round());
    final shots = <String>[];

    for (final unit in units(script)) {
      var current = '';

      for (final sentence in sentences(unit)) {
        final candidate = current.isEmpty ? sentence : '$current $sentence';
        if (current.isNotEmpty && words(candidate) > maxWords) {
          shots.add(current);
          current = sentence;
        } else {
          current = candidate;
        }
      }

      if (current.isNotEmpty) shots.add(current);
    }

    // A scenario made of nothing but whitespace and punctuation still has to
    // come back as something to film.
    if (shots.isEmpty && script.trim().isNotEmpty) shots.add(script.trim());
    return shots;
  }
}
