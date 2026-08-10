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
import '../providers/text_providers.dart';
import '../providers/types.dart';
import '../providers/voice_casting.dart';
import '../providers/voice_providers.dart';
import 'shot_planner.dart';

/// The voice-over is recorded before anything is drawn, because how long each
/// shot is on screen is what decides the clip we have to buy for it.
enum PipelineStep { script, voice, frames, videos, captions, assemble }

enum StepPhase { pending, running, done, skipped, failed }

class StepInfo {
  StepInfo(this.label, [this.state = StepPhase.pending, this.detail = '']);

  String label;
  StepPhase state;
  String detail;
}

/// One camera setup: the words spoken over it, the still it starts from and the
/// clip that still was animated into.
class Shot {
  Shot({required this.line, this.kind = 'talking'});

  final String line;

  /// talking | broll
  String kind;
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

  /// The cast actor. Where both exist the portrait wins for the frames -- a
  /// face that changes between shots is more visible than a product rendered
  /// from its description rather than its photo.
  String actorPortraitDataUri = '';

  String hook = '';
  String script = '';
  String caption = '';
  String voicePath = '';
  String srtPath = '';
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

const _captionsFile = 'captions.srt';
const _finalFile = 'final.mp4';

/// Burned-in captions, UGC style: bold white with a hard outline, sitting above
/// the bottom UI of the social apps.
const _subtitleStyle =
    'FontName=Arial,FontSize=22,Bold=1,PrimaryColour=&H00FFFFFF,'
    'OutlineColour=&H00000000,BorderStyle=1,Outline=3,Shadow=0,'
    'Alignment=2,MarginV=90';

/// One canvas for the whole ad. Shots come back from different models at
/// different sizes, and concat will not join streams whose dimensions differ,
/// so they all get padded onto this before being cut together.
({int width, int height}) _outputSize(String aspectRatio) => switch (aspectRatio) {
      '16:9' => (width: 1920, height: 1080),
      '1:1' => (width: 1080, height: 1080),
      _ => (width: 1080, height: 1920),
    };

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
        PipelineStep.captions => tr('Subtitles'),
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

    // One folder per run, so every intermediate file stays inspectable.
    final label = '${request['productName'] ?? ''}';
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
    final talking = shot.kind != 'broll';

    final imageProvider = '${_request['imageProvider'] ?? ''}';
    final imageModel = _registry.resolveModel(
        imageProvider, '${_request['imageModel'] ?? ''}');

    final clipProvider = talking
        ? '${_request['avatarProvider'] ?? ''}'
        : '${_request['videoProvider'] ?? ''}';
    final clipModel = _registry.resolveModel(
      clipProvider,
      talking
          ? '${_request['avatarModel'] ?? ''}'
          : '${_request['videoModel'] ?? ''}',
    );

    final framePrice = _pricing.unitPrice(imageModel);
    final clipPrice = _pricing.unitPrice(clipModel);
    if (framePrice == null || clipPrice == null) return CostEstimate.unknown;

