import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/paths.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';

class Candidate {
  const Candidate(this.path, this.prompt);

  final String path;
  final String prompt;
}

/// Casting: turns a description into candidate portraits.
///
/// The whole point of this class is the prompt it builds. Image models default
/// to advertising photography, and asking them for a "UGC look" does not move
/// them -- they comply in words and still render a campaign shot. The scaffold
/// in resources/casting.json names the camera, imposes concrete flaws and
/// forbids the commercial vocabulary by name. It is data, not code, because
/// this is the part of the product that needs the most iteration.
///
/// Candidates are generated in parallel and land in a scratch folder. Only the
/// one the user keeps is copied anywhere permanent.
class Casting extends ChangeNotifier {
  Casting(this._settings, this._registry, this._pricing, this._log);

  static const _fileName = 'casting.json';

  // Portraits are shot vertical because the ad is. There is no control for it:
  // a landscape reference for a 9:16 ad would only ever be a mistake.
  static const _portraitAspect = '9:16';

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;

  /// Fragment id -> text, with {slots}.
  Map<String, Object?> _portrait = {};
  List<String> _order = [];
  List<String> _traitOrder = [];
  Map<String, Object?> _fallbacks = {};

  /// The house style rules, shared with the director: an actor cast against
  /// advertising photography and then dropped into a commercial storyboard
  /// still produces a commercial.
  String directionRules = '';

  bool _overridden = false;

  final List<Candidate> _candidates = [];
  final List<ProviderTask> _tasks = [];

  int _requested = 0;
  int _received = 0;
  int _failed = 0;
  String _error = '';

  bool get running => _requested > 0 && _received + _failed < _requested;

  /// Newest batch, oldest first.
  List<Candidate> get candidates => List.unmodifiable(_candidates);
  int get received => _received;
  int get requested => _requested;
  String get error => _error;
  bool get overridden => _overridden;

  /// Where a casting.json would go to override the bundled scaffold.
  String get overridePath => p.join(Paths.configDir, _fileName);

