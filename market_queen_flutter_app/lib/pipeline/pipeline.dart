import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/paths.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../core/signal.dart';
import '../core/version.dart';
import '../i18n/translator.dart';
import '../media/ffmpeg.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import '../providers/voice_casting.dart';

/// The voice-over is recorded before anything is drawn, because how long each
/// shot is on screen is what decides the clip we have to buy for it.
enum PipelineStep { script, voice, frames, videos, assemble }

enum StepPhase { pending, running, done, skipped, failed }

class StepInfo {
  StepInfo(this.label, [this.state = StepPhase.pending, this.detail = '']);

  String label;
  StepPhase state;
  String detail;
}

/// The take: the words spoken, the still it starts from and the clip that
/// still was animated into.
///
/// Still a list of one rather than four loose fields, because re-shooting is
/// written against it and because the day a second camera setup earns its
/// place, it is a second entry rather than a second pipeline.
class Shot {
  Shot({required this.line});

  final String line;

  String imagePrompt = '';
  String videoPrompt = '';
  String framePath = '';
  String frameDataUri = '';

  /// This shot's own slice of the read. It is what the avatar model is
  /// lip-synced to, and its length is what the shot lasts -- measured, not
  /// apportioned.
  String voicePath = '';
  String voiceDataUri = '';
  String clipPath = '';

  /// Where this shot sits in the finished cut, in seconds. [duration] is its
  /// share of the voice-over; [clipDuration] is what the provider actually
  /// returned, which can be shorter.
  double start = 0.0;
  double duration = 0.0;
  double clipDuration = -1.0;
}

class _RunState {
  String dir = '';
  String productImagePath = '';
  String productImageDataUri = '';

  /// The cast actor, and the only reference the frame is drawn from.
  String actorPortraitDataUri = '';

  String hook = '';
  String script = '';
  String caption = '';
  String voicePath = '';
  String finalPath = '';
  double voiceDuration = -1.0;

  List<Shot> shots = [];

  /// One entry per billable call.
  List<Usage> consumed = [];
}

/// Raised internally to unwind a run that the user cancelled or that a step
/// gave up on. The message is already user-facing.
class _RunFailed implements Exception {
  _RunFailed(this.message);

  final String message;
}

const _finalFile = 'final.mp4';

/// Turns one form submission into a finished MP4.
///
/// The steps run one after another, each one feeding the next through [_run].
/// Nothing blocks the UI: every step awaits a task, and a cancel tears the
/// active one down.
class Pipeline extends ChangeNotifier {
  Pipeline(
    this._settings,
    this._registry,
    this._pricing,
    this._log,
    this._casting,
  ) {
    // Show the plan before anything runs.
    _resetSteps();
  }

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;
  final VoiceCasting _casting;

  /// (success, outputFile).
  final Event<({bool success, String outputFile})> finished = Event();

  Map<String, Object?> _request = {};
  _RunState _run = _RunState();

  /// "2/4" while a step is walking the shot list. Set, it pins the step's
  /// detail column so a provider's progress chatter cannot bury the count --
  /// which, on a six-shot run, is the one thing worth seeing at a glance.
  String _shotLabel = '';

  /// When >= 0, the frame and video steps do this shot only and then go
  /// straight to the cut: re-shooting one scene must not re-buy the others.
  int _onlyShot = -1;

  List<StepInfo> _steps = [];
  int _current = -1;
  bool _running = false;
  bool _cancelling = false;
  String _status = '';
  ProviderTask? _activeTask;

  bool get running => _running;
  List<StepInfo> get steps => List.unmodifiable(_steps);
  String get status => _status;
  String get outputFile => _run.finalPath;
  String get projectDir => _run.dir;

  /// What the run has cost so far.
  PriceBreakdown get cost => _pricing.actual(_run.consumed);

  /// The finished cut, shot by shot: what the storyboard is drawn from.
  List<Shot> get shots => List.unmodifiable(_run.shots);

  double get progress {
    if (_steps.isEmpty) return 0.0;
    final settled = _steps
        .where((step) => step.state == StepPhase.done || step.state == StepPhase.skipped)
        .length;
    return settled / _steps.length;
  }

  static String stepLabel(PipelineStep step) => switch (step) {
        PipelineStep.script => tr('Script'),
        PipelineStep.voice => tr('Voice-over'),
        PipelineStep.frames => tr('Frames'),
        PipelineStep.videos => tr('Shots'),
        PipelineStep.assemble => tr('Final cut'),
      };

