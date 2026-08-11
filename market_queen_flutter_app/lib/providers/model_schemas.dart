import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/paths.dart';
import 'capabilities.dart';

/// Answers "what does this model accept" from whichever source knows.
///
/// Two sources, and the split is not arbitrary. Everything called directly is
/// declared in [ModelCapabilities.declared], written from each provider's own
/// API reference: the parameters are known when the release is cut, and a
/// network round trip to discover what we already wrote down would be a
/// round trip that can fail. The two Kling endpoints still bought through fal
/// are the exception -- fal's catalogue moves between our releases, and every
/// endpoint on it publishes an OpenAPI document -- so those are read at run
/// time and cached.
///
/// One fetch per fal model, ever: the answer is written next to the settings
/// and re-read on the next launch. A schema that cannot be fetched -- no
/// network, a delisted endpoint -- is remembered as unknown for the session
/// only, so it is tried again next time rather than being written off.
class ModelSchemas extends ChangeNotifier {
  /// Schemas change when a provider ships a new revision of a model, which is
  /// rare but does happen; a fortnight is often enough to catch it and seldom
  /// enough that nobody waits on the network.
  static const _life = Duration(days: 14);

  final Map<String, ModelCapabilities> _memory = {};

  /// The fetch running for each endpoint, so a second caller joins it rather
  /// than starting another one -- or, for [ensure], waits on it.
  final Map<String, Future<void>> _inFlight = {};

  /// Whether this provider's models have a schema to fetch, as opposed to one
  /// already written down.
  static bool fetches(String providerId) => providerId.startsWith('fal-');

  /// What we know about [modelId] right now.
  ///
  /// Never blocks: a declared model answers immediately, and an unread fal
  /// schema comes back unknown and starts a fetch, which notifies listeners
  /// when it lands. A settings column that reads this in `build` therefore
  /// fills itself in a moment later without doing anything special.
  ModelCapabilities capabilities(String providerId, String modelId) {
    if (modelId.isEmpty) return const ModelCapabilities();

    if (!fetches(providerId)) {
      return ModelCapabilities.declared[modelId] ?? const ModelCapabilities();
    }

    final known = _memory[modelId];
    if (known != null) return known;

    final cached = _readCache(modelId);
    if (cached != null) {
      _memory[modelId] = cached;
      return cached;
    }

    unawaited(_fetch(modelId));
    return const ModelCapabilities();
  }

  /// The same answer, but waited for.
  ///
  /// [capabilities] never blocks because it is read from `build`. Sending has
  /// the opposite need: a fal model whose schema has not landed yet would be
  /// handed an opening frame it may not take. So the first generation of the
  /// session waits for the answer rather than being the one that fails.
  Future<ModelCapabilities> ensure(String providerId, String modelId) async {
    final known = capabilities(providerId, modelId);
    if (known.known || !fetches(providerId)) return known;

    await _fetch(modelId);
    return _memory[modelId] ?? const ModelCapabilities();
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
  static ModelCapabilities? parseSchema(String body) {
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

    return ModelCapabilities(
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

  String get _dir => Paths.ensureDir(p.join(Paths.configDir, 'model-schemas'));

  String _file(String endpointId) =>
      p.join(_dir, '${endpointId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.json');

  ModelCapabilities? _readCache(String endpointId) {
    if (_dir.isEmpty) return null;

    final file = File(_file(endpointId));
    if (!file.existsSync()) return null;

    try {
      if (DateTime.now().difference(file.lastModifiedSync()) > _life) {
        return null;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      if (decoded['v'] != ModelCapabilities.cacheVersion) return null;
      return ModelCapabilities.fromJson(decoded.cast<String, Object?>());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  void _writeCache(String endpointId, ModelCapabilities capabilities) {
    if (_dir.isEmpty) return;
    try {
      File(_file(endpointId))
          .writeAsStringSync(jsonEncode(capabilities.toJson()));
    } on FileSystemException {
      // A schema that cannot be cached is simply fetched again next time.
    }
  }
}
