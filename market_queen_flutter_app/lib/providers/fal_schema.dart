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

  /// False when no schema could be read -- the caller then falls back to what
  /// it did before rather than pretending the model has no options.
  final bool known;

  bool get supportsAudio => audioField.isNotEmpty;

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

  Map<String, Object?> toJson() => {
    'durations': durations,
    'defaultDuration': defaultDuration,
    'durationIsNumber': durationIsNumber,
    'resolutions': resolutions,
    'defaultResolution': defaultResolution,
    'aspectRatios': aspectRatios,
    'audioField': audioField,
    'defaultAudio': defaultAudio,
    'imageField': imageField,
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
  final Set<String> _inFlight = {};

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

  Future<void> _fetch(String endpointId) async {
    if (!_inFlight.add(endpointId)) return;

    try {
      final uri = Uri.parse(
        'https://fal.ai/api/openapi/queue/openapi.json'
        '?endpoint_id=${Uri.encodeComponent(endpointId)}',
      );
      final response = await Http.client
          .get(uri, headers: {'User-Agent': Http.userAgent})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return;

      final parsed = _parse(response.body);
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
    } finally {
      _inFlight.remove(endpointId);
    }
  }

  /// Pulls the four things the studio offers out of an OpenAPI document.
  static FalCapabilities? _parse(String body) {
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