  void _resetSteps() {
    _steps = [for (final step in PipelineStep.values) StepInfo(stepLabel(step))];
    notifyListeners();
  }

  /// Re-labels the steps after a language switch.
  void retranslate() {
    for (var i = 0; i < _steps.length; ++i) {
      _steps[i].label = stepLabel(PipelineStep.values[i]);
    }
    notifyListeners();
  }

  void _setStatus(String value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  void _setStep(PipelineStep step, StepPhase state, [String detail = '']) {
    final info = _steps[step.index];
    info.state = state;
    if (detail.isNotEmpty) info.detail = detail;
    _current = step.index;
    notifyListeners();
  }

  // ---- Lifecycle --------------------------------------------------------

  /// The whole ad, as [AdProject.toRequest] builds it.
  Future<void> start(Map<String, Object?> request) async {
    if (_running) return;

    _request = request;
    _run = _RunState();
    _shotLabel = '';
    _onlyShot = -1;
    _cancelling = false;

    _resetSteps();
    _setStatus('');

    // One folder per run, so every intermediate file stays inspectable. The
    // label is the ad's name when there is no product: naming the folder is the
    // only job it has, and the product fields are read by the models.
    final label = '${request['runLabel'] ?? ''}'.isEmpty
        ? '${request['productName'] ?? ''}'
        : '${request['runLabel'] ?? ''}';
    final folder = '${_stamp(DateTime.now())}-${Paths.slugify(label)}';
    _run.dir = Paths.ensureDir(p.join(_settings.projectsDir, folder));

    if (_run.dir.isEmpty) {
      _log.error(tr('Could not create the project folder in %1.')
          .arg(_settings.projectsDir));
      finished.emit((success: false, outputFile: ''));
      return;
    }

    _running = true;
    notifyListeners();

    _log.info(tr('Project folder: %1').arg(_run.dir));

    // The product photo is used both as a reference for the writer and,
    // optionally, as the opening frame itself.
    final productImage = Http.toLocalPath('${request['productImagePath'] ?? ''}');
    if (productImage.isNotEmpty && File(productImage).existsSync()) {
      _run.productImagePath = productImage;
      _run.productImageDataUri = await _prepare(productImage);
      if (_run.productImageDataUri.isEmpty) {
        _log.warning(unreadableImage(productImage));
      }
    }

    final portrait = Http.toLocalPath('${request['actorPortraitPath'] ?? ''}');
    if (portrait.isNotEmpty && File(portrait).existsSync()) {
      _run.actorPortraitDataUri = await _prepare(portrait);
      if (_run.actorPortraitDataUri.isEmpty) {
        _log.warning(unreadableImage(portrait));
      }
    }

    await _drive(from: PipelineStep.script);
  }

  /// Re-shoots one scene and cuts the ad again. Repairing a bad shot costs a
  /// fraction of relaunching the whole ad, which is the whole reason the shots
  /// are kept as separate files.
  Future<void> regenerateShot(int index) async {
    if (_running || index < 0 || index >= _run.shots.length || _run.dir.isEmpty) {
      return;
    }

    _onlyShot = index;
    _shotLabel = '';
    _cancelling = false;

    _resetSteps();
    _setStatus('');

    // The words and the read are exactly what they were; only the picture for
    // this one scene is being bought again.
    _setStep(PipelineStep.script, StepPhase.skipped, tr('unchanged'));
    _setStep(PipelineStep.voice, StepPhase.skipped, tr('unchanged'));

    _running = true;
    _run.finalPath = '';
    notifyListeners();

    _log.info(tr('Re-shooting scene %1.').arg(index + 1));

    await _drive(from: PipelineStep.frames);
  }

  /// What re-shooting one scene buys: a still and however many seconds it runs.
  /// The voice-over is not touched, so it is not re-bought.
  CostEstimate regenerateEstimate(int index) {
    if (index < 0 || index >= _run.shots.length) return CostEstimate.unknown;

    final shot = _run.shots[index];

    final imageProvider = '${_request['imageProvider'] ?? ''}';
    final imageModel = _registry.resolveModel(
        imageProvider, '${_request['imageModel'] ?? ''}');

    final clipProvider = '${_request['avatarProvider'] ?? ''}';
    final clipModel = _registry.resolveModel(
        clipProvider, '${_request['avatarModel'] ?? ''}');

    final framePrice = _pricing.unitPrice(imageModel);
    final clipPrice = _pricing.unitPrice(clipModel);
    if (framePrice == null || clipPrice == null) return CostEstimate.unknown;

    final amount = framePrice.amount +
        clipPrice.amount * (clipPrice.unit == 'video' ? 1.0 : shot.duration);

    return CostEstimate(true, amount);
  }

  void cancel() {
    if (!_running || _cancelling) return;
    _cancelling = true;
    _log.warning(tr('Cancelling...'));
    _activeTask?.cancel();
  }

  /// Runs the remaining steps in order. Everything below either completes or
  /// throws [_RunFailed]; there is exactly one place that catches.
  Future<void> _drive({required PipelineStep from}) async {
    try {
      for (final step in PipelineStep.values.skip(from.index)) {
        _throwIfCancelling();
        switch (step) {
          case PipelineStep.script:
            await _stepScript();
          case PipelineStep.voice:
            await _stepVoice();
          case PipelineStep.frames:
            await _stepFrames();
          case PipelineStep.videos:
            await _stepVideos();
          case PipelineStep.assemble:
            await _stepAssemble();
        }
      }
      _completeRun();
    } on _RunFailed catch (error) {
      _failRun(error.message);
    } on ProviderException catch (error) {
      _failRun(error.message);
    }
  }

  void _throwIfCancelling() {
    if (_cancelling) throw _RunFailed(tr('Cancelled.'));
  }

  /// Awaits a provider task, routing its progress into the step detail.
  Future<Map<String, Object?>> _await(ProviderTask? task, PipelineStep step) async {
    if (task == null) throw _RunFailed(tr('That provider is not available.'));

    _activeTask = task;
    task.onProgress((message) {
      _setStatus(message);
      if (_shotLabel.isEmpty) {
        _steps[step.index].detail = message;
        notifyListeners();
      }
    });

    try {
      return await task.run();
    } finally {
      _activeTask = null;
    }
  }

  /// Turns an "auto" pick into a concrete model id and says so in the log.
  String _pickModel(String providerId, String requestedModel,
      [int durationSeconds = 0]) {
    final resolved =
        _registry.resolveModel(providerId, requestedModel, durationSeconds);
    // Said whenever the id changed on the way through, not only for "auto": a
    // preference naming a retired model is resolved the same way, and the run
    // is priced on what it says here.
    if (resolved.isNotEmpty && resolved != requestedModel) {
      _log.info(tr('Auto picked %1.').arg(resolved));
    }
    return resolved;
  }

  /// Records what a step actually bought, so the run can report a real cost
  /// instead of repeating the estimate.
  void _recordUsage(String step, String providerId, String modelId, double units,
      [double unitsOut = 0.0, String quality = '', String size = '']) {
    _run.consumed
        .add(Usage(step, providerId, modelId, units, unitsOut, quality, size));
    notifyListeners();
  }


  String _writeArtifact(String fileName, List<int> data) {
    final path = p.join(_run.dir, fileName);
    try {
      File(path).writeAsBytesSync(data);
    } on FileSystemException {
      throw _RunFailed(tr('Could not write %1.').arg(fileName));
    }
    return path;
  }

  String get _ffmpeg => Ffmpeg.resolve(_settings.ffmpegPath);

  double get _estimatedSpeechDuration {
    final words = _run.script.trim().isEmpty
        ? 0
        : _run.script.trim().split(RegExp(r'\s+')).length;
    return math.max(3.0, words / 2.6);
  }

  /// A picture the models will accept, converting it with ffmpeg first if the
  /// Dart codecs cannot read it.
  Future<String> _prepare(String path) => imageDataUri(_ffmpeg, path);

  String _text(String key) => '${_request[key] ?? ''}';

  double _number(String key, double fallback) {
    final value = _request[key];
    return value is num ? value.toDouble() : fallback;
  }

  // ---------------------------------------------------------------------
  // 1. Script
  // ---------------------------------------------------------------------

  /// The whole scenario, as one take.
  ///
  /// It used to be cut into a shot per beat, each with its own read, its own
  /// still and its own clip, stitched back together at the end. That is four
  /// or five times the bill for an ad whose joins are audible: every line was
  /// a separate TTS call, so the delivery restarted at each cut.
  ///
  /// One read, one frame, one clip. What comes back is what was written.
  void _oneTake() {
    _run.shots
      ..clear()
      ..add(Shot(line: _run.script.trim()));
  }

  /// The shape the whole run is in: the frame, the clip and anything a model
  /// crops for itself. Read from one place so a picture and the video made
  /// out of it cannot disagree about it.
  String get _aspectRatio =>
      _text('aspectRatio').isEmpty ? '9:16' : _text('aspectRatio');

  Future<void> _stepScript() async {
    final ownScript = _text('script').trim();

    if (ownScript.isNotEmpty) {
      _setStep(PipelineStep.script, StepPhase.running);

      _run.script = ownScript;
      _oneTake();
      _run.hook = ownScript;

      _log.info(tr('Filming your scenario in one take.'));

      _setStep(PipelineStep.script, StepPhase.done, tr('your own scenario'));
      return;
    }

    final providerId = _text('textProvider');
    final model = _text('textModel');

    _setStep(PipelineStep.script, StepPhase.running);
    _setStatus(tr('Writing the script...'));

    final result = await _await(
      ProviderFactory.script(
        providerId,
        ScriptRequest(
          apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
          model: model,
          productName: _text('productName'),
          productDescription: _text('productDescription'),
          audience: _text('audience'),
          tone: _text('tone'),
          language: _text('language'),
          avatarBrief: _actorBrief,
          extraInstructions: _text('extraInstructions'),
          durationSeconds: (_request['durationSeconds'] as num?)?.toInt() ?? 20,
          referenceImageDataUri: _run.productImageDataUri,
        ),
      ),
      PipelineStep.script,
    );

    _recordUsage(
      'script',
      providerId,
      model,
      (result['inputTokens'] as num?)?.toDouble() ?? 0,
      (result['outputTokens'] as num?)?.toDouble() ?? 0,
    );

    _run.script = '${result['script'] ?? ''}';
    _run.hook = '${result['hook'] ?? ''}';
    _run.caption = '${result['caption'] ?? ''}';

    // The writer still answers with a shot list; it is read as prose here and
    // filmed in one take. Its own `script` field is what it thinks the whole
    // read is, so that wins, and the lines are joined only when it left the
    // field empty.
    if (_run.script.trim().isEmpty) {
      final lines = <String>[];
      for (final entry in (result['shots'] as List?) ?? const []) {
        if (entry is! Map) continue;
        final line = '${entry['line'] ?? ''}'.trim();
        if (line.isNotEmpty) lines.add(line);
      }
      _run.script = lines.join(' ');
    }

    if (_run.script.trim().isEmpty) {
      throw _RunFailed(tr('The model answer did not contain a script.'));
    }

    _oneTake();
    if (_run.hook.trim().isEmpty) _run.hook = _run.script.trim();

    // The writer describes the still and the movement in the same answer, so
    // the take is filmed on its own directions rather than on the generic ones.
    _run.shots.first
      ..imagePrompt = '${result['imagePrompt'] ?? ''}'.trim()
      ..videoPrompt = '${result['videoPrompt'] ?? ''}'.trim();

    _writeArtifact(
      'script.json',
      utf8.encode(const JsonEncoder.withIndent('    ').convert({
        'hook': _run.hook,
        'script': _run.script,
        'caption': _run.caption,
      })),
    );

    _log.success(tr('Script ready: "%1"').arg(_run.hook));
    _setStep(PipelineStep.script, StepPhase.done, _run.hook);
  }

  // ---------------------------------------------------------------------
  // 2. Voice-over -- the whole read, in one recording
  // ---------------------------------------------------------------------
  //
  // One call, one file. It used to be a call per beat, because each beat was
  // lip-synced to its own audio -- and every one of those calls started the
  // delivery again from nothing, so the finished ad restarted its own
  // intonation at each cut. Whatever context fields the engine took could
  // soften that; they could not remove it.
  //
  // Recorded whole, the ad's length also stops being an estimate: it is
  // however long the audio turned out to be, measured, and the clip is bought
  // against that.

  Future<void> _stepVoice() async {
    _setStep(PipelineStep.voice, StepPhase.running);

    final providerId = _text('voiceProvider');
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));

