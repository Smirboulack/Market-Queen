import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';
import '../i18n/translator.dart';
import '../providers/voice_profile.dart';

/// The two things that can be cast in an ad.
///
/// They are one shape -- references, a description, a still -- so one library,
/// one gallery and one editor serve both, and every screen that handles either
/// takes this rather than a boolean nobody can read at the call site.
enum AssetKind { actor, scene }

/// One reusable piece of casting: an actor, or a scene.
///
/// Both are the same object -- a name, a description in plain words, the
/// pictures and clips it was described with, and one still to recognise it by.
/// What differs is only what the extras carry: a voice for an actor, the light
/// and the mood for a scene.
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

const _audioExtensions = <String>{
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.flac',
};

/// Whether a reference is a recording. Only the reference video models take
/// one; everywhere else it is neither a picture nor a clip and is skipped.
bool isAudioPath(String path) =>
    _audioExtensions.contains(p.extension(path).toLowerCase());

/// Wider than what the file dialog offers on purpose: this is the test applied
/// to things arriving from outside the app -- a path pasted as text, a file
/// copied out of a browser -- where AVIF and HEIC are as common as PNG, and
/// [imageDataUri] converts either.
const _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp',
  '.tif',
  '.tiff',
  '.avif',
  '.heic',
  '.heif',
};

/// Whether a path names a picture.
///
/// Not the complement of the two above: "neither a clip nor a recording" is
/// what the send path assumes of a reference it has already accepted, which is
/// a different question from whether a stray path is worth accepting at all.
bool isImagePath(String path) =>
    _imageExtensions.contains(p.extension(path).toLowerCase());

/// Whether a path is something the composer can take as a reference.
bool isMediaPath(String path) =>
    isImagePath(path) || isVideoPath(path) || isAudioPath(path);

/// The three things a model can be handed.
///
/// They are not interchangeable and the interface should stop pretending they
/// are: a picture model has nothing to do with a clip, a reference video model
/// counts each kind against its own ceiling, and one button labelled "add
/// references" for all three says none of that.
enum MediaKind { image, video, audio }

MediaKind mediaKindOf(String path) => isVideoPath(path)
    ? MediaKind.video
    : isAudioPath(path)
    ? MediaKind.audio
    : MediaKind.image;

/// A folder of reusable assets on disk.
///
/// Saving copies the still out of the scratch folder into the library's own
/// directory, so clearing scratch can never orphan a saved actor or scene.
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

  /// What an entry saved without a name is called: "Actor 3", "Scene 3".
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

  /// Everything whose name or description matches [query], newest first.
  ///
  /// Substring, case-folded, over both fields: somebody looking for the woman
  /// in the kitchen is as likely to have written that in the description as in
  /// the name.
  List<LibraryAsset> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return assets;
    return [
      for (final asset in _assets)
        if (asset.name.toLowerCase().contains(needle) ||
            asset.prompt.toLowerCase().contains(needle))
          asset,
    ];
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

/// The scenes the user has kept: the place the ad is filmed in.
///
/// Called décors until the interface was rewritten. The file it is stored in
/// keeps the old name, and always will -- renaming a concept is not a reason to
/// lose everybody's library.
class SceneLibrary extends AssetLibrary {
  SceneLibrary() : super('decors.json', 'decors');

  @override
  String suggestedName() => tr('Scene %1').arg(count + 1);
}

/// One appearance of an actor.
///
/// An actor is not a picture. Sarah in a blazer at a desk and Sarah in a hoodie
/// in her kitchen are the same person, and an app that models them as two
/// actors makes the user cast, voice and describe her twice -- then leaves the
/// two copies to drift apart. A look is the picture; the actor is who is in it.
///
/// The default look is the actor's own [LibraryAsset.previewPath], so an actor
/// that never gets a second one costs nothing and behaves exactly as it did
/// before looks existed.
class ActorLook {
  const ActorLook({
    required this.id,
    required this.name,
    required this.path,
    this.prompt = '',
  });

  factory ActorLook.fromJson(Map<String, Object?> json) => ActorLook(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    path: '${json['path'] ?? ''}',
    prompt: '${json['prompt'] ?? ''}',
  );

  final String id;
  final String name;

  /// The still. Adopted into the library folder like any other, so clearing
  /// scratch cannot orphan it.
  final String path;

  /// What was asked for to get it, when it was generated rather than dropped.
  final String prompt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'prompt': prompt,
  };
}

