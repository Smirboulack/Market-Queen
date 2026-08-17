import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import '../providers/voice_providers.dart';

/// One designed take, once it is on disk and can be played.
///
/// [voiceId] is empty until the take is kept: a design produces three
/// candidates that exist only inside the call that made them, and only the one
/// the user chooses ever becomes a voice on their account.
class VoiceTake {
  VoiceTake({
    required this.generatedVoiceId,
    required this.path,
    this.durationSeconds = 0,
    this.language = '',
  });

  final String generatedVoiceId;

  /// The local mp3 of this take.
  final String path;

  final double durationSeconds;
  final String language;
}

/// How a voice is made when the library has nobody right.
///
/// Two doors, and the difference between them matters enough to be in the type
/// system rather than in a comment:
///
///  * **Designing** invents a voice from a description. Nothing it produces is
///    anybody's real voice, and the interface must never say it is -- the
///    honest phrasing is "a voice that matches this profile".
///  * **Cloning** copies a voice off recordings the user supplies. That one
///    really is the voice in the file, which is exactly why it is a separate
///    button with its own upload rather than a checkbox on the first.
///
/// Both create something permanent on the ElevenLabs account, so neither is
/// ever implicit: designing stops at three previews, and the account is only
/// touched when [keep] is called.
class VoiceForge extends ChangeNotifier {
  VoiceForge(this._settings, this._registry, this._pricing, this._log);

  /// ElevenLabs bills the design's preview line per thousand characters, once,
  /// however many takes come back from it.
  static const _charsPerKilo = 1000.0;

  /// The two engines the design endpoint accepts. v3 leads because it is the
  /// only one that will take a recording as a colour reference, and because a
  /// voice designed on it is the one that works with Eleven v3.
  static const designModels = <(String, String)>[
    ('eleven_ttv_v3', 'Voice Design v3'),
    ('eleven_multilingual_ttv_v2', 'Voice Design v2'),
  ];

  /// What the takes read out. Long enough to clear the endpoint's 100-character
  /// floor, and written as a piece of UGC rather than as a phonetic pangram:
  /// the whole question being asked is whether this voice can sell something
  /// without sounding like an advert.
  static String get defaultPreviewText => tr(
        'Honestly, I did not think this would work. I have tried a lot of '
        'these and most of them do nothing at all, so I was ready to be '
        'disappointed again. Two weeks in and I genuinely cannot believe the '
        'difference. I had to come on here and tell you about it.',
      );

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;

  ProviderTask? _task;

  final List<VoiceTake> _takes = [];
  String _spokenText = '';
  String _error = '';
  bool _designing = false;
  bool _cloning = false;
  bool _keeping = false;

  /// The three candidates of the last design, oldest first. Empty until one
  /// has run.
  List<VoiceTake> get takes => List.unmodifiable(_takes);

  /// What the takes are saying -- the engine writes its own line when none was
  /// given, and the user is entitled to know which words they are judging.
  String get spokenText => _spokenText;

  bool get designing => _designing;
  bool get cloning => _cloning;
  bool get keeping => _keeping;
  bool get busy => _designing || _cloning || _keeping;

  String get error => _error;

  String get _apiKey => _settings.apiKey(_registry.credentialFor('elevenlabs'));

  /// Whether there is a key to do any of this with. The buttons say so before
  /// they are pressed rather than failing on the click.
  bool get ready => _apiKey.isNotEmpty;

  String get _scratchDir => Paths.ensureDir(p.join(Paths.configDir, 'voices'));

  void reset() {
    cancel();
    _takes.clear();
    _spokenText = '';
    _error = '';
    notifyListeners();
  }

