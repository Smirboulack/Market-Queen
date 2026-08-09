import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';
import '../i18n/translator.dart';

/// The actors the user has kept.
///
/// An actor is the expensive part of a good ad: it takes several batches to
/// land a face that reads as real, and once it does it should never have to be
/// found again. Saving one copies its portrait out of the casting scratch
/// folder into the config directory, so clearing scratch can never orphan a
/// saved actor.
class ActorLibrary extends ChangeNotifier {
  ActorLibrary() {
    _load();
  }

  static const _fileName = 'actors.json';
  static const _portraitFolder = 'actors';

  final List<Map<String, Object?>> _actors = [];

  List<Map<String, Object?>> get actors => List.unmodifiable(_actors);
  int get count => _actors.length;

  String get _storeFile => p.join(Paths.configDir, _fileName);
  String get _portraitDir => p.join(Paths.configDir, _portraitFolder);

  // ---- Storage ----------------------------------------------------------

  void _load() {
    final file = File(_storeFile);
    if (!file.existsSync()) return;

    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Exception {
      return;
    }
    if (decoded is! List) return;

    _actors
      ..clear()
      ..addAll([
        for (final entry in decoded)
          if (entry is Map && '${entry['id'] ?? ''}'.isNotEmpty)
            entry.cast<String, Object?>(),
      ]);

    notifyListeners();
  }

  void _persist() {
    if (Paths.ensureDir(Paths.configDir).isEmpty) return;
    try {
      File(_storeFile)
          .writeAsStringSync(const JsonEncoder.withIndent('    ').convert(_actors));
    } on FileSystemException {
      // The next save tries again.
    }
  }

  void refresh() {
    _load();
    notifyListeners();
  }

  /// Copies a portrait out of scratch into the library folder, returning the
  /// new path. Files already inside the library are left where they are.
  String _adoptPortrait(String id, String path) {
    if (path.isEmpty || !File(path).existsSync()) return path;

    final dir = Paths.ensureDir(_portraitDir);
    if (dir.isEmpty) return path;

    // Already ours: a re-save of an unchanged actor must not copy the file onto
    // itself and must not accumulate duplicates.
    if (p.equals(p.dirname(File(path).absolute.path), dir)) return path;

    final extension = p.extension(path).replaceFirst('.', '');
    final target = p.join(dir, '$id.${extension.isEmpty ? 'png' : extension}');

    try {
      final existing = File(target);
      if (existing.existsSync()) existing.deleteSync();
      File(path).copySync(target);
      return target;
    } on FileSystemException {
      return path;
    }
  }

  // ---- Entries ----------------------------------------------------------

  /// Inserts or updates, and returns the actor's id. An actor carrying an id
  /// that is already on file is updated in place rather than duplicated.
  String save(Map<String, Object?> actor) {
    final entry = Map<String, Object?>.of(actor);

    var id = '${entry['id'] ?? ''}';
    if (id.isEmpty) id = _newId();
    entry['id'] = id;

    if ('${entry['name'] ?? ''}'.trim().isEmpty) {
      entry['name'] = suggestedName();
    }

    entry['portraitPath'] = _adoptPortrait(id, '${entry['portraitPath'] ?? ''}');

    final existing = _actors.indexWhere((a) => '${a['id'] ?? ''}' == id);
    if (existing >= 0) {
      _actors[existing] = entry;
    } else {
      // Newest first: the actor just cast is the one about to be used.
      _actors.insert(0, entry);
    }

    _persist();
    notifyListeners();
    return id;
  }

  Map<String, Object?> actor(String id) {
    for (final entry in _actors) {
      if ('${entry['id'] ?? ''}' == id) return Map<String, Object?>.of(entry);
    }
    return {};
  }

  void remove(String id) {
    final index = _actors.indexWhere((a) => '${a['id'] ?? ''}' == id);
    if (index < 0) return;

    final portrait = '${_actors[index]['portraitPath'] ?? ''}';
    _actors.removeAt(index);

    // Only files we adopted are ours to delete; a portrait the user pointed at
    // from their own folders stays where it is.
    if (portrait.isNotEmpty &&
        p.equals(p.dirname(File(portrait).absolute.path), _portraitDir)) {
      try {
        final file = File(portrait);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Leaving an orphan file behind beats failing the delete.
      }
    }

    _persist();
    notifyListeners();
  }

  /// Suggests a name for an actor that has none, so saving never blocks on a
  /// dialog: "Actor 3".
  String suggestedName() => tr('Actor %1').arg(_actors.length + 1);

  static int _counter = 0;

  static String _newId() {
    _counter += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '${stamp.substring(stamp.length - 6)}$_counter';
  }
}
