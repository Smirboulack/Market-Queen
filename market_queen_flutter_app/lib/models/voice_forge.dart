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
    this.voiceId = '',
    this.durationSeconds = 0,
    this.language = '',
  });

  final String generatedVoiceId;

  /// Set already on the providers where designing *creates*.
  ///
  /// MiniMax takes the id up front and the voice exists the moment the call
  /// answers, so there is nothing left for [VoiceForge.keep] to do but hand it
  /// back. ElevenLabs leaves this empty until a take is kept.
  final String voiceId;

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
/// Both create something permanent on the user's provider account, so neither
/// is ever implicit -- but *how* permanent differs by provider, and the
/// interface has to follow rather than paper over it:
///
///  * On **ElevenLabs**, designing stops at three previews that live inside the
///    call, and the account is only touched when [keep] is called.
///  * On **MiniMax**, the id is handed over up front and the voice exists as
///    soon as the design answers. There is one take, and keeping it is
///    bookkeeping rather than a second call.
///
/// Which of the two is in force is [provider], and it is the same preference
/// the rest of the app reads for "who speaks" -- deliberately, because a voice
/// id belongs to the account that made it. A voice designed on MiniMax handed
/// to ElevenLabs to read is not a degraded result, it is a 404.
class VoiceForge extends ChangeNotifier {
  VoiceForge(this._settings, this._registry, this._pricing, this._log);

  /// The provider ids this panel can work against, in the order they are
  /// offered.
  static const providers = <String>['elevenlabs', 'minimax-tts'];

  /// Whether [id] can design and clone at all. Everything else on the voice
  /// shelf reads a script and nothing more, so offering the workshop against
  /// one would be offering a button that 404s.
  static bool worksWith(String id) => providers.contains(id);

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

  /// Which account the workshop is working against.
  ///
  /// Read from the app's own voice preference rather than kept here, so it can
  /// never disagree with the engine that will do the reading. Falls back to
  /// ElevenLabs when the preference names a provider with no workshop -- the
  /// panel greys itself out in that case rather than pretending.
  String get provider {
    final saved = _settings.prefString('voiceProvider');
    return worksWith(saved) ? saved : providers.first;
  }

  String get credential => _registry.credentialFor(provider);

  String get _apiKey => _settings.apiKey(credential);

  /// Whether the design endpoint hands back several takes to choose between.
  /// One provider does and one does not -- see the class comment.
  bool get offersTakes => provider == 'elevenlabs';

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
  ///
  /// The same shape on both providers -- a design is billed as a reading of its
  /// own preview text -- so the only difference is which line of the catalogue
  /// the rate comes off.
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
    required String name,
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

    if (provider != 'elevenlabs') {
      await _designOnMiniMax(
        description: description,
        name: name,
        previewText: previewText,
        dir: dir,
      );
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

  /// One take, and the voice already exists when it lands.
  ///
  /// The name is not decoration here: MiniMax has no display name at all, so
  /// what the user typed becomes the id -- see [MiniMaxVoiceId.from] -- and it
  /// is what the voice is called on their side too.
  Future<void> _designOnMiniMax({
    required String description,
    required String name,
    required String previewText,
    required String dir,
  }) async {
    final voiceId = MiniMaxVoiceId.from(
      name.trim().isEmpty ? tr('Market Queen voice') : name.trim(),
    );

    final task = MiniMaxVoiceDesignTask(
      apiKey: _apiKey,
      description: description,
      previewText:
          previewText.trim().isEmpty ? defaultPreviewText : previewText,
      voiceId: voiceId,
    );

    _takes.clear();
    _spokenText = '';
    _error = '';
    _designing = true;
    _task = task;
    notifyListeners();

    _log.info(tr('Designing a voice with %1.').arg('MiniMax'));

    try {
      final result = await task.run();
      final audio = result['audio'];

      var path = '';
      if (audio is Uint8List && audio.isNotEmpty) {
        path = p.join(dir, 'design-${_stamp(DateTime.now())}.mp3');
        try {
          File(path).writeAsBytesSync(audio);
        } on FileSystemException {
          _log.warning(tr('Could not write %1.').arg(path));
          path = '';
        }
      }

      // Kept even with nothing to play: the voice is on the account either way,
      // and a panel that showed no take at all would look like a failure that
      // had in fact charged for a voice.
      _takes.add(VoiceTake(
        generatedVoiceId: voiceId,
        voiceId: '${result['voiceId'] ?? voiceId}',
        path: path,
      ));
      _spokenText = previewText.trim().isEmpty ? defaultPreviewText : previewText;

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
  ///
  /// On a provider where designing already created the voice there is nothing
  /// to send: the id it was made under comes straight back, so the button that
  /// calls this is a confirmation rather than a second charge.
  Future<({String voiceId, String name})> keep({
    required int index,
    required String name,
    String description = '',
  }) async {
    if (busy || index < 0 || index >= _takes.length) {
      return (voiceId: '', name: '');
    }

    if (_takes[index].voiceId.isNotEmpty) {
      return (voiceId: _takes[index].voiceId, name: name);
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

    final wanted = name.trim().isEmpty ? tr('Market Queen voice') : name.trim();

    final task = provider == 'elevenlabs'
        ? ElevenLabsVoiceCloneTask(VoiceCloneRequest(
            apiKey: _apiKey,
            name: wanted,
            description: description.trim().isEmpty
                ? tr('Cloned with Market Queen.')
                : description.trim(),
            samplePaths: List.of(samplePaths),
          ))
        // MiniMax has no display name and clones from one recording, so the
        // name becomes the id and the rest of the pile is left behind -- which
        // the panel says before the button is pressed rather than after.
        : MiniMaxVoiceCloneTask(
            apiKey: _apiKey,
            voiceId: MiniMaxVoiceId.from(wanted),
            samplePaths: List.of(samplePaths),
          );

    _error = '';
    _cloning = true;
    _task = task;
    notifyListeners();

    _log.info(tr('Cloning a voice from %1 recording(s).').arg(samplePaths.length));

    try {
      final result = await task.run();
      final voiceId = '${result['voiceId'] ?? ''}';
      final voiceName = '${result['name'] ?? wanted}';

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
