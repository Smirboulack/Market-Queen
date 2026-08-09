import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';
import '../i18n/translator.dart';

/// One reusable piece of casting: an actor, or a décor.
///
/// Both are the same object -- a name, a description in plain words, the
/// pictures and clips it was described with, and one still to recognise it by.
/// What differs is only what the extras carry: a voice for an actor, the light
/// and the mood for a décor.
class LibraryAsset {
  LibraryAsset({
    this.id = '',
    this.name = '',
    this.prompt = '',
    this.previewPath = '',
    List<String>? media,
    Map<String, Object?>? extras,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : media = media ?? <String>[],
       extras = extras ?? <String, Object?>{},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Reads an entry written by any build of the app. The keys an actor used
  /// before the rewrite -- `brief`, `portraitPath`, `referenceImages` -- are
  /// accepted so a library saved by the old studio opens untouched.
  factory LibraryAsset.fromJson(Map<String, Object?> json) {
    final extras = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_ownKeys.contains(entry.key)) extras[entry.key] = entry.value;
    }

    final rawMedia = json['media'] ?? json['referenceImages'];

    return LibraryAsset(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      prompt: '${json['prompt'] ?? json['brief'] ?? ''}',
      previewPath: '${json['previewPath'] ?? json['portraitPath'] ?? ''}',
      media: rawMedia is List ? [for (final entry in rawMedia) '$entry'] : null,
      extras: extras,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }

  /// Everything the class owns by name. Anything else in the file is an extra
  /// and is carried through untouched, so a field this build does not know
  /// about survives a save.
  static const _ownKeys = <String>{
    'id',
    'name',
    'prompt',
    'brief',
    'previewPath',
    'portraitPath',
    'media',
    'referenceImages',
    'createdAt',
    'updatedAt',
  };

  String id;
  String name;

  /// What the user typed to describe it.
  String prompt;

  /// One still, generated or promoted from the references. Empty until there
  /// is something to show.
  String previewPath;

  /// Reference images and clips, in the order they were added.
  final List<String> media;

  /// Everything that belongs to one kind and not the other.
  final Map<String, Object?> extras;

  DateTime createdAt;
  DateTime updatedAt;

  /// A detached copy: an editor works on one of these and only writes back
  /// when the user saves, so cancelling really cancels.
  LibraryAsset copy() => LibraryAsset(
    id: id,
    name: name,
    prompt: prompt,
    previewPath: previewPath,
    media: List<String>.of(media),
    extras: Map<String, Object?>.of(extras),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  String extraText(String key) => '${extras[key] ?? ''}';

  double extraNumber(String key, double fallback) {
    final value = extras[key];
    return value is num ? value.toDouble() : fallback;
  }

  void setExtra(String key, Object? value) {
    if (value == null || (value is String && value.isEmpty)) {
      extras.remove(key);
    } else {
      extras[key] = value;
    }
  }

  /// The picture to show for it: the still if there is one, otherwise the first
  /// reference that is an image rather than a clip.
  String get thumbnail {
    if (previewPath.isNotEmpty) return previewPath;
    for (final path in media) {
      if (!isVideoPath(path)) return path;
    }
    return '';
  }

  bool get isEmpty =>
      prompt.trim().isEmpty && media.isEmpty && previewPath.isEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'previewPath': previewPath,
    'media': media,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    ...extras,
  };
}

const _videoExtensions = <String>{
  '.mp4',
  '.mov',
  '.m4v',
  '.webm',
  '.mkv',
  '.avi',
};

/// Whether a reference is a clip rather than a picture. Clips cannot be handed
/// to an image model, so every place that picks a reference has to know.
bool isVideoPath(String path) =>
    _videoExtensions.contains(p.extension(path).toLowerCase());

/// A folder of reusable assets on disk.
///
/// Saving copies the still out of the scratch folder into the library's own
/// directory, so clearing scratch can never orphan a saved actor or décor.
abstract class AssetLibrary extends ChangeNotifier {
  /// [_fileName] is the store inside the config directory, [_folder] the
  /// sub-directory adopted stills are copied into.
  AssetLibrary(this._fileName, this._folder) {
    _load();
  }

  final String _fileName;
  final String _folder;
  final List<LibraryAsset> _assets = [];

  List<LibraryAsset> get assets => List.unmodifiable(_assets);
  int get count => _assets.length;

  /// What an entry saved without a name is called: "Actor 3", "Décor 3".
  String suggestedName();

  String get _storeFile => p.join(Paths.configDir, _fileName);
  String get _previewDir => p.join(Paths.configDir, _folder);

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

    _assets
      ..clear()
      ..addAll([
        for (final entry in decoded)
          if (entry is Map && '${entry['id'] ?? ''}'.isNotEmpty)
            LibraryAsset.fromJson(entry.cast<String, Object?>()),
      ]);

    notifyListeners();
  }

