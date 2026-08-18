import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/http_util.dart';
import '../core/settings_store.dart';
import '../core/signal.dart';
import '../i18n/translator.dart';
import '../providers/capabilities.dart';
import '../providers/registry.dart';
import '../providers/voice_profile.dart';
import 'asset_library.dart';
import 'canvas_feed.dart';

/// The ad being edited: one UGC spot, inside one project.
///
/// There is exactly one of these alive at a time -- the [Workspace] loads an ad
/// into it when you open one and reads it back out when it changes, the way an
/// editor holds one open document. Everything on the canvas reads and writes
/// this object, so the estimate and the Generate button always describe the
/// same thing rather than two snapshots of a form.
///
/// It is deliberately flat. There are no scenes: a UGC ad is one continuous
/// take of one person talking, and cutting it into beats on the way in only
/// ever made it look like an advert.
class AdProject extends ChangeNotifier {
  AdProject(this._settings, this._registry) {
    // Everything the canvas produced is part of the document, so a new tile has
    // to dirty the ad the same way a keystroke does.
    feed.addListener(_touched);
  }

  // Rough speaking pace, the same figure the pipeline plans against, so the
  // duration shown while writing matches the one the ad runs to.
  static const _wordsPerSecond = 2.6;

  final SettingsStore _settings;
  final Registry _registry;

  /// Anything that changes the ad changes what Generate would run, so the
  /// estimate re-prices itself without every setter having to remember.
  final Signal requestChanged = Signal();

  /// Raised when a different ad has been loaded in. Text fields hold their own
  /// contents once the user is typing, so a change made behind their back has
  /// to be announced rather than inferred.
  final Signal reloaded = Signal();

  /// Which ad this is, so the workspace knows where to write it back.
  String id = '';
  String projectId = '';
  String name = '';

  /// Everything this ad has generated, in the order it was asked for.
  ///
  /// The canvas is the studio now, so its contents are the ad as much as the
  /// scenario is. It saves and reopens with the rest of the document.
  final CanvasFeed feed = CanvasFeed();

  /// name, description, audience.
  ///
  /// No longer collected anywhere in the interface -- the block that used to
  /// ask for it is gone, on the grounds that somebody opening an ad studio is
  /// already advertising something and being made to fill in a form saying so
  /// twice is not a step. It stays on the model because the writer and the
  /// pricing still read it, and because ads saved before the change carry it.
  Map<String, Object?> product = {};

  /// Reference pictures and clips of the product, in the order they were
  /// added. The first picture is the one handed to a model that takes a single
  /// reference.
  final List<String> media = [];

  /// A list, though the interface only fills the first slot today: two actors
  /// in one scene is the next thing this grows into, and a list costs nothing
  /// now against a migration later.
  final List<String> actorIds = [];

  /// The scene the ad is filmed in. Written to the document under its old
  /// name, `decorId`, because renaming the idea is not a reason to lose the
  /// scene off every ad already saved.
  String sceneId = '';

  /// The whole ad, written by the user in their own words.
  String script = '';

  String aspectRatio = '9:16';

  /// The length the ad must not run past, in seconds, or 0 for "as long as the
  /// words take". It is a ceiling for planning, never a cut.
  int maxSeconds = 0;

  // ---- Fields -----------------------------------------------------------

  void _touched() {
    notifyListeners();
    requestChanged.emit();
  }

  void setProductField(String key, Object? value) {
    if (product[key] == value) return;
    product[key] = value;
    _touched();
  }

  void setScript(String value) {
    if (script == value) return;
    script = value;
    _touched();
  }

  void setAspectRatio(String value) {
    if (aspectRatio == value) return;
    aspectRatio = value;
    _touched();
  }

  void setMaxSeconds(int value) {
    if (maxSeconds == value) return;
    maxSeconds = value;
    _touched();
  }

  void setActor(String actorId) {
    if (actorIds.length == 1 && actorIds.first == actorId) return;
    actorIds
      ..clear()
      ..add(actorId);
    _touched();
  }

  void clearActor() {
    if (actorIds.isEmpty) return;
    actorIds.clear();
    _touched();
  }

  void setScene(String id) {
    if (sceneId == id) return;
    sceneId = id;
    _touched();
  }

  void clearScene() => setScene('');

  // ---- Reference media --------------------------------------------------
  //
  // As many as the user likes: they are billed by their own provider, so there
  // is no reason for us to cap it.

  /// The pictures among the references -- what a model can actually be handed.
  List<String> get productImages => [
    for (final path in media)
      if (!isVideoPath(path)) path,
  ];

  void addMedia(List<String> paths) {
    // A multi-select dialog or a multi-file drop arrives all at once; adding
    // them one notification at a time would rebuild the grid once per file.
    final before = media.length;

    for (final raw in paths) {
      final path = Http.toLocalPath(raw);
      if (path.isNotEmpty && !media.contains(path)) media.add(path);
    }

    if (media.length == before) return;
    _touched();
  }

