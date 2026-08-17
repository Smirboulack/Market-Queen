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
import '../providers/voice_casting.dart';

/// Bringing the actor to life: one short clip of them saying something.
///
/// This is the last step of making an actor and the first honest answer to
/// "will this work?". Everything before it is a still and a waveform, and the
/// two can each be fine while the pair of them is uncanny -- a face that does
/// not move the way that voice sounds is obvious in half a second and invisible
/// in a preview that only shows one of them.
///
/// It buys the same two things a real shot buys, in the same order and from the
/// same models, so what comes back here is what the render will produce: the
/// line is recorded on the voice provider, then the still and that recording go
/// to the avatar model together.
class ActorReel extends ChangeNotifier {
  ActorReel(this._settings, this._registry, this._pricing, this._log, this._casting);

  static const _charsPerKilo = 1000.0;

  /// Roughly what a line takes to say, for the estimate. The same figure the
  /// pricer uses, so the two agree.
  static const _wordsPerSecond = 2.6;

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;
  final VoiceCasting _casting;

  ProviderTask? _task;

  String _clipPath = '';
  String _stage = '';
  String _error = '';
  bool _running = false;

  /// The finished take, empty until one lands.
  String get clipPath => _clipPath;

  /// What is happening, in the provider's own words.
  String get stage => _stage;

  String get error => _error;
  bool get running => _running;

  String get _scratchDir => Paths.ensureDir(p.join(Paths.configDir, 'takes'));

  String get _voiceProvider => _registry.providerOrDefault(
        'voice',
        _settings.prefString('voiceProvider'),
      );

  String get _avatarProvider => _registry.providerOrDefault(
        'avatar',
        _settings.prefString('avatarProvider'),
      );

  String get avatarModel =>
      _registry.resolveModel(_avatarProvider, _settings.prefString('avatarModel'));

  String get avatarLabel => _registry.modelLabel(_avatarProvider, avatarModel);

  /// What one take costs: the line read aloud, plus the seconds of video that
  /// reading turns into. Both are per-unit prices and the second one is the
  /// whole bill, so an unknown either side makes the answer unknown rather than
  /// half a quote.
  CostEstimate estimate(String line) {
    final text = line.trim();
    if (text.isEmpty) return CostEstimate.free;

    final words = text.split(RegExp(r'\s+')).length;
    final seconds = Pricing.speechSeconds(words);

    final voiceModel =
        _registry.resolveModel(_voiceProvider, _settings.prefString('voiceModel'));

    final voice = _pricing.unitPrice(voiceModel);
    final video = _pricing.unitPrice(avatarModel);
    if (voice == null || video == null) return CostEstimate.unknown;

    return CostEstimate(
      true,
      voice.amount * (text.length / _charsPerKilo) + video.amount * seconds,
    );
  }

  /// Seconds of speech [line] comes to. Public because the resolution the
  /// avatar model is asked for depends on it.
  static double secondsOf(String line) {
    final text = line.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length / _wordsPerSecond;
  }

  void reset() {
    cancel();
    _clipPath = '';
    _stage = '';
    _error = '';
    notifyListeners();
  }