  void _persist() {
    if (Paths.ensureDir(Paths.configDir).isEmpty) return;
    try {
      File(_storeFile).writeAsStringSync(
        const JsonEncoder.withIndent(
          '    ',
        ).convert([for (final asset in _assets) asset.toJson()]),
      );
    } on FileSystemException {
      // The next save tries again.
    }
  }

  void refresh() {
    _load();
    notifyListeners();
  }

  // ---- Entries ----------------------------------------------------------

  LibraryAsset? byId(String id) {
    if (id.isEmpty) return null;
    for (final asset in _assets) {
      if (asset.id == id) return asset;
    }
    return null;
  }

  /// Inserts or updates, and returns the id. An asset carrying an id already on
  /// file is updated in place rather than duplicated.
  String save(LibraryAsset asset) {
    final entry = asset.copy();

    if (entry.id.isEmpty) entry.id = _newId();
    if (entry.name.trim().isEmpty) entry.name = suggestedName();
    entry.updatedAt = DateTime.now();
    entry.previewPath = _adoptPreview(entry.id, entry.previewPath);

    final existing = _assets.indexWhere((a) => a.id == entry.id);
    if (existing >= 0) {
      _assets[existing] = entry;
    } else {
      // Newest first: the one just made is the one about to be used.
      _assets.insert(0, entry);
    }

    _persist();
    notifyListeners();
    return entry.id;
  }

  void remove(String id) {
    final index = _assets.indexWhere((asset) => asset.id == id);
    if (index < 0) return;

    final preview = _assets[index].previewPath;
    _assets.removeAt(index);

    // Only files we adopted are ours to delete; a picture the user pointed at
    // from their own folders stays where it is.
    if (preview.isNotEmpty && _isAdopted(preview)) {
      try {
        final file = File(preview);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Leaving an orphan behind beats failing the delete.
      }
    }

    _persist();
    notifyListeners();
  }

  bool _isAdopted(String path) {
    final dir = _previewDir;
    try {
      return p.equals(p.dirname(File(path).absolute.path), dir);
    } on FileSystemException {
      return false;
    }
  }

  /// Copies a still out of scratch into the library folder, returning the new
  /// path. Files already inside the library are left where they are.
  String _adoptPreview(String id, String path) {
    if (path.isEmpty || !File(path).existsSync()) return path;

    final dir = Paths.ensureDir(_previewDir);
    if (dir.isEmpty) return path;
    if (_isAdopted(path)) return path;

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

  static int _counter = 0;

  static String _newId() {
    _counter += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '${stamp.substring(stamp.length - 6)}$_counter';
  }
}

/// The actors the user has kept.
///
/// An actor is the expensive part of a good ad: it takes several tries to land
/// a face that reads as real, and once it does it should never have to be found
/// again.
class ActorLibrary extends AssetLibrary {
  ActorLibrary() : super('actors.json', 'actors');

  @override
  String suggestedName() => tr('Actor %1').arg(count + 1);
}

/// The décors the user has kept: the room the ad is filmed in.
class DecorLibrary extends AssetLibrary {
  DecorLibrary() : super('decors.json', 'decors');

  @override
  String suggestedName() => tr('Décor %1').arg(count + 1);
}

/// The optional dials a décor can carry. Not traits in the old sense: a décor
/// is written in words like everything else, and these only pin down the four
/// things a sentence tends to leave vague.
class DecorTweak {
  const DecorTweak(this.key, this.label, this.options);

  final String key;
  final String label;

  /// Label shown, fragment sent.
  final List<(String, String)> options;

  static List<DecorTweak> get all => [
    DecorTweak('light', tr('Light'), [
      (tr('Window daylight'), 'lit only by daylight from a window'),
      (tr('Overcast'), 'flat overcast daylight'),
      (tr('Warm lamps'), 'lit by warm household lamps'),
      (tr('Overhead'), 'lit by a plain overhead ceiling light'),
      (tr('Night'), 'at night, only the lights of the room on'),
    ]),
    DecorTweak('mood', tr('Mood'), [
      (tr('Lived-in'), 'lived-in and a little untidy'),
      (tr('Tidy'), 'tidy but ordinary, nothing staged'),
      (tr('Cosy'), 'cosy and warm'),
      (tr('Cold'), 'bare and slightly cold'),
      (tr('Busy'), 'busy, things going on in the background'),
    ]),
    DecorTweak('time', tr('Time of day'), [
      (tr('Morning'), 'early morning'),
      (tr('Midday'), 'the middle of the day'),
      (tr('Late afternoon'), 'late afternoon'),
      (tr('Evening'), 'the evening'),
    ]),
    DecorTweak('space', tr('Space'), [
      (tr('Indoors'), 'indoors'),
      (tr('Outdoors'), 'outdoors'),
      (tr('In a car'), 'inside a parked car'),
      (tr('Public place'), 'in a public place with people around'),
    ]),
  ];
}