  void removeMedia(int index) {
    if (index < 0 || index >= media.length) return;
    media.removeAt(index);
    _touched();
  }

  void setPrimaryMedia(int index) {
    if (index <= 0 || index >= media.length) return;
    media.insert(0, media.removeAt(index));
    _touched();
  }

  // ---- Readiness ---------------------------------------------------------
  //
  // Every field is optional and can be filled in in any order. What used to be
  // "which step are you allowed to reach" is now only "what is still missing
  // before Generate means anything".

  bool get hasProduct => '${product['name'] ?? ''}'.trim().isNotEmpty;

  bool get hasScript => script.trim().isNotEmpty;

  bool get hasActor => actorIds.isNotEmpty;

  /// Two things, not three. The product used to be one of them; it was dropped
  /// with the panel that asked for it, because an ad with a scenario and an
  /// actor is an ad that can be shot, and nothing downstream ever refused to
  /// run for want of a product name.
  bool get complete => hasScript && hasActor;

  /// What is still missing, in the order it reads best. Shown on the send
  /// button, so a disabled one always says why.
  List<String> get missing => [
    if (!hasActor) tr('an actor'),
    if (!hasScript) tr('a script'),
  ];

  /// How long the written ad takes to say.
  double get spokenSeconds {
    final text = script.trim();
    if (text.isEmpty) return 0.0;
    return text.split(RegExp(r'\s+')).length / _wordsPerSecond;
  }

  /// Whether the script has run past the ceiling the user set.
  bool get overLength => maxSeconds > 0 && spokenSeconds > maxSeconds;

  // ---- Adapter onto the pipeline ----------------------------------------

  /// The request shape the pipeline, the pricer and the writing helpers all
  /// understand.
  ///
  /// The actor and the scene are references into the libraries rather than
  /// copies, so editing one from anywhere updates every ad that casts it.
  Map<String, Object?> toRequest({
    required ActorLibrary actors,
    required SceneLibrary scenes,
  }) {
    // Model choices live in the preferences the Models page writes, so the
    // studio and that page agree on what "your usual models" means.
    String pickedProvider(String category) => _registry.providerOrDefault(
          category,
          _settings.prefString('${category}Provider'),
        );

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

    final actor = actorIds.isEmpty ? null : actors.byId(actorIds.first);
    final scene = sceneId.isEmpty ? null : scenes.byId(sceneId);

    final images = productImages;

    // The pipeline sizes its shot count from a duration. The ceiling wins when
    // there is one; otherwise the ad lasts exactly as long as its words take,
    // which is the rule the whole studio is built on.
    final duration = maxSeconds > 0
        ? maxSeconds
        : math.max(5, spokenSeconds.round());

    double voice(String key, double fallback) =>
        actor?.extraNumber(key, fallback) ?? fallback;

    // The ad's own name names the run folder when no product does -- nobody
    // finds "20260810-143002-" again. It is kept apart from the product name
    // rather than standing in for it: an ad called "Boss Bottled" whose product
    // field was never filled in used to reach the image model as a thing the
    // actor is holding, and came back as six frames of somebody waving a
    // perfume bottle through a script about a dating app.
    final productName = '${product['name'] ?? ''}'.trim();

    return {
      'productName': productName,
      'runLabel': productName.isEmpty ? name.trim() : productName,
      'productDescription': '${product['description'] ?? ''}'.trim(),
      'audience': '${product['audience'] ?? ''}'.trim(),
      'tone': '',
      // The language the app is being used in. A brief written entirely in
      // French used to come back as an English ad, because "no language set"
      // was read as "English".
      'language': Translator.instance.currentLabel,
      'avatarBrief': actor?.prompt.trim() ?? '',
      // The standing instruction for how this actor moves. The avatar model
      // takes it as the motion for the take.
      'actorAction': actor == null ? '' : ActorAction.of(actor),
      'extraInstructions': sceneBrief(scenes),
      // No scenes any more: the pipeline cuts the user's own script into shots
      // itself, which is the only cutting an authentic UGC ad wants.
      'scenes': const <Map<String, Object?>>[],
      'script': script.trim(),
      'durationSeconds': duration,
      'aspectRatio': aspectRatio,
      // One image: the pipeline takes a single reference.
      'productImagePath': images.isEmpty ? '' : images.first,
      'actorPortraitPath': actor?.thumbnail ?? '',
      'decorImagePath': scene?.thumbnail ?? '',
      'useProductPhotoAsFrame': false,
      'textProvider': textProvider,
      'textModel': pickedModel('text', textProvider),
      'imageProvider': imageProvider,
      'imageModel': pickedModel('image', imageProvider),
      // The frame, decided here rather than read out of the settings by
      // whoever needs it: the estimate priced the picture shelf's default
      // frame while the run bought the saved one, which is the same picture
      // quoted at an eighth of what it cost.
      'imageSize': ImageCapabilities.of(pickedModel('image', imageProvider))
          .frameFor(_settings.prefString('imageSize'), aspectRatio),
      'imageQuality': ImageCapabilities.of(pickedModel('image', imageProvider))
          .qualityOr(_settings.prefString('imageQuality')),
      'avatarProvider': avatarProvider,
      'avatarModel': pickedModel('avatar', avatarProvider),
      'videoProvider': videoProvider,
      'videoModel': pickedModel('video', videoProvider),
      'voiceProvider': voiceProvider,
      'voiceModel': pickedModel('voice', voiceProvider),
      // The voice the actor was cast with, and the brief it was cast from. The
      // owner travels with the id because a library voice has to be put on the
      // account before it can speak, and the pipeline may be the first to use
      // it. With no voice chosen, the brief is searched and the best match
      // reads the ad.
      'voiceId': actor?.extraText('voiceId') ?? '',
      'voiceOwner': actor?.extraText('voiceOwner') ?? '',
      'voiceName': actor?.extraText('voiceName') ?? '',
      for (final key in VoiceProfile.keys) key: actor?.extraText(key) ?? '',
      // What was auditioned has to be what is bought.
      'voiceStability': voice('voiceStability', 0.45),
      'voiceSimilarity': voice('voiceSimilarity', 0.8),
      'voiceStyle': voice('voiceStyle', 0.35),
      'voiceSpeed': voice('voiceSpeed', 1.0),
    };
  }