  void cancel() {
    final task = _task;
    if (task != null && !task.isFinished) task.cancel();
    _task = null;
    _running = false;
    _stage = '';
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  void _report(String message) {
    if (_stage == message) return;
    _stage = message;
    notifyListeners();
  }

  /// Films [line] as [actor], and leaves the clip in [clipPath].
  ///
  /// [actor] is the same map the pipeline is handed -- the voice id or the
  /// brief to cast from, plus the four delivery dials -- so the take is read by
  /// whoever the render would use.
  Future<void> film({
    required Map<String, Object?> actor,
    required String portraitPath,
    required String line,
    String motionPrompt = '',
  }) async {
    if (_running) return;

    final text = line.trim();
    if (text.isEmpty) {
      _setError(tr('Write a line for them to say.'));
      return;
    }
    final portrait = Http.toLocalPath(portraitPath);
    if (portrait.isEmpty || !File(portrait).existsSync()) {
      _setError(tr('Pick the picture they are filmed from first.'));
      return;
    }

    final dir = _scratchDir;
    if (dir.isEmpty) {
      _setError(tr('Could not create the takes folder.'));
      return;
    }

    _error = '';
    _clipPath = '';
    _running = true;
    notifyListeners();

    try {
      final audio = await _record(text, actor, dir);
      if (audio.isEmpty) return;

      await _animate(
        portrait: portrait,
        audioPath: audio,
        seconds: secondsOf(text),
        motionPrompt: motionPrompt,
        dir: dir,
      );
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('The take failed: %1').arg(error.message));
        _error = error.message;
      }
    } finally {
      _running = false;
      _stage = '';
      _task = null;
      notifyListeners();
    }
  }

  /// The line, read by the actor's voice. Returns the file, or empty on
  /// failure with [error] already set.
  Future<String> _record(
    String line,
    Map<String, Object?> actor,
    String dir,
  ) async {
    _report(tr('Recording the voice-over...'));

    final providerId = _voiceProvider;
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));
    final model =
        _registry.resolveModel(providerId, _settings.prefString('voiceModel'));

    final voice = await _casting.voiceFor(
      providerId: providerId,
      apiKey: apiKey,
      modelId: model,
      source: actor,
      onTask: (running) => _task = running,
    );

    double dial(String key, double fallback) {
      final value = actor[key];
      return value is num ? value.toDouble() : fallback;
    }

    final task = ProviderFactory.voice(
      providerId,
      VoiceRequest(
        apiKey: apiKey,
        model: model,
        voiceId: voice.id,
        text: line,
        stability: dial('voiceStability', 0.45),
        similarity: dial('voiceSimilarity', 0.8),
        style: dial('voiceStyle', 0.35),
        speed: dial('voiceSpeed', 1.0),
      ),
    );
    if (task == null) {
      _setError(tr('No voice provider called %1.').arg(providerId));
      return '';
    }

    _task = task;
    task.onProgress(_report);

    final result = await task.run();
    final data = result['data'] as Uint8List? ?? Uint8List(0);
    final extension = '${result['extension'] ?? 'mp3'}';

    final path = p.join(dir, 'take-${_stamp(DateTime.now())}.$extension');
    try {
      File(path).writeAsBytesSync(data);
    } on FileSystemException {
      _setError(tr('Could not write %1.').arg(path));
      return '';
    }
    return path;
  }

  /// The still plus that recording, on the avatar model.
  Future<void> _animate({
    required String portrait,
    required String audioPath,
    required double seconds,
    required String motionPrompt,
    required String dir,
  }) async {
    _report(tr('Bringing them to life...'));

    final providerId = _avatarProvider;
    final model = avatarModel;

    final task = ProviderFactory.avatar(
      providerId,
      AvatarRequest(
        apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
        model: model,
        imageDataUri: Http.imageToDataUri(portrait),
        audioDataUri: Http.fileToDataUri(audioPath),
        prompt: motionPrompt.trim(),
        // OmniHuman refuses audio over thirty seconds at 1080p and takes a
        // minute of it at 720p. A long line is shot at the lower resolution
        // rather than refused, which is the difference between a preview and an
        // error message.
        resolution: seconds > 28 ? '720p' : '',
      ),
    );
    if (task == null) {
      _setError(tr('No avatar provider called %1.').arg(providerId));
      return;
    }

    _task = task;
    task.onProgress(_report);

    _log.info(tr('Filming the actor with %1.').arg(
      _registry.modelLabel(providerId, model),
    ));

    final result = await task.run();
    final data = result['data'] as Uint8List? ?? Uint8List(0);
    final extension = '${result['extension'] ?? 'mp4'}';

    final path = p.join(dir, 'take-${_stamp(DateTime.now())}.$extension');
    try {
      File(path).writeAsBytesSync(data);
    } on FileSystemException {
      _setError(tr('Could not write %1.').arg(path));
      return;
    }

    _clipPath = path;
    notifyListeners();
  }

  void _setError(String message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}'
        '-${three(time.millisecond)}';
  }
}