    final seconds =
        talking ? shot.duration : Pricing.clipSeconds(shot.duration).toDouble();
    final amount = framePrice.amount +
        clipPrice.amount * (clipPrice.unit == 'video' ? 1.0 : seconds);

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
          case PipelineStep.captions:
            await _stepCaptions();
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
    if (Registry.isAuto(requestedModel) && resolved.isNotEmpty) {
      _log.info(tr('Auto picked %1.').arg(resolved));
    }
    return resolved;
  }

  /// Records what a step actually bought, so the run can report a real cost
  /// instead of repeating the estimate.
  void _recordUsage(String step, String providerId, String modelId, double units,
      [double unitsOut = 0.0]) {
    _run.consumed.add(Usage(step, providerId, modelId, units, unitsOut));
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

  /// Cuts a scenario the user wrote into shots.
  ///
  /// The rules live in [ShotPlanner], where the pricer can reach them too: what
  /// the estimate quotes and what the run buys have to be the same list.
  void _splitOwnScript() {
    _run.shots
      ..clear()
      ..addAll([for (final line in ShotPlanner.split(_run.script)) Shot(line: line)]);
  }

  /// Puts a camera on each shot of a scenario the user wrote.
  ///
  /// This is what stops an ad being one unbroken talking head. A UGC ad that
  /// stays on the same face for its whole length reads as an advert, and the
  /// product never gets seen -- so the lines that describe the thing are filmed
  /// on the thing, with the read carrying over them.
  ///
  /// It never fails a run. Every shot already has a line and a default frame
  /// prompt; a plan that could not be bought only costs the cutaways.
  Future<void> _planShots() async {
    if (_request['brollEnabled'] == false) return;

    // Two shots is a cut, not a cut list. There is nothing to cut away to.
    if (_run.shots.length < ShotPlanner.minShotsToDirect) return;

    final providerId = _text('textProvider');
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));
    if (providerId.isEmpty || apiKey.isEmpty) return;

    final model = _pickModel(providerId, _text('textModel'));

    final task = ProviderFactory.script(
      providerId,
      ScriptRequest(
        mode: ScriptMode.planShots,
        apiKey: apiKey,
        model: model,
        productName: _text('productName'),
        productDescription: _text('productDescription'),
        audience: _text('audience'),
        avatarBrief: _text('avatarBrief'),
        extraInstructions: _text('extraInstructions'),
        lines: [for (final shot in _run.shots) shot.line],
        referenceImageDataUri: _run.productImageDataUri,
      ),
    );

    // Cutaways are worth having, not worth failing a run over: an unknown
    // writer leaves the ad exactly as the user wrote it.
    if (task == null) return;

    _setStatus(tr('Planning the shots...'));

    try {
      final result = await _await(task, PipelineStep.script);

      _recordUsage(
        'script',
        providerId,
        model,
        (result['inputTokens'] as num?)?.toDouble() ?? 0,
        (result['outputTokens'] as num?)?.toDouble() ?? 0,
      );

      // By position, and only ever the camera. A plan that came back short
      // leaves the rest of the ad exactly as it was.
      final plan = (result['plan'] as List?) ?? const [];

      for (var index = 0; index < plan.length && index < _run.shots.length; ++index) {
        final entry = plan[index];
        if (entry is! Map) continue;

        final shot = _run.shots[index];
        shot.kind = ScriptTask.shotKind(entry['kind']);
        shot.imagePrompt = '${entry['imagePrompt'] ?? ''}'.trim();
        shot.videoPrompt = '${entry['videoPrompt'] ?? ''}'.trim();
      }

      // A face has to open and close the ad: the hook is a person looking at
      // you, and so is the call to action. Enforced here rather than trusted to
      // the prompt, because it is the one arrangement that is always wrong.
      _run.shots.first.kind = 'talking';
      _run.shots.last.kind = 'talking';

      final broll = _run.shots.where((shot) => shot.kind == 'broll').length;
      _log.success(tr('%1 talking shot(s), %2 product shot(s).')
          .arg(_run.shots.length - broll)
          .arg(broll));
    } on ProviderException catch (error) {
      _throwIfCancelling();
      _log.warning(tr('Could not plan the shots (%1). Filming every line on camera.')
          .arg(error.message));
    }
  }

  Future<void> _stepScript() async {
    final shotCount = Pricing.shotCount(
        (_request['durationSeconds'] as num?)?.toInt() ?? 20);

    // Scenes the studio cut and directed: the shot list is already decided, so
    // there is nothing to write and nothing to guess at.
    final scenes = (_request['scenes'] as List?) ?? const [];
    if (scenes.isNotEmpty) {
      _run.shots.clear();
      for (final entry in scenes) {
        if (entry is! Map) continue;
        final line = '${entry['line'] ?? ''}'.trim();
        if (line.isEmpty) continue;

        _run.shots.add(Shot(line: line, kind: '${entry['kind'] ?? 'talking'}')
          ..imagePrompt = '${entry['imagePrompt'] ?? ''}'.trim()
          ..videoPrompt = '${entry['videoPrompt'] ?? ''}'.trim());
      }
    }

    final ownScript = _text('script').trim();

    if (_run.shots.isNotEmpty) {
      _run.script = ownScript;
      _run.hook = _run.shots.first.line;
      _log.info(tr('Using your %1 scene(s).').arg(_run.shots.length));
      _setStep(PipelineStep.script, StepPhase.skipped, tr('your own scenes'));
      return;
    }

    if (ownScript.isNotEmpty) {
      _setStep(PipelineStep.script, StepPhase.running);

      _run.script = ownScript;
      _splitOwnScript();
      _run.hook = _run.shots.isEmpty ? ownScript : _run.shots.first.line;

      _log.info(tr('Using the scenario you wrote, cut into %1 shot(s).')
          .arg(_run.shots.length));

      // Not a word of it changes; only where the camera points.
      await _planShots();

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
          avatarBrief: _text('avatarBrief'),
          extraInstructions: _text('extraInstructions'),
          durationSeconds: (_request['durationSeconds'] as num?)?.toInt() ?? 20,
          shotCount: shotCount,
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

    final shotsJson = <Map<String, Object?>>[];
    for (final entry in (result['shots'] as List?) ?? const []) {
      if (entry is! Map) continue;
      final shot = Shot(
        line: '${entry['line'] ?? ''}',
        kind: ScriptTask.shotKind(entry['kind']),
      )
        ..imagePrompt = '${entry['imagePrompt'] ?? ''}'
        ..videoPrompt = '${entry['videoPrompt'] ?? ''}';
      _run.shots.add(shot);
      shotsJson.add({
        'line': shot.line,
        'kind': shot.kind,
        'imagePrompt': shot.imagePrompt,
        'videoPrompt': shot.videoPrompt,
      });
    }

    // Same rule as a scenario the user wrote: a face opens the ad and a face
    // closes it, whatever the writer thought.
    if (_run.shots.isNotEmpty) {
      _run.shots.first.kind = 'talking';
      _run.shots.last.kind = 'talking';
    }

    if (_run.shots.isEmpty) {
      throw _RunFailed(tr('The model answer did not contain a script.'));
    }

    _writeArtifact(
      'script.json',
      utf8.encode(const JsonEncoder.withIndent('    ').convert({
        'hook': _run.hook,
        'script': _run.script,
        'caption': _run.caption,
        'shots': shotsJson,
      })),
    );

    _log.success(tr('Script ready in %1 shot(s): "%2"')
        .arg(_run.shots.length)
        .arg(_run.hook));
    _setStep(PipelineStep.script, StepPhase.done, _run.hook);
  }

  // ---------------------------------------------------------------------
  // 2. Voice-over -- one take per scene, then the measured cut plan
  // ---------------------------------------------------------------------
  //
  // The read is recorded scene by scene rather than in one piece, because a
  // talking shot is lip-synced to its own audio: the model needs the words for
  // that shot and nothing else.
  //
  // Recorded naively that would sound like a series of fresh takes, so each
  // request carries the neighbouring lines in previous_text/next_text. The
  // engine uses them for context only -- it never speaks them -- and the
  // delivery carries across the joins. Not every engine takes them, though, and
  // one that does not is sent a body without them rather than a 400: what each
  // one accepts is declared in [ElevenLabsModel].
  //
  // The gain is that a scene's length stops being an estimate. It is however
  // long its audio turned out to be, measured, which is what finally removes
  // every reason to stretch, loop or trim a clip.

  Future<void> _stepVoice() async {
    _setStep(PipelineStep.voice, StepPhase.running);

    final providerId = _text('voiceProvider');
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));

    // Said once, when it is actually true, because the alternative is one
    // setting away: v3 is the expressive engine but takes no context fields, so
    // on a multi-shot ad every line is a fresh take. Multilingual v2 carries the
    // delivery across the joins instead.
    if (_run.shots.length > 1 &&
        providerId == 'elevenlabs' &&
        !ElevenLabsModel.of(_pickModel(providerId, _text('voiceModel'))).stitching) {
      _log.info(tr('Eleven v3 records each line on its own: it takes no context '
          'from the neighbouring ones. Multilingual v2 does, if you would rather '
          'have one continuous read.'));
    }

    // Cast once, before the first line: every shot is the same person speaking,
    // and a brief resolved per shot would be four round trips to say so.
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

    _log.info(tr('%1 shot(s) over %2s.')
        .arg(_run.shots.length)
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
  // 3. Frames -- one still per shot
  // ---------------------------------------------------------------------

  /// What a shot is drawn from when nothing wrote a prompt for it.
  ///
  /// Which is now the ordinary case: the studio no longer cuts the ad into
  /// directed scenes, so the only description of the shot is the ad itself --
  /// the actor as they were described, the room they are in, and the thing they
  /// are holding. Composed rather than fixed, because a generic "a person
  /// holding X" throws away the two fields the user spent the most time on.
  String _defaultFramePrompt(String kind) {
    final actor = _text('avatarBrief').trim();
    final decor = _text('extraInstructions').trim();
    final product = _text('productName').trim();

    // A product shot has the same room and the same light -- it is the same
    // person filming, a moment later -- but no face in it. That is the whole
    // point of cutting to it.
    if (kind == 'broll') {
      return [
        tr('A vertical close-up taken on a phone, held in one hand.'),
        //: %1 is a product name
        if (product.isNotEmpty)
          tr('In frame: %1, and nothing else.').arg(product)
        else
          tr('In frame: the product being used, held in someone\'s hands.'),
        //: %1 is how the user described the room the ad is filmed in
        if (decor.isNotEmpty) tr('Shot in %1.').arg(decor),
        tr(
          'Nobody\'s face in the shot: hands only. Ordinary room light, visible '
          'texture, no retouching, slightly imperfect focus. Not an '
          'advertisement: no studio lighting, no colour grading, no product '
          'hero shot.',
        ),
      ].join(' ');
    }

    return [
      tr('A vertical photo taken on a phone, held at arm\'s length.'),
      if (actor.isEmpty)
        tr('In frame: an ordinary person talking to the camera.')
      //: %1 is how the user described their actor
      else
        tr('In frame: %1, talking to the camera.').arg(actor),
      //: %1 is how the user described the room the ad is filmed in
      if (decor.isNotEmpty) tr('Shot in %1.').arg(decor),
      //: %1 is a product name
      if (product.isNotEmpty) tr('They are holding %1.').arg(product),
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

      // One reference per model, so it has to be the one the shot is about: the
      // face for a talking shot, the thing itself for a product shot. Handing a
      // product shot the actor's portrait is how a cutaway comes back with her
      // in it.
      final reference = shot.kind == 'broll'
          ? (_run.productImageDataUri.isEmpty
              ? _run.actorPortraitDataUri
              : _run.productImageDataUri)
          : (_run.actorPortraitDataUri.isEmpty
              ? _run.productImageDataUri
              : _run.actorPortraitDataUri);

      final result = await _await(
        ProviderFactory.image(
          providerId,
          ImageRequest(
            apiKey: apiKey,
            model: model,
            aspectRatio: _text('aspectRatio').isEmpty ? '9:16' : _text('aspectRatio'),
            referenceImageDataUri: reference,
            prompt: shot.imagePrompt.isEmpty
                ? _defaultFramePrompt(shot.kind)
                : shot.imagePrompt,
          ),
        ),
        PipelineStep.frames,
      );

      _recordUsage('frames', providerId, model, 1.0);

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
  // 4. Shots -- talking ones are lip-synced, the rest are animated
  // ---------------------------------------------------------------------
  //
  // A talking shot goes to an avatar model: it takes the still and the line's
  // audio and gives back a clip whose mouth matches, exactly as long as the
  // audio. Nothing is asked for in seconds and nothing needs trimming
  // afterwards.
  //
  // A product shot has no face to sync, so it stays on the ordinary
  // image-to-video path and buys the smallest clip that covers its slot.

  Future<void> _stepVideos() async {
    _setStep(PipelineStep.videos, StepPhase.running);

    final first = _onlyShot >= 0 ? _onlyShot : 0;
    final last = _onlyShot >= 0 ? _onlyShot : _run.shots.length - 1;

    for (var index = first; index <= last && index < _run.shots.length; ++index) {
      _throwIfCancelling();
      final shot = _run.shots[index];
      final talking = shot.kind != 'broll' && shot.voiceDataUri.isNotEmpty;

      _shotLabel = '${index + 1}/${_run.shots.length}';
      _setStep(PipelineStep.videos, StepPhase.running, _shotLabel);
      _setStatus(talking
          ? tr('Filming shot %1 of %2...').arg(index + 1).arg(_run.shots.length)
          : tr('Filming the product for shot %1...').arg(index + 1));

      final String providerId;
      final String model;
      final ProviderTask? task;

      if (talking) {
        providerId = _request['avatarProvider'] == null ||
                '${_request['avatarProvider']}'.isEmpty
            ? 'fal-avatar'
            : '${_request['avatarProvider']}';
        model = _pickModel(providerId, _text('avatarModel'));
        task = ProviderFactory.avatar(
          providerId,
          AvatarRequest(
            apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
            model: model,
            imageDataUri: shot.frameDataUri,
            audioDataUri: shot.voiceDataUri,
            prompt: shot.videoPrompt,
          ),
        );
        if (task == null) {
          throw _RunFailed(tr('No avatar provider called %1.').arg(providerId));
        }
      } else {
        providerId = _text('videoProvider');
        final clipSeconds = Pricing.clipSeconds(shot.duration);
        model = _pickModel(providerId, _text('videoModel'), clipSeconds);
        task = ProviderFactory.video(
          providerId,
          VideoRequest(
            apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
            model: model,
            aspectRatio:
                _text('aspectRatio').isEmpty ? '9:16' : _text('aspectRatio'),
            imageDataUri: shot.frameDataUri,
            prompt: shot.videoPrompt.isEmpty
                ? tr('Slow handheld move around the product, natural light, '
                    'nobody on screen.')
                : shot.videoPrompt,
            durationSeconds: clipSeconds,
          ),
        );
      }

      final result = await _await(task, PipelineStep.videos);

      // Billed by the second of clip; for a talking shot the clip is the line.
      final seconds = talking
          ? shot.duration
          : Pricing.clipSeconds(shot.duration).toDouble();
      _recordUsage('video', providerId, model, seconds, 1);

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'mp4'}';
      final path = _writeArtifact('shot${index + 1}-clip.$extension', data);

      shot.clipPath = path;
      _log.success(tr('Shot %1 saved (%2 MB).')
          .arg(index + 1)
          .arg((data.length / 1048576.0).toStringAsFixed(1)));
    }

    await _probeClipDurations();

    _shotLabel = '';
    _setStep(PipelineStep.videos, StepPhase.done,
        tr('%1 shot(s)').arg(_run.shots.length));
  }

  /// Measures every clip so the cut can trim each one to its slot. A clip that
  /// came back shorter than we asked for would otherwise leave a gap.
  Future<void> _probeClipDurations() async {
    final exe = _ffmpeg;
    if (exe.isEmpty) return;

    final first = _onlyShot >= 0 ? _onlyShot : 0;
    final last = _onlyShot >= 0 ? _onlyShot : _run.shots.length - 1;

    for (var index = first; index <= last && index < _run.shots.length; ++index) {
      _throwIfCancelling();
      _run.shots[index].clipDuration =
          await probeDuration(exe, _run.shots[index].clipPath);
    }
  }

  // ---------------------------------------------------------------------
  // 5. Subtitles
  // ---------------------------------------------------------------------

  Future<void> _stepCaptions() async {
    if (_request['captionsEnabled'] == false) {
      _setStep(PipelineStep.captions, StepPhase.skipped, tr('off'));
      return;
    }

    // Re-shooting a scene changes the picture, never the read, so the subtitles
    // that were timed against it are still exactly right.
    if (_onlyShot >= 0 && _run.srtPath.isNotEmpty) {
      _setStep(PipelineStep.captions, StepPhase.skipped, tr('unchanged'));
      return;
    }

    final providerId = _text('captionsProvider');
    final model = _text('captionsModel').isEmpty ? 'whisper-1' : _text('captionsModel');

    _setStep(PipelineStep.captions, StepPhase.running);
    _setStatus(tr('Timing the subtitles...'));

    final task = ProviderFactory.transcribe(
      providerId,
      TranscribeRequest(
        apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
        model: model,
        audioPath: _run.voicePath,
      ),
    );

    if (task == null) {
      _log.warning(tr('No subtitle provider selected, skipping.'));
      _setStep(PipelineStep.captions, StepPhase.skipped);
      return;
    }

    try {
      final result = await _await(task, PipelineStep.captions);

      // Whisper bills the length of the audio it listened to.
      _recordUsage('captions', providerId, model,
          math.max(0.0, _run.voiceDuration) / 60.0);

      _run.srtPath =
          _writeArtifact(_captionsFile, utf8.encode('${result['srt'] ?? ''}'));
      _log.success(tr('Subtitles ready.'));
      _setStep(PipelineStep.captions, StepPhase.done);
    } on ProviderException catch (error) {
      _throwIfCancelling();
      // Subtitles are a nice-to-have: a failure here must not lose the video.
      _log.warning(tr('Subtitles unavailable (%1). Continuing without them.')
          .arg(error.message));
      _setStep(PipelineStep.captions, StepPhase.skipped, tr('failed'));
    }
  }

  // ---------------------------------------------------------------------
  // 6. Final cut
  // ---------------------------------------------------------------------
  //
  // Every shot is trimmed to its slot and the slots are laid end to end, so the
  // picture keeps moving for the whole ad without a single frame being
  // stretched or looped. One ffmpeg pass does the lot: trim, normalise,
  // concatenate, burn in the subtitles and mux the voice-over.

  Future<void> _stepAssemble() async {
    _setStep(PipelineStep.assemble, StepPhase.running);
    _setStatus(tr('Assembling the final video...'));

    final exe = _ffmpeg;
    if (exe.isEmpty) {
      _log.error(tr('FFmpeg is required to cut the shots together with the '
              'voice-over and the subtitles. Install it or set its path in '
              'Settings. Your generated files are in %1.')
          .arg(_run.dir));
      throw _RunFailed(tr('FFmpeg not found.'));
    }

    final usable = _run.shots.where((shot) => shot.clipPath.isNotEmpty).toList();
    if (usable.isEmpty) {
      throw _RunFailed(tr('No shot was rendered, so there is nothing to cut together.'));
    }

    final frame = _outputSize(
        _text('aspectRatio').isEmpty ? '9:16' : _text('aspectRatio'));
    final hasSubtitles = _run.srtPath.isNotEmpty;

    final args = <String>['-y', '-hide_banner'];
    for (final shot in usable) {
      args.addAll(['-i', p.basename(shot.clipPath)]);
    }
    args.addAll(['-i', p.basename(_run.voicePath)]);

    // Clips come from different models at different sizes and frame rates.
    // concat refuses to join streams that do not match, so each one is padded
    // to the same canvas and resampled to the same rate first.
    //
    // Every shot is then made exactly as long as its own line: trimmed if the
    // clip overran, and holding its last frame if it came back short. Because
    // each length is the measured length of that line's audio, the shots add up
    // to the voice-over on their own -- so nothing is stretched, nothing is
    // looped, and there is no -shortest deciding where the ad ends.
    final chains = <String>[];
    var concatInputs = '';
    var shortfall = 0.0;

    for (var i = 0; i < usable.length; ++i) {
      final shot = usable[i];
      final slot = shot.duration;
      final available =
          shot.clipDuration > 0 ? math.min(slot, shot.clipDuration) : slot;
      final pad = math.max(0.0, slot - available);
      shortfall += pad;

      var chain = '[$i:v]trim=0:${available.toStringAsFixed(3)},'
          'setpts=PTS-STARTPTS,'
          'scale=${frame.width}:${frame.height}:force_original_aspect_ratio=decrease,'
          'pad=${frame.width}:${frame.height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30';

      if (pad > 0.02) {
        chain += ',tpad=stop_mode=clone:stop_duration=${pad.toStringAsFixed(3)}';
      }

      chains.add('$chain[v$i]');
      concatInputs += '[v$i]';
    }

    if (shortfall > 0.5) {
      _log.warning(
          tr('The clips are %1s short in total; those shots hold their last frame.')
              .arg(shortfall.toStringAsFixed(1)));
    }

    var lastLabel = 'vc';
    chains.add('${concatInputs}concat=n=${usable.length}:v=1:a=0[vc]');
    if (hasSubtitles) {
      chains.add("[vc]subtitles=${Ffmpeg.escapeFilterPath(_captionsFile)}:"
          "force_style='$_subtitleStyle'[vs]");
      lastLabel = 'vs';
    }

    args.addAll([
      '-filter_complex', chains.join(';'),
      '-map', '[$lastLabel]',
      '-map', '${usable.length}:a:0',
      '-c:v', 'libx264',
      '-preset', 'medium',
      '-crf', '20',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'aac',
      '-b:a', '192k',
      '-movflags', '+faststart',
      _finalFile,
    ]);

    _log.info(tr('Cutting %1 shot(s) into %2x%3.')
        .arg(usable.length)
        .arg(frame.width)
        .arg(frame.height));

    final task = FfmpegTask(exe, args, workingDirectory: _run.dir);
    await _await(task, PipelineStep.assemble);

    _run.finalPath = p.join(_run.dir, _finalFile);
    if (!File(_run.finalPath).existsSync()) {
      throw _RunFailed(tr('FFmpeg finished but produced no file.'));
    }
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
            'kind': shot.kind,
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
      'captions': relative(_run.srtPath),
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
