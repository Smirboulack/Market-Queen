import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/paths.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../core/signal.dart';
import '../i18n/translator.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import '../providers/voice_casting.dart';
import '../providers/voice_providers.dart';

/// The audition booth.
///
/// A voice-over is the cheapest part of an ad to get wrong and the most obvious
/// once it is: an announcer read sinks a UGC ad as surely as a model's face. So
/// this exists to make hearing the actor cost a fraction of a cent, before any
/// video is bought.
///
/// Cloning is deliberately separate and never implicit. It uploads the user's
/// recordings and creates a permanent voice on their provider account, so it
/// only ever happens on an explicit click.
class VoiceBooth extends ChangeNotifier {
  VoiceBooth(
    this._settings,
    this._registry,
    this._pricing,
    this._log,
    this._casting,
  );

  /// ElevenLabs bills text-to-speech per thousand characters.
  static const _charsPerKilo = 1000.0;

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;
  final VoiceCasting _casting;

  /// The new voice is on the account; the caller decides whether to adopt it.
  final Event<({String voiceId, String name})> cloned = Event();

  ProviderTask? _task;

  String _samplePath = '';
  String _error = '';
  final List<String> _cloneSamples = [];
  bool _auditioning = false;
  bool _cloning = false;

  bool get auditioning => _auditioning;
  bool get cloning => _cloning;

  /// Local file of the last audition, empty until one lands.
  String get samplePath => _samplePath;
  String get error => _error;

  /// Recordings to clone from. Kept here rather than in the project: they are
  /// an input to one operation, not part of the ad.
  List<String> get cloneSamples => List.unmodifiable(_cloneSamples);

  String get _scratchDir => Paths.ensureDir(p.join(Paths.configDir, 'auditions'));

  void _setError(String value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }

  void cancel() {
    final task = _task;
    if (task != null && !task.isFinished) task.cancel();
    _task = null;
    _auditioning = false;
    _cloning = false;
    notifyListeners();
  }

  // ---- Audition ---------------------------------------------------------

  /// What one audition of [text] costs.
  CostEstimate estimate(String text) {
    var providerId = _settings.prefString('voiceProvider');
    if (providerId.isEmpty) providerId = _registry.defaultProvider('voice');

    final model =
        _registry.resolveModel(providerId, _settings.prefString('voiceModel'));

    final unit = _pricing.unitPrice(model);
    if (unit == null) return CostEstimate.unknown;
    return CostEstimate(true, unit.amount * (text.length / _charsPerKilo));
  }

  /// Speaks [text] as the actor would. [actor] is AdProject's actor map: the
  /// casting brief -- or a pinned voice id -- plus the four settings.
  ///
  /// The voice is worked out here rather than passed in, because the whole
  /// point of the audition is that it buys what the render will: the brief goes
  /// through the same caster, hits the same remembered answer, and the actor you
  /// hear is the actor the ad gets.
  Future<void> audition(Map<String, Object?> actor, String text) async {
    if (_auditioning || _cloning) return;

    final line = text.trim();
    if (line.isEmpty) {
      _setError(tr('Write a line for them to say.'));
      return;
    }

    final dir = _scratchDir;
    if (dir.isEmpty) {
      _setError(tr('Could not create the auditions folder.'));
      return;
    }

    var providerId = _settings.prefString('voiceProvider');
    if (providerId.isEmpty) providerId = _registry.defaultProvider('voice');

    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));
    final model =
        _registry.resolveModel(providerId, _settings.prefString('voiceModel'));

    double setting(String key, double fallback) {
      final value = actor[key];
      return value is num ? value.toDouble() : fallback;
    }

    _error = '';
    _auditioning = true;
    notifyListeners();

    try {
      final voice = await _casting.voiceFor(
        providerId: providerId,
        apiKey: apiKey,
        modelId: model,
        source: actor,
        onTask: (running) => _task = running,
      );
      if (voice.label.isNotEmpty) {
        _log.info(voice.description.isEmpty
            //: %1 is a voice's name
            ? tr('Voice: %1.').arg(voice.label)
            //: %1 is a voice's name, %2 what it sounds like
            : tr('Voice: %1 — %2.').arg(voice.label).arg(voice.description));
      }

      final task = ProviderFactory.voice(
        providerId,
        VoiceRequest(
          apiKey: apiKey,
          model: model,
          voiceId: voice.id,
          text: line,
          stability: setting('voiceStability', 0.45),
          similarity: setting('voiceSimilarity', 0.8),
          style: setting('voiceStyle', 0.35),
          speed: setting('voiceSpeed', 1.0),
        ),
      );

      if (task == null) {
        _setError(tr('No voice provider called %1.').arg(providerId));
        _auditioning = false;
        notifyListeners();
        return;
      }
      _task = task;

      final result = await task.run();

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'mp3'}';

      // A fresh name every time: an audio player that already has the file open
      // will not reload one that kept its path.
      final path = p.join(dir, 'audition-${_stamp(DateTime.now())}.$extension');

      try {
        File(path).writeAsBytesSync(data);
      } on FileSystemException {
        _setError(tr('Could not write %1.').arg(path));
        _auditioning = false;
        notifyListeners();
        return;
      }

      _samplePath = path;
      _auditioning = false;
      notifyListeners();
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Audition failed: %1').arg(error.message));
        _error = error.message;
      }
      _auditioning = false;
      notifyListeners();
    } finally {
      _task = null;
    }
  }

  // ---- Cloning ----------------------------------------------------------

  void addCloneSamples(List<String> paths) {
    final before = _cloneSamples.length;
    for (final raw in paths) {
      final path = Http.toLocalPath(raw);
      if (path.isNotEmpty && !_cloneSamples.contains(path)) _cloneSamples.add(path);
    }
    if (_cloneSamples.length != before) notifyListeners();
  }

  void removeCloneSample(int index) {
    if (index < 0 || index >= _cloneSamples.length) return;
    _cloneSamples.removeAt(index);
    notifyListeners();
  }

  /// Uploads the samples and creates a voice on the user's account.
  Future<void> cloneVoice(String name) async {
    if (_auditioning || _cloning) return;

    if (_cloneSamples.isEmpty) {
      _setError(tr('Add at least one recording first.'));
      return;
    }

    final task = ElevenLabsVoiceCloneTask(VoiceCloneRequest(
      apiKey: _settings.apiKey(_registry.credentialFor('elevenlabs')),
      name: name.trim().isEmpty ? tr('Market Queen voice') : name.trim(),
      description: tr('Cloned with Market Queen.'),
      samplePaths: List.of(_cloneSamples),
    ));

    _error = '';
    _cloning = true;
    _task = task;
    notifyListeners();

    _log.info(
        tr('Cloning a voice from %1 recording(s).').arg(_cloneSamples.length));

    try {
      final result = await task.run();
      final voiceId = '${result['voiceId'] ?? ''}';
      final voiceName = '${result['name'] ?? ''}';

      _log.success(tr('Voice "%1" is on your account.').arg(voiceName));
      _cloning = false;
      notifyListeners();
      cloned.emit((voiceId: voiceId, name: voiceName));
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Cloning failed: %1').arg(error.message));
        _error = error.message;
      }
      _cloning = false;
      notifyListeners();
    } finally {
      _task = null;
    }
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}'
        '-${three(time.millisecond)}';
  }
}
