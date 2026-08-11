import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/paths.dart';

/// What one fal.ai model actually accepts, read from the model's own OpenAPI
/// schema.
///
/// Every endpoint on fal declares its inputs, and they disagree wildly: Kling
/// v3 takes `start_image_url` and a duration of `"5"`, Wan 2.7 takes `image_url`
/// and a duration of `5`, Veo 3.1 wants `"8s"`, Seedance offers `"auto"`, and
/// only some of them have a `resolution` or a `generate_audio` at all.
///
/// The studio used to guess at all of this by looking for substrings in the
/// model id, which produced two kinds of failure: options that were never
/// offered because we did not know they existed, and fields sent to models that
/// reject unknown fields outright. Asking the model is both correct and free.
@immutable
class FalCapabilities {
  const FalCapabilities({
    this.durations = const [],
    this.defaultDuration = '',
    this.durationIsNumber = false,
    this.resolutions = const [],
    this.defaultResolution = '',
    this.aspectRatios = const [],
    this.audioField = '',
    this.defaultAudio = true,
    this.imageField = '',
    this.imagesField = '',
    this.videosField = '',
    this.audiosField = '',
    this.imagesMax = 0,
    this.videosMax = 0,
    this.audiosMax = 0,
    this.known = false,
  });

  /// The exact tokens the model's `duration` enum lists, in its own spelling.
  /// Sent back verbatim, because "8s" and 8 are not interchangeable.
  final List<String> durations;
  final String defaultDuration;

  /// Whether `duration` is declared as a number rather than a string.
  final bool durationIsNumber;

  final List<String> resolutions;
  final String defaultResolution;

  /// Empty when the model has no aspect-ratio input -- Kling v3 has none, and
  /// sending one is an error rather than a no-op.
  final List<String> aspectRatios;

  /// The name of the "make sound too" switch, or empty when the model has no
  /// such thing. It is `generate_audio` on most and `enable_audio` on a few.
  final String audioField;
  final bool defaultAudio;

  /// What the opening frame is called here.
  final String imageField;

  /// The list inputs of a multimodal endpoint, when it has them.
  ///
  /// A reference model is a different animal from an image-to-video one: it has
  /// no opening frame at all. It takes up to fifty files across the three
  /// modalities, and the prompt addresses them by handle -- `@Image1`,
  /// `@Video1`, `@Audio1`. That is what makes it possible to hand it a real ad
  /// and a new face and ask for the same ad with that face in it.
  ///
  /// Empty for every ordinary model, so the caller can tell the two apart
  /// without a table of model ids.
  final String imagesField;
  final String videosField;
  final String audiosField;

  /// How many of each the endpoint will take, off its own `maxItems`.
  ///
  /// They differ by a lot -- one model takes nine pictures and three clips,
  /// the next takes four and one -- and the only place that number was written
  /// down was the rejection that came back after the upload. Zero means the
  /// schema did not say, and the caller falls back to fal's platform ceiling.
  final int imagesMax;
  final int videosMax;
  final int audiosMax;

  /// False when no schema could be read -- the caller then falls back to what
  /// it did before rather than pretending the model has no options.
  final bool known;

  bool get supportsAudio => audioField.isNotEmpty;

  /// Whether this endpoint takes reference material rather than a first frame.
  bool get takesReferences =>
      imagesField.isNotEmpty || videosField.isNotEmpty || audiosField.isNotEmpty;

  // fal's own platform ceilings, which apply on top of whatever a model
  // declares. They live here rather than in the runner because the bar has to
  // draw the same numbers the send path enforces -- a counter that says 0/30
  // over a request that is trimmed at 9 is worse than no counter.
  static const platformMaxImages = 30;
  static const platformMaxVideos = 10;
  static const platformMaxAudios = 10;

  static const maxImageBytes = 30 * 1024 * 1024;
  static const maxVideoBytes = 200 * 1024 * 1024;
  static const maxAudioBytes = 15 * 1024 * 1024;

  /// How many of each modality this endpoint takes: what it declared, capped by
  /// the platform, and zero for a list it does not have at all.
  ({int images, int videos, int audios}) get referenceLimits => (
    images: _limit(imagesField, imagesMax, platformMaxImages),
    videos: _limit(videosField, videosMax, platformMaxVideos),
    audios: _limit(audiosField, audiosMax, platformMaxAudios),
  );

