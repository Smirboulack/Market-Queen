import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/paths.dart';
import '../core/settings_store.dart';
import '../core/signal.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import 'scene_model.dart';

/// The ad being built.
///
/// Every panel of the studio reads and writes this one object, so the actor
/// rail, the cost estimate and the Generate button always describe the same
/// thing rather than three snapshots of a form. It autosaves to the config
/// directory, so closing the app halfway through a build loses nothing.
///
/// There is deliberately no duration field: an ad lasts exactly as long as its
/// words take to say. [spokenSeconds] derives it from the script.
class AdProject extends ChangeNotifier {
  AdProject(this._settings, this._registry) {
    // The scene model owns its own edits; the project only has to notice them.
    scenes.addListener(() {
      notifyListeners();
      requestChanged.emit();
    });
    scenes.dirtied.addListener(_touch);

    _load();
  }

  // Same figure the script writer uses to size a script, so the duration shown
  // while writing matches the one the pipeline plans against.
  static const _wordsPerSecond = 2.6;

  // Long enough that a burst of keystrokes writes once, short enough that the
  // draft on disk is never far behind what is on screen.
  static const _autosaveDelay = Duration(milliseconds: 400);

  final SettingsStore _settings;
  final Registry _registry;

  final SceneModel scenes = SceneModel();

  /// Anything that changes the ad changes what Generate would run, so the
  /// estimate re-prices itself without every setter having to remember.
  final Signal requestChanged = Signal();

  // Text fields lose their binding the moment the user types in them, so any
  // change made behind their back has to be announced rather than inferred.
  final Signal cleared = Signal();
  final Signal actorReset = Signal();

  Timer? _autosave;
  bool _loading = false;

  /// name, description, audience, images (List&lt;String&gt;).
  Map<String, Object?> product = {};

  /// name, brief, decor, traits, portraitPath, voice.
  Map<String, Object?> actor = {};

  /// Kept only so a draft written before scenes existed still opens with its
  /// words intact; the first edit turns it into scenes.
  String script = '';
  String aspectRatio = '9:16';
  bool captions = true;

  /// The length the ad is *aiming* for, in seconds, or 0 for "as long as the
  /// words take".
  ///
  /// It never truncates anything: an ad lasts exactly as long as its script, and
  /// this only gives the editor something to say when the script has run past
  /// what the format wants.
  int targetSeconds = 0;

  @override
  void dispose() {
    _autosave?.cancel();
    scenes.dispose();
    super.dispose();
  }

  // ---- Fields -----------------------------------------------------------

  void setProductField(String key, Object? value) {
    if (product[key] == value) return;
    product[key] = value;
    notifyListeners();
    requestChanged.emit();
    _touch();
  }

  void setActorField(String key, Object? value) {
    if (actor[key] == value) return;
    actor[key] = value;
    notifyListeners();
    requestChanged.emit();
    _touch();
  }

  void setScript(String value) {
    if (script == value) return;
    script = value;
    notifyListeners();
    requestChanged.emit();
    _touch();
  }

  void setAspectRatio(String value) {
    if (aspectRatio == value) return;
    aspectRatio = value;
    notifyListeners();
    requestChanged.emit();
    _touch();
  }

  void setCaptions(bool value) {
    if (captions == value) return;
    captions = value;
    notifyListeners();
    requestChanged.emit();
    _touch();
  }

  void setTargetSeconds(int value) {
    if (targetSeconds == value) return;
    targetSeconds = value;
    notifyListeners();
    _touch();
  }

  // ---- Reference images -------------------------------------------------
  //
  // `target` is "product" or "actor" -- the two lists behave identically, so
  // they share one implementation and one widget. Several are allowed: the user
  // is billed by their own provider, so there is no reason for us to cap it.
  // Index 0 is the primary, the one the models get when only a single reference
  // can be passed.

  List<String> imagesFor(String target) {
    final owner = target == 'actor' ? actor : product;
    final key = target == 'actor' ? 'referenceImages' : 'images';
    final value = owner[key];
    return value is List ? [for (final entry in value) '$entry'] : <String>[];
  }

  void _setImages(String target, List<String> images) {
    final owner = target == 'actor' ? actor : product;
    final key = target == 'actor' ? 'referenceImages' : 'images';
    owner[key] = images;
    notifyListeners();
    requestChanged.emit();
    _touch();
  }