    // Cast before the read: which voice, resolved from the actor.
    final voiceId = await _castVoice(providerId, apiKey);

    for (var index = 0; index < _run.shots.length; ++index) {
      _throwIfCancelling();

      _shotLabel = '${index + 1}/${_run.shots.length}';
      _setStep(PipelineStep.voice, StepPhase.running, _shotLabel);
      _setStatus(tr('Recording line %1 of %2...')
          .arg(index + 1)
          .arg(_run.shots.length));

      final model = _pickModel(providerId, _text('voiceModel'));
      final shot = _run.shots[index];

      final result = await _await(
        ProviderFactory.voice(
          providerId,
          VoiceRequest(
            apiKey: apiKey,
            model: model,
            voiceId: voiceId,
            text: shot.line,
            // The booth's sliders, so the ad sounds like the audition did.
            stability: _number('voiceStability', 0.45),
            similarity: _number('voiceSimilarity', 0.8),
            style: _number('voiceStyle', 0.35),
            speed: _number('voiceSpeed', 1.0),
            previousText: index > 0 ? _run.shots[index - 1].line : '',
            nextText: index + 1 < _run.shots.length
                ? _run.shots[index + 1].line
                : '',
          ),
        ),
        PipelineStep.voice,
      );

      // TTS is billed on the text we sent, not on the audio that came back.
      _recordUsage('voice', providerId, model, shot.line.length / 1000.0);

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'mp3'}';
      final path = _writeArtifact('shot${index + 1}-voice.$extension', data);