  static int _limit(String field, int declared, int ceiling) {
    if (field.isEmpty) return 0;
    if (declared <= 0) return ceiling;
    return declared < ceiling ? declared : ceiling;
  }

  /// The seconds a duration token stands for, for pricing and planning.
  /// Returns 0 for "auto" and anything unparseable.
  static int secondsOf(String token) {
    final digits = RegExp(r'\d+').firstMatch(token);
    return digits == null ? 0 : int.parse(digits.group(0)!);
  }

  /// The token closest to [seconds] that this model will accept.
  ///
  /// Asking Hailuo for 8 seconds when it offers 6 and 10 has to resolve to one
  /// of the two rather than being sent as-is and rejected. "auto" is never
  /// chosen by proximity -- it is only used when it is the only thing on offer.
  String durationFor(int seconds) {
    if (durations.isEmpty) return '';

    var best = '';
    var bestGap = 1 << 30;
    for (final token in durations) {
      final value = secondsOf(token);
      if (value == 0) continue;
      final gap = (value - seconds).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = token;
      }
    }
    if (best.isNotEmpty) return best;
    return defaultDuration.isEmpty ? durations.first : defaultDuration;
  }

  /// The value the settings column should start from: what the model itself
  /// defaults to, or the first thing it offers.
  String get firstResolution => resolutions.isEmpty
      ? ''
      : (resolutions.contains(defaultResolution)
            ? defaultResolution
            : resolutions.first);

  /// Everything this model wants for one clip, in its own spelling.
  ///
  /// Returned rather than built at each call site so the composer's preview,
  /// the runner and the pipeline cannot disagree about what will be sent.
  ({String imageField, Map<String, Object?> input}) videoInput({
    required int seconds,
    String resolution = '',
    bool audio = true,
    String aspectRatio = '',
  }) {
    final input = <String, Object?>{};

    final token = durationFor(seconds);
    if (token.isNotEmpty) {
      input['duration'] = durationIsNumber ? secondsOf(token) : token;
    }
    if (resolutions.contains(resolution)) {
      input['resolution'] = resolution;
    }
    if (audioField.isNotEmpty) {
      input[audioField] = audio;
    }
    // Only when the model declares one: Kling v3 has no aspect ratio at all,
    // and sending it there is an error rather than a no-op.
    if (aspectRatios.contains(aspectRatio)) {
      input['aspect_ratio'] = aspectRatio;
    }

    return (imageField: imageField, input: input);
  }

  /// Bumped whenever a new field is read out of the schema. A cache written by
  /// an older build knows nothing about it, and silently answering "this model
  /// takes no references" for a fortnight is worse than one extra fetch.
  static const cacheVersion = 3;

  Map<String, Object?> toJson() => {
    'v': cacheVersion,
    'durations': durations,
    'defaultDuration': defaultDuration,
    'durationIsNumber': durationIsNumber,
    'resolutions': resolutions,
    'defaultResolution': defaultResolution,
    'aspectRatios': aspectRatios,
    'audioField': audioField,
    'defaultAudio': defaultAudio,
    'imageField': imageField,
    'imagesField': imagesField,
    'videosField': videosField,
    'audiosField': audiosField,
    'imagesMax': imagesMax,
    'videosMax': videosMax,
    'audiosMax': audiosMax,
  };

  factory FalCapabilities.fromJson(Map<String, Object?> json) {
    List<String> list(Object? value) => [
      if (value is List)
        for (final entry in value) '$entry',
    ];

    return FalCapabilities(
      durations: list(json['durations']),
      defaultDuration: '${json['defaultDuration'] ?? ''}',
      durationIsNumber: json['durationIsNumber'] == true,
      resolutions: list(json['resolutions']),
      defaultResolution: '${json['defaultResolution'] ?? ''}',
      aspectRatios: list(json['aspectRatios']),
      audioField: '${json['audioField'] ?? ''}',
      defaultAudio: json['defaultAudio'] != false,
      imageField: '${json['imageField'] ?? ''}',
      imagesField: '${json['imagesField'] ?? ''}',
      videosField: '${json['videosField'] ?? ''}',
      audiosField: '${json['audiosField'] ?? ''}',
      imagesMax: (json['imagesMax'] as num?)?.toInt() ?? 0,
      videosMax: (json['videosMax'] as num?)?.toInt() ?? 0,
      audiosMax: (json['audiosMax'] as num?)?.toInt() ?? 0,
      known: true,
    );
  }
}