  void addImages(String target, List<String> paths) {
    // A multi-select dialog or a multi-file drop arrives all at once; adding
    // them one notification at a time would rebuild the grid once per file.
    final images = imagesFor(target);
    final before = images.length;

    for (final raw in paths) {
      final path = Http.toLocalPath(raw);
      if (path.isNotEmpty && !images.contains(path)) images.add(path);
    }

    if (images.length == before) return;
    _setImages(target, images);
  }

  void removeImage(String target, int index) {
    final images = imagesFor(target);
    if (index < 0 || index >= images.length) return;
    images.removeAt(index);
    _setImages(target, images);
  }

  void setPrimaryImage(String target, int index) {
    final images = imagesFor(target);
    if (index <= 0 || index >= images.length) return;
    images.insert(0, images.removeAt(index));
    _setImages(target, images);
  }

  /// Loads a saved actor over the current one, portrait and voice included.
  ///
  /// Wholesale, not merged: loading a saved actor should give exactly the actor
  /// that was saved, not a blend with whatever was half-typed before.
  void applyActor(Map<String, Object?> saved) {
    if (saved.isEmpty) return;
    actor = Map<String, Object?>.of(saved);
    notifyListeners();
    requestChanged.emit();
    actorReset.emit();
    _touch();
  }

  /// Starts casting again from nothing, leaving the product and the script
  /// alone. What "New actor" does.
  void newActor() {
    actor = {};
    notifyListeners();
    requestChanged.emit();
    actorReset.emit();
    _touch();
  }

  void clear() {
    product = {};
    actor = {};
    scenes.setList(const []);
    script = '';
    aspectRatio = '9:16';
    captions = true;
    targetSeconds = 0;

    notifyListeners();
    requestChanged.emit();
    cleared.emit();
    _touch();
  }

  /// Applies a director's answer to the scenes, leaving every line alone.
  void applyDirection(List<Map<String, Object?>> shots) =>
      scenes.applyDirection(shots);

  /// Every line, joined: what the voice-over says in one take.
  String spokenScript() =>
      scenes.count > 0 ? scenes.spokenScript : script.trim();

  // ---- Readiness ---------------------------------------------------------
  //
  // There is no wizard any more: everything is on one screen and can be filled
  // in in any order. What used to be "which step are you allowed to reach" is
  // now just "what is still missing before Generate means anything".

  bool get hasProduct => '${product['name'] ?? ''}'.trim().isNotEmpty;

  /// A description is not an actor: the ad needs a picture, cast or promoted
  /// from the user's own photos.
  bool get hasActor => '${actor['portraitPath'] ?? ''}'.trim().isNotEmpty;

  /// A draft written before scenes existed still counts as having words.
  bool get hasScript => scenes.hasSpokenLine || script.trim().isNotEmpty;

  bool get complete => hasProduct && hasActor && hasScript;

  /// What is still missing, in the order it reads best. Shown on the Generate
  /// button so a disabled button always says why.
  List<String> get missing => [
        if (!hasProduct) tr('a product'),
        if (!hasActor) tr('an actor'),
        if (!hasScript) tr('a line to say'),
      ];

  double get spokenSeconds {
    if (scenes.count > 0) return scenes.totalSeconds;

    // A draft written before scenes existed.
    final text = script.trim();
    if (text.isEmpty) return 0.0;
    return text.split(RegExp(r'\s+')).length / _wordsPerSecond;
  }

  // ---- Adapter onto the pipeline ----------------------------------------

