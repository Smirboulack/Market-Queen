import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/paths.dart';

/// How a person or a place is asked for.
///
/// The whole point of this class is the prompt it builds. Image models default
/// to advertising photography, and asking them for a "UGC look" does not move
/// them -- they comply in words and still render a campaign shot. The scaffold
/// in resources/casting.json names the camera, imposes concrete flaws and
/// forbids the commercial vocabulary by name. It is data, not code, because
/// this is the part of the product that needs the most iteration.
///
/// It generates nothing itself: [ImageForge] does that, from the text this
/// returns.
class Casting {
  Casting();

  static const _fileName = 'casting.json';

  /// Fragment id -> text, with {slots}.
  Map<String, Object?> _portrait = {};
  List<String> _order = [];
  Map<String, Object?> _fallbacks = {};

  bool _overridden = false;

  bool get overridden => _overridden;

  /// Where a casting.json would go to override the bundled scaffold.
  String get overridePath => p.join(Paths.configDir, _fileName);

  Future<void> load() async {
    // The user's file wins outright rather than merging, for the same reason
    // the price catalogue does: a half-overridden scaffold would be impossible
    // to reason about when a picture comes out wrong.
    _overridden = _loadFromFile(overridePath);
    if (!_overridden) {
      _loadScaffold(
        await rootBundle.loadString('assets/resources/casting.json'),
      );
    }
  }

  bool _loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return false;
    try {
      return _loadScaffold(file.readAsStringSync());
    } on FileSystemException {
      return false;
    }
  }

  bool _loadScaffold(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return false;
    }
    if (decoded is! Map<String, dynamic>) return false;

    final portrait = decoded['portrait'];
    if (portrait is! Map || portrait.isEmpty) return false;

    _portrait = portrait.cast<String, Object?>();

    final fallbacks = decoded['fallbacks'];
    _fallbacks = fallbacks is Map ? fallbacks.cast<String, Object?>() : {};

    final order = decoded['order'];
    _order = order is List ? [for (final entry in order) '$entry'] : [];

    // An override that forgot the order array still works: fall back to every
    // fragment the file defines, in the order the file lists them.
    if (_order.isEmpty) _order = _portrait.keys.toList();

    return true;
  }

  String _fragment(String key) => '${_portrait[key] ?? ''}'.trim();

  String _fallback(String key) => '${_fallbacks[key] ?? ''}';

  // ---- The prompts ------------------------------------------------------

  /// The exact text that would be sent for an actor. Shown in the editor: the
  /// realism work is the product here, so it should be inspectable rather than
  /// magic.
  ///
  /// [description] is what the user wrote. [location] is the scene, when the
  /// actor is being pictured somewhere in particular.
  String buildPortraitPrompt({
    required String description,
    String location = '',
  }) {
    var subjectText = description.trim();
    if (subjectText.isEmpty) subjectText = _fallback('subject');

    var locationText = location.trim();
    if (locationText.isEmpty) locationText = _fallback('location');

    final parts = <String>[];
    for (final key in _order) {
      final fragment = _fragment(key);
      if (fragment.isEmpty) continue;
      parts.add(
        fragment
            .replaceAll('{subject}', subjectText)
            .replaceAll('{location}', locationText),
      );
    }

    return parts.join(' ');
  }

  /// The same fight, for a room rather than a face: an empty place, shot on a
  /// phone by somebody who lives there.
  ///
  /// The scaffold has no scenery block of its own -- the two fragments worth
  /// borrowing are the flaws and the list of forbidden words, which are what
  /// keep a location from coming back as an interiors catalogue.
  String buildScenePrompt({required String description, String tweaks = ''}) {
    var place = description.trim();
    if (place.isEmpty) place = _fallback('location');

    final parts = <String>[
      'A photo of a place, taken on a phone by somebody who is there. '
          'Nobody in frame.',
      'The place: $place.',
      if (tweaks.trim().isNotEmpty) 'It is ${tweaks.trim()}.',
      _fragment('flaws'),
      _fragment('forbid'),
    ];

    return [for (final part in parts) if (part.isNotEmpty) part].join(' ');
  }
}