/// Reads and remembers those schemas.
///
/// One fetch per model, ever: the answer is written next to the settings and
/// re-read on the next launch. A model whose schema cannot be fetched -- no
/// network, a delisted endpoint -- is remembered as unknown for the session
/// only, so it is tried again next time rather than being written off.
class FalSchemas extends ChangeNotifier {
  /// Schemas change when a provider ships a new revision of a model, which is
  /// rare but does happen; a fortnight is often enough to catch it and seldom
  /// enough that nobody waits on the network.
  static const _life = Duration(days: 14);

  final Map<String, FalCapabilities> _memory = {};

  /// The fetch running for each endpoint, so a second caller joins it rather
  /// than starting another one -- or, for [ensure], waits on it.
  final Map<String, Future<void>> _inFlight = {};

  /// Only fal endpoints have a schema to read. Everything else is left to its
  /// provider's own defaults.
  static bool handles(String providerId) =>
      providerId.startsWith('fal-') || providerId == 'fal-upscale';

  /// What we know about [endpointId] right now.
  ///
  /// Never blocks: an unread schema comes back unknown and starts a fetch,
  /// which notifies listeners when it lands. A settings panel that reads this
  /// in `build` therefore fills itself in a moment later without doing anything
  /// special.
  FalCapabilities capabilities(String endpointId) {
    if (endpointId.isEmpty) return const FalCapabilities();

    final known = _memory[endpointId];
    if (known != null) return known;

    final cached = _readCache(endpointId);
    if (cached != null) {
      _memory[endpointId] = cached;
      return cached;
    }

    unawaited(_fetch(endpointId));
    return const FalCapabilities();
  }

  /// The same answer, but waited for.
  ///
  /// [capabilities] never blocks because it is read from `build`. Sending has
  /// the opposite need: a model whose schema has not landed yet gets the
  /// substring guesswork instead, and for a reference model that means an
  /// `image_url` it never declared and a rejected request. So the first
  /// generation of the session waits for the answer rather than being the one
  /// that fails.
  Future<FalCapabilities> ensure(String endpointId) async {
    final known = capabilities(endpointId);
    if (known.known) return known;

    await _fetch(endpointId);
    return _memory[endpointId] ?? const FalCapabilities();
  }

  /// Starts a fetch for [endpointId], or hands back the one already running.
  Future<void> _fetch(String endpointId) {
    final running = _inFlight[endpointId];
    if (running != null) return running;

    final future = _read(endpointId)
        .whenComplete(() => _inFlight.remove(endpointId));
    _inFlight[endpointId] = future;
    return future;
  }

  Future<void> _read(String endpointId) async {
    try {
      final uri = Uri.parse(
        'https://fal.ai/api/openapi/queue/openapi.json'
        '?endpoint_id=${Uri.encodeComponent(endpointId)}',
      );
      final response = await Http.client
          .get(uri, headers: {'User-Agent': Http.userAgent})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;

      final parsed = parseSchema(response.body);
      if (parsed == null) return;

      _memory[endpointId] = parsed;
      _writeCache(endpointId, parsed);
      notifyListeners();
    } on http.ClientException {
      // Offline. Left unread so the next launch tries again.
    } on TimeoutException {
      // Same.
    } on FormatException {
      // A schema we cannot read is no worse than no schema.
    }
    // The in-flight entry is cleared by [_fetch], which owns it: clearing it
    // here as well would free the slot a moment before the future settles, and
    // a caller arriving in that gap would start a second fetch.
  }