      shot.voicePath = path;
      shot.voiceDataUri = Http.fileToDataUri(path);
    }

    _shotLabel = '';
    await _probeShotAudio();
    await _joinVoice();
  }

  /// Who reads the ad.
  ///
  /// The user picked traits, not a voice: a language and an accent, a gender, an
  /// age, what the read is for. Turning that into a provider's voice id is this
  /// step's first job, and it is done through the same caster the audition used,
  /// so the answer it finds is the answer it already found.
  Future<String> _castVoice(String providerId, String apiKey) async {
    _setStatus(tr('Casting the voice...'));

    try {
      final voice = await _casting.voiceFor(
        providerId: providerId,
        apiKey: apiKey,
        modelId: _registry.resolveModel(providerId, _text('voiceModel')),
        source: _request,
        onTask: (task) => _activeTask = task,
      );

      if (voice.label.isNotEmpty) {
        _log.info(voice.description.isEmpty
            //: %1 is a voice's name
            ? tr('Voice: %1.').arg(voice.label)
            //: %1 is a voice's name, %2 what it sounds like
            : tr('Voice: %1 — %2.').arg(voice.label).arg(voice.description));
      } else if (voice.id.isEmpty) {
        // Said here rather than left to the provider's "pick a voice first",
        // which names neither the brief nor the reason.
        _log.warning(tr('No voice matched this actor. Widen the brief, or pick '
            'a voice in the actor editor.'));
      }
      return voice.id;
    } finally {
      _activeTask = null;
    }
  }

  /// Measures every line. Without ffmpeg there is nothing to measure with, so
  /// the old word-count estimate stands in -- the ad still renders, it just
  /// plans against a guess again.
  Future<void> _probeShotAudio() async {
    final exe = _ffmpeg;

    if (exe.isEmpty) {
      final estimated = _estimatedSpeechDuration;
      final count = math.max(1, _run.shots.length);
      for (final shot in _run.shots) {
        shot.duration = estimated / count;
      }
    } else {
      for (final shot in _run.shots) {
        _throwIfCancelling();
        final duration = await probeDuration(exe, shot.voicePath);
        // A line that could not be measured still has to hold the screen for as
        // long as it is heard; the word-count estimate is the safest guess.
        shot.duration =
            duration > 0 ? duration : math.max(0.5, shot.line.length / 15.6);
      }
    }

    _planShotTimings();
  }

  /// Lays the measured durations end to end. Nothing is apportioned any more:
  /// each shot lasts exactly as long as its own line was recorded to be, so the
  /// picture and the sound cannot drift apart.
  void _planShotTimings() {
    var cursor = 0.0;
    for (final shot in _run.shots) {
      shot.start = cursor;
      cursor += shot.duration;
    }
    _run.voiceDuration = cursor;

    _log.info(tr('The read runs %1s.')
        .arg(_run.voiceDuration.toStringAsFixed(1)));
  }

  /// One file with the whole read in it. Whisper times the subtitles against it
  /// and the final mux uses it as the audio track, so the picture and the sound
  /// come from the same sequence in the same order.
  Future<void> _joinVoice() async {
    final withAudio =
        _run.shots.where((shot) => shot.voicePath.isNotEmpty).toList();

    if (withAudio.isEmpty) {
      throw _RunFailed(tr('No voice-over was recorded.'));
    }

    void settle() {
      _setStep(PipelineStep.voice, StepPhase.done,
          tr('%1s').arg(_run.voiceDuration.toStringAsFixed(1)));
    }

    final exe = _ffmpeg;
    if (exe.isEmpty || withAudio.length == 1) {
      // Nothing to join, or nothing to join it with.
      _run.voicePath = withAudio.first.voicePath;
      settle();
      return;
    }

    final args = <String>['-y', '-hide_banner'];
    var inputs = '';
    for (var i = 0; i < withAudio.length; ++i) {
      args.addAll(['-i', p.basename(withAudio[i].voicePath)]);
      inputs += '[$i:a]';
    }
    args.addAll([
      '-filter_complex', '${inputs}concat=n=${withAudio.length}:v=0:a=1[a]',
      '-map', '[a]',
      '-c:a', 'libmp3lame',
      '-q:a', '2',
      'voice.mp3',
    ]);

    final task = FfmpegTask(exe, args, workingDirectory: _run.dir);
    _activeTask = task;
    try {
      await task.run();
      _run.voicePath = p.join(_run.dir, 'voice.mp3');
      _log.success(tr('Voice-over ready: %1 line(s), %2s.')
          .arg(_run.shots.length)
          .arg(_run.voiceDuration.toStringAsFixed(1)));
    } on ProviderException catch (error) {
      _throwIfCancelling();
      // The scenes still have their own audio, so the ad is not lost -- only
      // the subtitles, which are timed against the joined file.
      _log.warning(tr('Could not join the voice-over: %1').arg(error.message));
      _run.voicePath = withAudio.first.voicePath;
    } finally {
      _activeTask = null;
    }

    settle();
  }

  // ---------------------------------------------------------------------
  // 3. The frame -- one still, of the actor, in the shape of the ad
  // ---------------------------------------------------------------------

  /// Who is on camera, for the writer: how they look, and how they behave.
  ///
  /// The personality is the half of an actor with nothing to show for itself,
  /// and leaving it out is why an actor cast as blunt and Gen-Z used to be
  /// handed a script written in the same neutral voice as everybody else and
  /// then simply read it in a young one.
  String get _actorBrief {
    final look = _text('avatarBrief').trim();
    final persona = _text('actorPersona').trim();
    if (persona.isEmpty) return look;
    if (look.isEmpty) return persona;
    return '$look. $persona';
  }

  /// The motion an avatar model is given for one shot.
  ///
  /// Two instructions, and the shot's own comes second on purpose: the actor's
  /// is a standing description of how this person carries themselves, and the
  /// shot's is what they do in these few seconds, so the specific one is the
  /// last thing the model reads.
  String _motionFor(String shotPrompt) {
    final action = _text('actorAction').trim();
    final shot = shotPrompt.trim();
    if (action.isEmpty) return shot;
    if (shot.isEmpty) return action;
    return '$action. $shot';
  }

  /// What the take is drawn from when nothing wrote a prompt for it.
  ///
  /// Which is now the ordinary case: it is the actor as they were described,
  /// the room they are in, and nothing else.
  ///
  /// It used to end with `they are holding <product name>`, and that line is
  /// the single worst thing this app has done. A name is not a picture: the
  /// model has to invent the shape, the colour and the label, and what it
  /// invents is a counterfeit of a real bottle with the branding misspelt --
  /// put in the hands of an actor, in an ad, under somebody's own account.
  ///
  /// It is also wrong even when the field is right. The product name outlives
  /// the ad it was typed for: a project written for a perfume and rewritten for
  /// a dating app still carries the perfume, and the frame is the one place
  /// where a leftover word becomes a physical object on camera.
  ///
  /// So the product is simply not mentioned. It is not replaced by an
  /// instruction to hold nothing either: the shot that puts a product on
  /// camera is a real feature and it is coming, and a prompt that forbids one
  /// is something that would have to be found and undone first.
  String _defaultFramePrompt() {
    final actor = _text('avatarBrief').trim();
    final decor = _text('extraInstructions').trim();

    return [
      tr('A vertical photo taken on a phone, held at arm\'s length.'),
      if (actor.isEmpty)
        tr('In frame: an ordinary person talking to the camera.')
      //: %1 is how the user described their actor
      else
        tr('In frame: %1, talking to the camera.').arg(actor),
      //: %1 is how the user described the room the ad is filmed in
      if (decor.isNotEmpty) tr('Shot in %1.').arg(decor),
      tr(
        'Ordinary room light, visible skin texture, no retouching, framed '
        'slightly off-centre. Not an advertisement: no studio lighting, no '
        'colour grading, no product hero shot.',
      ),
    ].join(' ');
  }

  Future<void> _stepFrames() async {
    _setStep(PipelineStep.frames, StepPhase.running);

    final providerId = _text('imageProvider');
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));
    final useOwnPhoto = _request['useProductPhotoAsFrame'] == true;

    final first = _onlyShot >= 0 ? _onlyShot : 0;
    final last = _onlyShot >= 0 ? _onlyShot : _run.shots.length - 1;

    for (var index = first; index <= last && index < _run.shots.length; ++index) {
      _throwIfCancelling();
      final shot = _run.shots[index];

      // The photo the user dropped in stands in for the first shot's still:
      // that is the one that has to show the real product.
      if (index == 0 && useOwnPhoto && _run.productImagePath.isNotEmpty) {
        shot.framePath = _run.productImagePath;
        shot.frameDataUri = _run.productImageDataUri;
        _log.info(tr('Using your photo for shot 1.'));
        continue;
      }

      _shotLabel = '${index + 1}/${_run.shots.length}';
      _setStep(PipelineStep.frames, StepPhase.running, _shotLabel);
      _setStatus(
          tr('Drawing shot %1 of %2...').arg(index + 1).arg(_run.shots.length));

      final model = _pickModel(providerId, _text('imageModel'));
      final size = _text('imageSize');
      final quality = _text('imageQuality');

      // The face, or nothing. A product photo used to stand in when the actor
      // had no portrait, which handed the image model a picture of a bottle and
      // asked it for a person talking to camera -- and got a person holding a
      // bottle, from a field the ad never mentioned.
      final reference = _run.actorPortraitDataUri;

      final result = await _await(
        ProviderFactory.image(
          providerId,
          ImageRequest(
            apiKey: apiKey,
            model: model,
            aspectRatio: _aspectRatio,
            referenceImageDataUri: reference,
            prompt: shot.imagePrompt.isEmpty
                ? _defaultFramePrompt()
                : shot.imagePrompt,
            size: size,
            quality: quality,
          ),
        ),
        PipelineStep.frames,
      );

      _recordUsage('frames', providerId, model, 1.0, 0, quality, size);

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'png'}';
      final path = _writeArtifact('shot${index + 1}-frame.$extension', data);

      shot.framePath = path;
      shot.frameDataUri = Http.imageToDataUri(path);
      _log.success(
          tr('Frame %1 saved (%2 KB).').arg(index + 1).arg(data.length ~/ 1024));
    }

    _shotLabel = '';
    _setStep(PipelineStep.frames, StepPhase.done,
        tr('%1 frame(s)').arg(_run.shots.length));
  }

  // ---------------------------------------------------------------------
  // 4. The take -- the still, lip-synced to the read
  // ---------------------------------------------------------------------
  //
  // The avatar model takes the still and the audio and gives back a clip whose
  // mouth matches, exactly as long as the audio. Nothing is asked for in
  // seconds, so nothing comes back needing to be stretched or trimmed -- which
  // is why this is the only video path an ad has. The image-to-video shelf
  // belongs to the Video mode, where the length is the thing you are buying.

  Future<void> _stepVideos() async {
    _setStep(PipelineStep.videos, StepPhase.running);

    for (var index = 0; index < _run.shots.length; ++index) {
      _throwIfCancelling();
      final shot = _run.shots[index];

      if (shot.voiceDataUri.isEmpty) {
        throw _RunFailed(
            tr('No voice-over was recorded, so there is nothing to lip-sync to.'));
      }

      _setStatus(tr('Filming your actor...'));

      // The default is asked for rather than named: hardcoding one here is how
      // a provider that has since been dropped stays wired into the one path
      // nobody reads until a render fails.
      final providerId = _registry.providerOrDefault(
          'avatar', '${_request['avatarProvider'] ?? ''}');
      final model = _pickModel(providerId, _text('avatarModel'));

      final task = ProviderFactory.avatar(
        providerId,
        AvatarRequest(
          apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
          model: model,
          imageDataUri: shot.frameDataUri,
          audioDataUri: shot.voiceDataUri,
          prompt: _motionFor(shot.videoPrompt),
          aspectRatio: _aspectRatio,
        ),
      );
      if (task == null) {
        throw _RunFailed(tr('No avatar provider called %1.').arg(providerId));
      }

      final result = await _await(task, PipelineStep.videos);

      // Billed by the second, and the clip is the line: the avatar model is
      // handed the audio and gives back exactly that much video.
      _recordUsage('video', providerId, model, shot.duration, 1);

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'mp4'}';
      final path = _writeArtifact('shot${index + 1}-clip.$extension', data);

      shot.clipPath = path;
      _log.success(tr('Shot %1 saved (%2 MB).')
          .arg(index + 1)
          .arg((data.length / 1048576.0).toStringAsFixed(1)));
    }

    _setStep(PipelineStep.videos, StepPhase.done);
  }

  // ---------------------------------------------------------------------
  // 5. Delivery
  // ---------------------------------------------------------------------

  Future<void> _stepAssemble() async {
    _setStep(PipelineStep.assemble, StepPhase.running);

    final clip = _run.shots.isEmpty ? '' : _run.shots.first.clipPath;
    if (clip.isEmpty || !File(clip).existsSync()) {
      throw _RunFailed(tr('No shot was rendered, so there is nothing to deliver.'));
    }

    // The avatar model was handed the frame, the line and the shape of the ad,
    // and what it gives back is the ad: already the right size, already
    // carrying its own audio in sync with the mouth. Sending it through ffmpeg
    // to be padded, concatenated and re-encoded is a generation of quality and
    // a dependency, spent on producing the same file.
    //
    // This is what a one-take ad buys beyond the money: nothing has to be cut,
    // so nothing can be cut wrong, and the machine does not need ffmpeg at all.
    _setStatus(tr('Finishing the video...'));

    final destination = p.join(_run.dir, _finalFile);
    try {
      File(clip).copySync(destination);
    } on FileSystemException {
      throw _RunFailed(tr('Could not write the finished video into %1.')
          .arg(_run.dir));
    }

    _run.finalPath = destination;
    _setStep(PipelineStep.assemble, StepPhase.done, _finalFile);
  }

  // ---------------------------------------------------------------------
  // Wrap-up
  // ---------------------------------------------------------------------

  void _writeProjectManifest(bool success) {
    if (_run.dir.isEmpty) return;

    String relative(String path) =>
        path.isEmpty ? '' : p.relative(path, from: _run.dir);

    final manifest = <String, Object?>{
      'app': 'Market Queen',
      'version': appVersion,
      // Bumped whenever the shape below changes; LibraryModel reads older ones.
      // 2 replaced the single frame/clip pair with the shots array.
      'schemaVersion': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'success': success,
      'productName': _text('productName'),
      'hook': _run.hook,
      'script': _run.script,
      'caption': _run.caption,
      'shots': [
        for (final shot in _run.shots)
          {
            'line': shot.line,
            'imagePrompt': shot.imagePrompt,
            'videoPrompt': shot.videoPrompt,
            'frame': relative(shot.framePath),
            'clip': relative(shot.clipPath),
            'start': shot.start,
            'duration': shot.duration,
          },
      ],
      // The first shot's still doubles as the project thumbnail.
      'frame': _run.shots.isEmpty ? '' : relative(_run.shots.first.framePath),
      'voice': relative(_run.voicePath),
      'final': relative(_run.finalPath),
      // What the providers billed, estimated from their published prices.
      'cost': cost.toJson(),
      'providers': {
        'text': _text('textProvider'),
        'textModel': _text('textModel'),
        'image': _text('imageProvider'),
        'imageModel': _text('imageModel'),
        'avatar': _text('avatarProvider'),
        'avatarModel': _text('avatarModel'),
        'video': _text('videoProvider'),
        'videoModel': _text('videoModel'),
        'voice': _text('voiceProvider'),
        'voiceModel': _text('voiceModel'),
      },
    };

    try {
      File(p.join(_run.dir, 'project.json'))
          .writeAsStringSync(const JsonEncoder.withIndent('    ').convert(manifest));
    } on FileSystemException {
      // A missing manifest costs the library entry, not the video.
    }
  }

  void _failRun(String error) {
    if (!_running) return;

    if (_current >= 0 &&
        _current < _steps.length &&
        _steps[_current].state == StepPhase.running) {
      _steps[_current]
        ..state = StepPhase.failed
        ..detail = error;
    }

    _log.error(error);
    _setStatus(error);

    _writeProjectManifest(false);

    _onlyShot = -1;
    _running = false;
    _cancelling = false;
    _activeTask = null;
    notifyListeners();
    finished.emit((success: false, outputFile: ''));
  }

  void _completeRun() {
    _writeProjectManifest(true);

    _onlyShot = -1;
    _running = false;
    _cancelling = false;
    notifyListeners();

    _log.success(tr('Done: %1').arg(_run.finalPath));
    _setStatus(tr('Your ad is ready.'));
    finished.emit((success: true, outputFile: _run.finalPath));
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
