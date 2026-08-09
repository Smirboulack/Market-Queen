import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/http_util.dart';
import '../core/settings_store.dart';
import '../core/signal.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import 'asset_library.dart';

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
  AdProject(this._settings, this._registry);

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

  /// name, description, audience.
  Map<String, Object?> product = {};

  /// Reference pictures and clips of the product, in the order they were
  /// added. The first picture is the one handed to a model that takes a single
  /// reference.
  final List<String> media = [];

  /// A list, though the interface only fills the first slot today: two actors
  /// in one décor is the next thing this grows into, and a list costs nothing
  /// now against a migration later.
  final List<String> actorIds = [];

  String decorId = '';

  /// The whole ad, written by the user in their own words.
  String script = '';

  String aspectRatio = '9:16';
  bool captions = true;

  /// Whether the ad is allowed to cut away from the actor.
  ///
  /// On, the lines that describe the product are filmed on the product with the
  /// read carrying over them, which is what a real UGC ad does and what stops
  /// this one being thirty seconds of the same face. Off is for the people who
  /// want exactly the take they wrote and nothing else.
  bool broll = true;

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

  void setCaptions(bool value) {
    if (captions == value) return;
    captions = value;
    _touched();
  }

  void setBroll(bool value) {
    if (broll == value) return;
    broll = value;
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

  void setDecor(String id) {
    if (decorId == id) return;
    decorId = id;
    _touched();
  }

  void clearDecor() => setDecor('');

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

  bool get complete => hasProduct && hasScript && hasActor;

  /// What is still missing, in the order it reads best. Shown on the Generate
  /// button, so a disabled button always says why.
  List<String> get missing => [
    if (!hasProduct) tr('a product'),
    if (!hasActor) tr('an actor'),
    if (!hasScript) tr('a scenario'),
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
  /// The actor and the décor are references into the libraries rather than
  /// copies, so editing one from anywhere updates every ad that casts it.
  Map<String, Object?> toRequest({
    required ActorLibrary actors,
    required DecorLibrary decors,
  }) {
    // Model choices live in the preferences the Models page writes, so the
    // studio and that page agree on what "your usual models" means.
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

    final actor = actorIds.isEmpty ? null : actors.byId(actorIds.first);
    final decor = decorId.isEmpty ? null : decors.byId(decorId);

    final images = productImages;

    // The pipeline sizes its shot count from a duration. The ceiling wins when
    // there is one; otherwise the ad lasts exactly as long as its words take,
    // which is the rule the whole studio is built on.
    final duration = maxSeconds > 0
        ? maxSeconds
        : math.max(5, spokenSeconds.round());

    double voice(String key, double fallback) =>
        actor?.extraNumber(key, fallback) ?? fallback;

    return {
      'productName': '${product['name'] ?? ''}'.trim(),
      'productDescription': '${product['description'] ?? ''}'.trim(),
      'audience': '${product['audience'] ?? ''}'.trim(),
      'tone': '',
      // The language the app is being used in. A brief written entirely in
      // French used to come back as an English ad, because "no language set"
      // was read as "English".
      'language': Translator.instance.currentLabel,
      'avatarBrief': actor?.prompt.trim() ?? '',
      'extraInstructions': decorBrief(decors),
      // No scenes any more: the pipeline cuts the user's own script into shots
      // itself, which is the only cutting an authentic UGC ad wants.
      'scenes': const <Map<String, Object?>>[],
      'brollEnabled': broll,
      'script': script.trim(),
      'durationSeconds': duration,
      'aspectRatio': aspectRatio,
      // One image: the pipeline takes a single reference.
      'productImagePath': images.isEmpty ? '' : images.first,
      'actorPortraitPath': actor?.thumbnail ?? '',
      'decorImagePath': decor?.thumbnail ?? '',
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
      'voiceId': actor?.extraText('voiceId') ?? '',
      // What was auditioned has to be what is bought.
      'voiceStability': voice('voiceStability', 0.45),
      'voiceSimilarity': voice('voiceSimilarity', 0.8),
      'voiceStyle': voice('voiceStyle', 0.35),
      'voiceSpeed': voice('voiceSpeed', 1.0),
      'captionsEnabled': captions,
      'captionsProvider': 'openai-whisper',
      'captionsModel': 'whisper-1',
    };
  }

  /// The décor in one sentence: what the user wrote, plus whichever dials they
  /// set. Empty when no décor is cast.
  String decorBrief(DecorLibrary decors) {
    final decor = decorId.isEmpty ? null : decors.byId(decorId);
    if (decor == null) return '';

    final tweaks = decorTweakFragments(decor);
    final description = decor.prompt.trim();

    if (description.isEmpty) return tweaks;
    if (tweaks.isEmpty) return description;
    return '$description, $tweaks';
  }

  /// The set dials of a décor, strung together in the order they are offered.
  static String decorTweakFragments(LibraryAsset decor) {
    final fragments = <String>[];
    for (final tweak in DecorTweak.all) {
      final value = decor.extraText(tweak.key);
      if (value.isNotEmpty) fragments.add(value);
    }
    return fragments.join(', ');
  }

  // ---- Document ----------------------------------------------------------

  Map<String, Object?> toJson() => {
    'product': product,
    'media': media,
    'actorIds': actorIds,
    'decorId': decorId,
    'script': script,
    'aspectRatio': aspectRatio,
    'captions': captions,
    'broll': broll,
    'maxSeconds': maxSeconds,
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

    decorId = '${document['decorId'] ?? ''}';
    script = '${document['script'] ?? ''}';
    aspectRatio = '${document['aspectRatio'] ?? '9:16'}';
    captions = document['captions'] != false;
    // Ads saved before product shots existed were all talking heads by
    // accident, not by choice, so they open with them switched on.
    broll = document['broll'] != false;
    maxSeconds = (document['maxSeconds'] as num?)?.toInt() ?? 0;

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
    decorId = '';
    script = '';
    aspectRatio = '9:16';
    captions = true;
    broll = true;
    maxSeconds = 0;

    notifyListeners();
    requestChanged.emit();
    reloaded.emit();
  }

  /// Drops an actor or a décor that has been deleted from its library, so an ad
  /// never points at something that is gone.
  void forget({String actorId = '', String decorId = ''}) {
    var changed = false;
    if (actorId.isNotEmpty && actorIds.remove(actorId)) changed = true;
    if (decorId.isNotEmpty && this.decorId == decorId) {
      this.decorId = '';
      changed = true;
    }
    if (changed) _touched();
  }
}