  /// The scene in one sentence: what the user wrote, plus whichever dials they
  /// set. Empty when no scene is cast.
  String sceneBrief(SceneLibrary scenes) {
    final scene = sceneId.isEmpty ? null : scenes.byId(sceneId);
    if (scene == null) return '';

    final tweaks = sceneTweakFragments(scene);
    final description = scene.prompt.trim();

    if (description.isEmpty) return tweaks;
    if (tweaks.isEmpty) return description;
    return '$description, $tweaks';
  }

  /// The set dials of a scene, strung together in the order they are offered.
  static String sceneTweakFragments(LibraryAsset scene) {
    final fragments = <String>[];
    for (final tweak in SceneTweak.all) {
      final value = scene.extraText(tweak.key);
      if (value.isNotEmpty) fragments.add(value);
    }
    return fragments.join(', ');
  }

  // ---- Document ----------------------------------------------------------

  Map<String, Object?> toJson() => {
    'product': product,
    'media': media,
    'actorIds': actorIds,
    'decorId': sceneId,
    'script': script,
    'aspectRatio': aspectRatio,
    'maxSeconds': maxSeconds,
    'feed': feed.toJson(),
  };

  /// Opens a document. Wholesale, not merged: opening an ad has to give exactly
  /// the ad that was saved.
  void load({
    required String id,
    required String projectId,
    required String name,
    required Map<String, Object?> document,
  }) {
    this.id = id;
    this.projectId = projectId;
    this.name = name;

    final savedProduct = document['product'];
    product = savedProduct is Map
        ? savedProduct.cast<String, Object?>()
        : <String, Object?>{};

    final savedMedia = document['media'];
    media
      ..clear()
      ..addAll([
        if (savedMedia is List)
          for (final entry in savedMedia) '$entry',
      ]);

    final savedActors = document['actorIds'];
    actorIds
      ..clear()
      ..addAll([
        if (savedActors is List)
          for (final entry in savedActors)
            if ('$entry'.isNotEmpty) '$entry',
      ]);

    sceneId = '${document['decorId'] ?? ''}';
    script = '${document['script'] ?? ''}';
    aspectRatio = '${document['aspectRatio'] ?? '9:16'}';
    maxSeconds = (document['maxSeconds'] as num?)?.toInt() ?? 0;
    feed.load(document['feed']);

    notifyListeners();
    requestChanged.emit();
    reloaded.emit();
  }

  /// Nothing open. What the studio holds while you are picking a project.
  void close() {
    id = '';
    projectId = '';
    name = '';
    product = {};
    media.clear();
    actorIds.clear();
    sceneId = '';
    script = '';
    aspectRatio = '9:16';
    maxSeconds = 0;
    feed.clear();

    notifyListeners();
    requestChanged.emit();
    reloaded.emit();
  }

  @override
  void dispose() {
    feed.removeListener(_touched);
    feed.dispose();
    super.dispose();
  }

  /// Drops an actor or a scene that has been deleted from its library, so an ad
  /// never points at something that is gone.
  void forget({String actorId = '', String sceneId = ''}) {
    var changed = false;
    if (actorId.isNotEmpty && actorIds.remove(actorId)) changed = true;
    if (sceneId.isNotEmpty && this.sceneId == sceneId) {
      this.sceneId = '';
      changed = true;
    }
    if (changed) _touched();
  }
}