  void cancel() {
    final task = _task;
    if (task != null && !task.isFinished) task.cancel();
    _task = null;
    _designing = _cloning = _keeping = false;
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  void _setError(String value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }

  // ---- Designing ---------------------------------------------------------

  /// What one design costs: the preview line, read once.
  CostEstimate estimate(String previewText, String modelId) {
    final text = previewText.trim().isEmpty
        ? defaultPreviewText
        : previewText.trim();
    final unit = _pricing.unitPrice(modelId);
    if (unit == null) return CostEstimate.unknown;
    return CostEstimate(true, unit.amount * (text.length / _charsPerKilo));
  }

  /// Three takes on [description], written to disk so they can be played.
  ///
  /// [referenceAudioPath] is optional and only the v3 engine reads it: a
  /// recording there colours the timbre without the result being a clone of it.
  Future<void> design({
    required String description,
    String previewText = '',
    String modelId = 'eleven_ttv_v3',
    String referenceAudioPath = '',
  }) async {
    if (busy) return;

    final dir = _scratchDir;
    if (dir.isEmpty) {
      _setError(tr('Could not create the voices folder.'));
      return;
    }

    var reference = '';
    if (referenceAudioPath.isNotEmpty) {
      try {
        final file = File(referenceAudioPath);
        if (file.existsSync()) reference = base64Encode(file.readAsBytesSync());
      } on FileSystemException {
        // A reference that cannot be read is dropped rather than fatal: the
        // description on its own is still a design.
        _log.warning(tr('Could not read %1.').arg(referenceAudioPath));
      }
    }

    final task = ElevenLabsVoiceDesignTask(VoiceDesignRequest(
      apiKey: _apiKey,
      model: modelId,
      description: description,
      previewText: previewText,
      referenceAudioBase64: reference,
    ));

    _takes.clear();
    _spokenText = '';
    _error = '';
    _designing = true;
    _task = task;
    notifyListeners();

    _log.info(tr('Designing a voice with %1.').arg(modelId));

    try {
      final result = await task.run();
      final previews =
          (result['previews'] as List?)?.cast<VoicePreview>() ?? const [];

      final stamp = _stamp(DateTime.now());
      for (var i = 0; i < previews.length; ++i) {
        final preview = previews[i];
        final path = p.join(dir, 'design-$stamp-${i + 1}.${preview.extension}');
        try {
          File(path).writeAsBytesSync(preview.audio);
        } on FileSystemException {
          _log.warning(tr('Could not write %1.').arg(path));
          continue;
        }
        _takes.add(VoiceTake(
          generatedVoiceId: preview.generatedVoiceId,
          path: path,
          durationSeconds: preview.durationSeconds,
          language: preview.language,
        ));
      }

      _spokenText = '${result['text'] ?? ''}';
      if (_takes.isEmpty) _error = tr('None of the takes could be saved.');

      _designing = false;
      notifyListeners();
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Voice design failed: %1').arg(error.message));
        _error = error.message;
      }
      _designing = false;
      notifyListeners();
    } finally {
      _task = null;
    }
  }

  /// Keeps take [index] as a real voice, and returns its id and name.
  ///
  /// The other two travel with it as the ones that were heard and passed over,
  /// which is what ElevenLabs asks for. Empty id when it failed; [error] says
  /// why.
  Future<({String voiceId, String name})> keep({
    required int index,
    required String name,
    String description = '',
  }) async {
    if (busy || index < 0 || index >= _takes.length) {
      return (voiceId: '', name: '');
    }

    final chosen = _takes[index];
    final task = ElevenLabsVoiceSaveTask(VoiceSaveRequest(
      apiKey: _apiKey,
      name: name,
      description: description,
      generatedVoiceId: chosen.generatedVoiceId,
      passedOver: [
        for (var i = 0; i < _takes.length; ++i)
          if (i != index) _takes[i].generatedVoiceId,
      ],
    ));

    _error = '';
    _keeping = true;
    _task = task;
    notifyListeners();

    try {
      final result = await task.run();
      final voiceId = '${result['voiceId'] ?? ''}';
      final voiceName = '${result['name'] ?? name}';

      _log.success(tr('Voice "%1" is on your account.').arg(voiceName));
      _keeping = false;
      notifyListeners();
      return (voiceId: voiceId, name: voiceName);
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Could not keep the voice: %1').arg(error.message));
        _error = error.message;
      }
      _keeping = false;
      notifyListeners();
      return (voiceId: '', name: '');
    } finally {
      _task = null;
    }
  }

  // ---- Cloning -----------------------------------------------------------

  /// Copies the voice in [samplePaths] onto the account.
  ///
  /// This is the one path where the app may honestly say the voice *is* the one
  /// in the recording, which is why it never runs off anything but files the
  /// user handed over on purpose.
  Future<({String voiceId, String name})> clone({
    required String name,
    required List<String> samplePaths,
    String description = '',
  }) async {
    if (busy) return (voiceId: '', name: '');

    if (samplePaths.isEmpty) {
      _setError(tr('Add at least one recording first.'));
      return (voiceId: '', name: '');
    }

    final task = ElevenLabsVoiceCloneTask(VoiceCloneRequest(
      apiKey: _apiKey,
      name: name.trim().isEmpty ? tr('Market Queen voice') : name.trim(),
      description: description.trim().isEmpty
          ? tr('Cloned with Market Queen.')
          : description.trim(),
      samplePaths: List.of(samplePaths),
    ));

    _error = '';
    _cloning = true;
    _task = task;
    notifyListeners();

    _log.info(tr('Cloning a voice from %1 recording(s).').arg(samplePaths.length));

    try {
      final result = await task.run();
      final voiceId = '${result['voiceId'] ?? ''}';
      final voiceName = '${result['name'] ?? name}';

      _log.success(tr('Voice "%1" is on your account.').arg(voiceName));
      _cloning = false;
      notifyListeners();
      return (voiceId: voiceId, name: voiceName);
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Cloning failed: %1').arg(error.message));
        _error = error.message;
      }
      _cloning = false;
      notifyListeners();
      return (voiceId: '', name: '');
    } finally {
      _task = null;
    }
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