  /// Pulls the things the studio offers out of an OpenAPI document.
  ///
  /// Visible for testing: telling a list input apart from a singular one is the
  /// difference between feeding a reference model and sending a field the
  /// endpoint rejects, and it is worth pinning to a real schema.
  @visibleForTesting
  static FalCapabilities? parseSchema(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final schemas = (decoded['components'] as Map?)?['schemas'];
    if (schemas is! Map) return null;

    // The input object is the one whose name ends in "Input"; the rest are the
    // output and the nested element types.
    Map<String, Object?>? properties;
    for (final entry in schemas.entries) {
      if (!'${entry.key}'.endsWith('Input')) continue;
      final props = (entry.value as Map?)?['properties'];
      if (props is Map) {
        properties = props.cast<String, Object?>();
        break;
      }
    }
    if (properties == null) return null;

    Map<String, Object?>? field(String name) {
      final value = properties![name];
      return value is Map ? value.cast<String, Object?>() : null;
    }

    List<String> enumOf(Map<String, Object?>? spec) {
      final values = spec?['enum'];
      return [
        if (values is List)
          for (final value in values) '$value',
      ];
    }

    final duration = field('duration');
    final resolution = field('resolution');

    // Some models spell the switch one way, some the other; a couple have none.
    var audioField = '';
    for (final candidate in ['generate_audio', 'enable_audio', 'with_audio']) {
      if (field(candidate) != null) {
        audioField = candidate;
        break;
      }
    }

    // The opening frame. `image_url` is the common name and `start_image_url`
    // is Kling's; taking the first that exists keeps the two apart without a
    // per-model table.
    var imageField = '';
    for (final candidate in [
      'image_url',
      'start_image_url',
      'first_frame_image',
      'input_image_url',
    ]) {
      if (field(candidate) != null) {
        imageField = candidate;
        break;
      }
    }

    // The list inputs of a reference model. The array check is what keeps them
    // apart from the singular ones: `audio_url` on a lip-sync model is one file
    // and belongs nowhere near this, while `audio_urls` on Seedance is a list
    // the prompt addresses by handle.
    String listField(List<String> candidates) {
      for (final candidate in candidates) {
        if ('${field(candidate)?['type'] ?? ''}' == 'array') return candidate;
      }
      return '';
    }

    /// How many the endpoint says it will take. Absent on some schemas, which
    /// is why zero has to mean "it did not say" rather than "none".
    int maxItems(String name) {
      if (name.isEmpty) return 0;
      final declared = field(name)?['maxItems'];
      return declared is num ? declared.toInt() : 0;
    }

    final imagesField = listField([
      'image_urls',
      'reference_image_urls',
      'images',
    ]);
    final videosField = listField([
      'video_urls',
      'reference_video_urls',
      'videos',
    ]);
    final audiosField = listField([
      'audio_urls',
      'reference_audio_urls',
      'audios',
    ]);

    return FalCapabilities(
      durations: enumOf(duration),
      defaultDuration: '${duration?['default'] ?? ''}',
      durationIsNumber: '${duration?['type'] ?? ''}' == 'integer' ||
          '${duration?['type'] ?? ''}' == 'number',
      resolutions: enumOf(resolution),
      defaultResolution: '${resolution?['default'] ?? ''}',
      aspectRatios: enumOf(field('aspect_ratio')),
      audioField: audioField,
      defaultAudio: (field(audioField)?['default']) != false,
      imageField: imageField,
      imagesField: imagesField,
      videosField: videosField,
      audiosField: audiosField,
      imagesMax: maxItems(imagesField),
      videosMax: maxItems(videosField),
      audiosMax: maxItems(audiosField),
      known: true,
    );
  }

  // ---- Disk ---------------------------------------------------------------

  String get _dir => Paths.ensureDir(p.join(Paths.configDir, 'fal-schemas'));

  String _file(String endpointId) =>
      p.join(_dir, '${endpointId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.json');

  FalCapabilities? _readCache(String endpointId) {
    if (_dir.isEmpty) return null;

    final file = File(_file(endpointId));
    if (!file.existsSync()) return null;

    try {
      if (DateTime.now().difference(file.lastModifiedSync()) > _life) {
        return null;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      if (decoded['v'] != FalCapabilities.cacheVersion) return null;
      return FalCapabilities.fromJson(decoded.cast<String, Object?>());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  void _writeCache(String endpointId, FalCapabilities capabilities) {
    if (_dir.isEmpty) return;
    try {
      File(_file(endpointId))
          .writeAsStringSync(jsonEncode(capabilities.toJson()));
    } on FileSystemException {
      // A schema that cannot be cached is simply fetched again next time.
    }
  }
}