  Future<void> load() async {
    // The user's file wins outright rather than merging, for the same reason
    // the price catalogue does: a half-overridden scaffold would be impossible
    // to reason about when a portrait comes out wrong.
    _overridden = _loadFromFile(overridePath);
    if (!_overridden) {
      _loadScaffold(await rootBundle.loadString('assets/resources/casting.json'));
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

    directionRules = '${decoded['direction'] ?? ''}';

    final order = decoded['order'];
    _order = order is List ? [for (final entry in order) '$entry'] : [];

    final traits = decoded['traitOrder'];
    _traitOrder = traits is List ? [for (final entry in traits) '$entry'] : [];

    // An override that forgot the order array still works: fall back to every
    // fragment the file defines, in the order the file lists them.
    if (_order.isEmpty) _order = _portrait.keys.toList();

    return true;
  }

  // ---- The prompt -------------------------------------------------------

  /// The exact text that would be sent. Shown in the UI: the realism work is
  /// the product here, so it should be inspectable rather than magic.
  String buildPrompt(Map<String, Object?> actor) {
    // The subject line is the structured traits, then the free description.
    // Traits come first so a bare "tired" in the brief qualifies a person the
    // model has already been told the age and build of.
    final subject = <String>[];
    final rawTraits = actor['traits'];
    final traits = rawTraits is Map ? rawTraits.cast<String, Object?>() : const {};

    // Named order first, then anything the scaffold did not list, so an added
    // trait still reaches the prompt instead of disappearing silently.
    final keys = List<String>.of(_traitOrder);
    for (final key in traits.keys) {
      if (!keys.contains(key)) keys.add(key);
    }

    for (final key in keys) {
      final fragment = '${traits[key] ?? ''}'.trim();
      if (fragment.isNotEmpty) subject.add(fragment);
    }

    final brief = '${actor['brief'] ?? ''}'.trim();
    if (brief.isNotEmpty) subject.add(brief);

    var subjectText = subject.join(', ');
    if (subjectText.isEmpty) subjectText = '${_fallbacks['subject'] ?? ''}';

    var locationText = '${actor['decor'] ?? ''}'.trim();
    if (locationText.isEmpty) locationText = '${_fallbacks['location'] ?? ''}';

    final parts = <String>[];
    for (final key in _order) {
      final fragment = '${_portrait[key] ?? ''}'.trim();
      if (fragment.isEmpty) continue;
      parts.add(fragment
          .replaceAll('{subject}', subjectText)
          .replaceAll('{location}', locationText));
    }

    return parts.join(' ');
  }

  // ---- Generation -------------------------------------------------------

  /// What one batch costs.
  CostEstimate estimate(int count) {
    var providerId = _settings.prefString('imageProvider');
    if (providerId.isEmpty) providerId = _registry.defaultProvider('image');

    final resolved =
        _registry.resolveModel(providerId, _settings.prefString('imageModel'));

    final unit = _pricing.unitPrice(resolved);
    if (unit == null) return CostEstimate.unknown;
    return CostEstimate(true, unit.amount * count);
  }

  String get _scratchDir => Paths.ensureDir(p.join(Paths.configDir, 'casting'));

  void _setError(String value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }

  void reset() {
    cancel();
    _candidates.clear();
    _requested = _received = _failed = 0;
    _error = '';
    notifyListeners();
  }

  void cancel() {
    for (final task in _tasks) {
      if (!task.isFinished) task.cancel();
    }
    _tasks.clear();

    if (_requested > 0) {
      _requested = _received + _failed;
      notifyListeners();
    }
  }

  void _finishOne() {
    if (_received + _failed >= _requested) {
      // Every request failed: the batch produced nothing and the reason is
      // already in the log, but the panel needs to say so where the user is
      // looking.
      if (_received == 0 && _failed > 0 && _error.isEmpty) {
        _error = tr('No portrait came back. Check the log.');
      }
    }
    notifyListeners();
  }

  /// Fires [count] portrait requests at once. [actor] is AdProject's actor map:
  /// brief, decor, traits, referenceImages.
  Future<void> generate(Map<String, Object?> actor, {int count = 4}) async {
    if (running) return;

    final dir = _scratchDir;
    if (dir.isEmpty) {
      _setError(tr('Could not create the casting folder.'));
      return;
    }

    // A new batch replaces the previous one: keeping candidates across batches
    // would make the grid a pile rather than a choice.
    _candidates.clear();
    _tasks.clear();
    _received = _failed = 0;
    _requested = count < 1 ? 1 : count;
    _error = '';
    notifyListeners();

    var providerId = _settings.prefString('imageProvider');
    if (providerId.isEmpty) providerId = _registry.defaultProvider('image');

    final model =
        _registry.resolveModel(providerId, _settings.prefString('imageModel'));
    final prompt = buildPrompt(actor);

    // A photo of the real person, when there is one, is what keeps the same
    // face across the whole batch and every later shot.
    var referenceUri = '';
    final references = actor['referenceImages'];
    if (references is List && references.isNotEmpty) {
      referenceUri = Http.imageToDataUri('${references.first}');
    }

    _log.info(tr('Casting %1 portrait(s) with %2.').arg(_requested).arg(model));

    final stamp = _timestamp(DateTime.now());
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));

    for (var i = 0; i < _requested; ++i) {
      final task = ProviderFactory.image(
        providerId,
        ImageRequest(
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          aspectRatio: _portraitAspect,
          referenceImageDataUri: referenceUri,
        ),
      );

      if (task == null) {
        _failed += 1;
        _setError(tr('No image provider called %1.').arg(providerId));
        _finishOne();
        continue;
      }

      _tasks.add(task);
      unawaited(_collect(task, dir, stamp, i, prompt));
    }
  }

  Future<void> _collect(
    ProviderTask task,
    String dir,
    String stamp,
    int index,
    String prompt,
  ) async {
    try {
      final result = await task.run();

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'png'}';
      final path = p.join(dir, '$stamp-${index + 1}.$extension');

      try {
        File(path).writeAsBytesSync(data);
      } on FileSystemException {
        _failed += 1;
        _setError(tr('Could not write %1.').arg(path));
        _finishOne();
        return;
      }

      _received += 1;
      _candidates.add(Candidate(path, prompt));
      _finishOne();
    } on ProviderException catch (error) {
      _failed += 1;
      if (error is! TaskCancelled) {
        _log.error(tr('Portrait failed: %1').arg(error.message));
        _error = error.message;
      }
      _finishOne();
    }
  }

  static String _timestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