/// Where an actor's looks are kept, and the only place that shape is written.
class ActorLooks {
  ActorLooks._();

  static const key = 'looks';

  static List<ActorLook> of(LibraryAsset actor) {
    final raw = actor.extras[key];
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map) ActorLook.fromJson(entry.cast<String, Object?>()),
    ];
  }

  static void save(LibraryAsset actor, List<ActorLook> looks) {
    actor.setExtra(key, looks.isEmpty ? null : [
      for (final look in looks) look.toJson(),
    ]);
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16);
}

/// How old the actor is and who they read as -- facts about the person, not
/// about the voice.
///
/// They used to be the voice's. An actor's age was `voiceAge`, which is one of
/// three bands ElevenLabs sorts its library into, and their gender was
/// `voiceGender`, which is a search filter -- so changing who was reading the
/// ad changed how old the actor was, and a woman of 22 and a woman of 29 were
/// the same fact. That is backwards: the person is the thing that exists, and
/// which voice suits them is a decision made afterwards and changed freely.
///
/// So the two are separate now, and this is the person's half. [age] is a number
/// of years rather than a band, because "22" is what somebody knows about the
/// actor they just made and "young" is what a voice library needs to be told.
///
/// **Actors saved before the split.** They carry only the voice's values, so
/// both accessors fall back to them: an actor who has never been given a number
/// still reports the band their voice was searched under. Nothing is rewritten
/// on load -- an actor is migrated the first time somebody sets one of these,
/// and until then the old value is the best answer there is.
class ActorIdentity {
  ActorIdentity._();

  static const ageKey = 'actorAge';
  static const genderKey = 'actorGender';

  /// Years, or 0 when nobody has said.
  static int ageOf(LibraryAsset actor) {
    final value = actor.extras[ageKey];
    if (value is num) return value.round();
    return 0;
  }

  static void setAge(LibraryAsset actor, int years) =>
      actor.setExtra(ageKey, years <= 0 ? null : years);

  /// The lowest and highest a person's age is allowed to be here. Not a
  /// judgement about casting: it is what keeps a typo -- 222, or 2 -- out of the
  /// brief the image model is handed.
  static const int minAge = 13;
  static const int maxAge = 99;

  /// `female`, `male`, or empty. The same two values the voice library uses, so
  /// an actor's gender can seed a voice search without translating anything.
  static String genderOf(LibraryAsset actor) {
    final own = actor.extraText(genderKey);
    return own.isNotEmpty ? own : actor.extraText('voiceGender');
  }

  static void setGender(LibraryAsset actor, String value) =>
      actor.setExtra(genderKey, value);

  /// Which of the voice library's three age bands this actor falls in.
  ///
  /// The bands are ElevenLabs' own -- `young`, `middle_aged`, `old` -- and the
  /// boundaries are where a casting director would put them rather than where a
  /// census would: an ad read by a 32-year-old does not sound "young", and 50 is
  /// where a voice starts reading as one with some miles on it.
  ///
  /// Empty when the actor has no age at all, so a filter on the band simply does
  /// not match rather than matching the middle.
  static String bandOf(LibraryAsset actor) {
    final years = ageOf(actor);
    if (years <= 0) return actor.extraText('voiceAge');
    if (years < 30) return 'young';
    if (years < 50) return 'middle_aged';
    return 'old';
  }

  /// The actor in the words a card has room for: "22 · Female".
  static String summary(LibraryAsset actor) {
    final years = ageOf(actor);
    final parts = <String>[
      if (years > 0)
        //: %1 is a whole number of years
        tr('%1 years old').arg(years)
      else
        VoiceTrait.labelFor('voiceAge', actor.extraText('voiceAge')),
      VoiceTrait.labelFor('voiceGender', genderOf(actor)),
    ];
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }
}

/// Who the actor is, as against what they look like and how they sound.
///
/// It is the third leg of the same object -- looks, voice, personality -- and
/// the one with no picture and no audio to show for itself, which is why it
/// used to fall off the screen entirely. It is not decoration: every field here
/// ends up in the brief the script writer is handed, so an actor described as
/// blunt and Gen-Z gets written blunt and Gen-Z rather than written neutral and
/// then read out in a young voice.
class ActorPersona {
  ActorPersona._();

  static const traitsKey = 'personaTraits';
  static const energyKey = 'personaEnergy';
  static const styleKey = 'speakingStyle';

  /// What the actor is doing on camera. Not personality but the same kind of
  /// thing -- a standing instruction about this person rather than about one
  /// shot -- and it is handed to the avatar model as its motion prompt.
  static const actionKey = 'actorAction';