  /// The request shape the pipeline understands.
  Map<String, Object?> toRequest() {
    // Model choices still live in the preferences the pickers write, so the
    // studio and the settings page agree on what "your usual models" means.
    String pickedProvider(String category) {
      final saved = _settings.prefString('${category}Provider');
      return saved.isEmpty ? _registry.defaultProvider(category) : saved;
    }

    String pickedModel(String category, String providerId) {
      final saved = _settings.prefString('${category}Model');
      if (saved.isNotEmpty) return saved;
      return _registry.provider(providerId)?.defaultModel ?? '';
    }

    final textProvider = pickedProvider('text');
    final imageProvider = pickedProvider('image');
    final avatarProvider = pickedProvider('avatar');
    final videoProvider = pickedProvider('video');
    final voiceProvider = pickedProvider('voice');

    final images = imagesFor('product');

    // The pipeline sizes its shot count from a duration. We no longer ask for
    // one, so we hand it the length of the script instead -- which is the rule
    // the whole studio is built on.
    final duration = math.max(5, spokenSeconds.round());

    double setting(String key, double fallback) {
      final value = actor[key];
      return value is num ? value.toDouble() : fallback;
    }

    return {
      'productName': '${product['name'] ?? ''}'.trim(),
      'productDescription': '${product['description'] ?? ''}'.trim(),
      'audience': '${product['audience'] ?? ''}'.trim(),
      'tone': '${actor['tone'] ?? ''}',
      'language': '${actor['language'] ?? ''}',
      'avatarBrief': '${actor['brief'] ?? ''}'.trim(),
      'extraInstructions': '${actor['decor'] ?? ''}'.trim(),
      // Both: `scenes` is what the pipeline cuts on, `script` is the same words
      // in one piece for the single voice-over take.
      'scenes': scenes.toList(),
      'script': spokenScript(),
      'durationSeconds': duration,
      'aspectRatio': aspectRatio,
      // One image for now: the pipeline takes a single reference.
      'productImagePath': images.isEmpty ? '' : images.first,
      'actorPortraitPath': '${actor['portraitPath'] ?? ''}',
      'useProductPhotoAsFrame': false,
      'textProvider': textProvider,
      'textModel': pickedModel('text', textProvider),
      'imageProvider': imageProvider,
      'imageModel': pickedModel('image', imageProvider),
      'avatarProvider': avatarProvider,
      'avatarModel': pickedModel('avatar', avatarProvider),
      'videoProvider': videoProvider,
      'videoModel': pickedModel('video', videoProvider),
      'voiceProvider': voiceProvider,
      'voiceModel': pickedModel('voice', voiceProvider),
      'voiceId': '${actor['voiceId'] ?? ''}',
      // What was auditioned has to be what is bought.
      'voiceStability': setting('voiceStability', 0.45),
      'voiceSimilarity': setting('voiceSimilarity', 0.8),
      'voiceStyle': setting('voiceStyle', 0.35),
      'voiceSpeed': setting('voiceSpeed', 1.0),
      'captionsEnabled': captions,
      'captionsProvider': 'openai-whisper',
      'captionsModel': 'whisper-1',
    };
  }

  // ---- Draft persistence ------------------------------------------------

  String get _draftFile => p.join(Paths.configDir, 'draft.json');

  void _touch() {
    if (_loading) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, _save);
  }

  void _save() {
    if (Paths.ensureDir(Paths.configDir).isEmpty) return;

    final root = {
      'schemaVersion': 4,
      'product': product,
      'actor': actor,
      'scenes': scenes.toList(),
      'script': script,
      'aspectRatio': aspectRatio,
      'captions': captions,
      'targetSeconds': targetSeconds,
    };

    try {
      File(_draftFile)
          .writeAsStringSync(const JsonEncoder.withIndent('    ').convert(root));
    } on FileSystemException {
      // The next edit tries again.
    }
  }

  void _load() {
    final file = File(_draftFile);
    if (!file.existsSync()) return;

    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Exception {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded.isEmpty) return;

    _loading = true;

    final savedProduct = decoded['product'];
    if (savedProduct is Map) product = savedProduct.cast<String, Object?>();

    final savedActor = decoded['actor'];
    if (savedActor is Map) actor = savedActor.cast<String, Object?>();

    final savedScenes = decoded['scenes'];
    if (savedScenes is List) scenes.setList(savedScenes);

    script = '${decoded['script'] ?? ''}';
    aspectRatio = '${decoded['aspectRatio'] ?? '9:16'}';
    captions = decoded['captions'] != false;
    // Drafts written by the wizard build carry a `currentStep` there is nowhere
    // to put any more; it is simply dropped on the next save.
    targetSeconds = (decoded['targetSeconds'] as num?)?.toInt() ?? 0;

    _loading = false;
    notifyListeners();
    requestChanged.emit();
  }
}