  /// How they come across. Several at once, because nobody is one adjective.
  static List<(String, String)> get tones => [
    (tr('Friendly'), 'friendly'),
    (tr('Confident'), 'confident'),
    (tr('Playful'), 'playful'),
    (tr('Professional'), 'professional'),
    (tr('Warm'), 'warm'),
    (tr('Bold'), 'bold'),
  ];

  /// The register they speak in.
  static List<(String, String)> get styles => [
    (tr('Casual'), 'casual'),
    (tr('Luxury'), 'luxury'),
    (tr('Gen-Z'), 'gen-z'),
    (tr('Expert'), 'expert'),
    (tr('Relatable'), 'relatable'),
  ];

  static List<(String, String)> get all => [...tones, ...styles];

  static String labelFor(String value) {
    for (final option in all) {
      if (option.$2 == value) return option.$1;
    }
    return value;
  }

  static List<String> traitsOf(LibraryAsset actor) {
    final raw = actor.extras[traitsKey];
    if (raw is List) return [for (final entry in raw) '$entry'];
    // A single value from an older save reads as a list of one rather than as
    // nothing at all.
    final single = actor.extraText(traitsKey);
    return single.isEmpty ? const [] : [single];
  }

  static void setTraits(LibraryAsset actor, List<String> values) =>
      actor.setExtra(traitsKey, values.isEmpty ? null : values);

  static void toggleTrait(LibraryAsset actor, String value) {
    final traits = List<String>.of(traitsOf(actor));
    if (!traits.remove(value)) traits.add(value);
    setTraits(actor, traits);
  }

  /// How much they give. Zero is flat and even, one is all energy.
  static double energyOf(LibraryAsset actor) =>
      actor.extraNumber(energyKey, 0.6);

  /// The persona in one sentence, in the words a writer can use. Empty when
  /// nothing was set, so it can be appended to a brief unconditionally.
  static String brief(LibraryAsset actor) {
    final traits = [for (final value in traitsOf(actor)) labelFor(value)];
    final style = actor.extraText(styleKey).trim();
    final energy = actor.extras.containsKey(energyKey)
        ? energyOf(actor)
        : -1.0;

    final parts = <String>[
      if (traits.isNotEmpty) traits.join(', '),
      if (energy >= 0)
        energy > 0.75
            ? tr('high energy')
            : energy < 0.3
            ? tr('low key')
            : tr('even energy'),
      if (style.isNotEmpty) style,
    ];
    return parts.join('. ');
  }
}

/// The optional dials a scene can carry. Not traits in the old sense: a scene
/// is written in words like everything else, and these only pin down the four
/// things a sentence tends to leave vague.
class SceneTweak {
  const SceneTweak(this.key, this.label, this.options);

  final String key;
  final String label;

  /// Label shown, fragment sent.
  final List<(String, String)> options;

  static List<SceneTweak> get all => [
    // "Lighting" rather than "Light": the catalogue is keyed on the English
    // string, and "Light" is already the name of the pale theme. One key
    // cannot be both "Clair" and "Lumière".
    SceneTweak('light', tr('Lighting'), [
      (tr('Window daylight'), 'lit only by daylight from a window'),
      (tr('Overcast'), 'flat overcast daylight'),
      (tr('Warm lamps'), 'lit by warm household lamps'),
      (tr('Overhead'), 'lit by a plain overhead ceiling light'),
      (tr('Night'), 'at night, only the lights of the room on'),
    ]),
    SceneTweak('mood', tr('Mood'), [
      (tr('Lived-in'), 'lived-in and a little untidy'),
      (tr('Tidy'), 'tidy but ordinary, nothing staged'),
      (tr('Cosy'), 'cosy and warm'),
      (tr('Cold'), 'bare and slightly cold'),
      (tr('Busy'), 'busy, things going on in the background'),
    ]),
    SceneTweak('time', tr('Time of day'), [
      (tr('Morning'), 'early morning'),
      (tr('Midday'), 'the middle of the day'),
      (tr('Late afternoon'), 'late afternoon'),
      (tr('Evening'), 'the evening'),
    ]),
    SceneTweak('space', tr('Space'), [
      (tr('Indoors'), 'indoors'),
      (tr('Outdoors'), 'outdoors'),
      (tr('In a car'), 'inside a parked car'),
      (tr('Public place'), 'in a public place with people around'),
    ]),
  ];
}
