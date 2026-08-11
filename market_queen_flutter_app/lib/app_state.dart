import 'core/http_util.dart';
import 'core/log_model.dart';
import 'core/pricing.dart';
import 'core/settings_store.dart';
import 'core/signal.dart';
import 'core/version.dart';
import 'i18n/translator.dart';
import 'media/ffmpeg.dart';
import 'models/ad_project.dart';
import 'models/asset_library.dart';
import 'models/casting.dart';
import 'models/image_forge.dart';
import 'models/library_model.dart';
import 'models/line_doctor.dart';
import 'models/studio_runner.dart';
import 'models/voice_booth.dart';
import 'models/workspace.dart';
import 'pipeline/pipeline.dart';
import 'providers/fal_schema.dart';
import 'providers/registry.dart';
import 'providers/types.dart';
import 'providers/voice_casting.dart';

/// The single object the UI talks to. It owns the engine pieces and exposes the
/// few OS-level helpers the interface needs.
class AppState {
  AppState._(
    this.settings,
    this.registry,
    this.pricing,
    this.log,
    this.translator,
  ) {
    // One caster for the whole app: the booth and the pipeline have to agree on
    // who is reading the ad, and they agree by sharing the record of it.
    voiceCasting = VoiceCasting(settings);
    pipeline = Pipeline(settings, registry, pricing, log, voiceCasting, falSchemas);
    project = AdProject(settings, registry);
    casting = Casting();
    actors = ActorLibrary();
    scenes = SceneLibrary();
    // The tree the studio browses. It has to be built after the actor library,
    // because importing a pre-projects draft rehouses that draft's actor in it.
    workspace = Workspace(project, actors);
    actorForge = ImageForge(
      settings,
      registry,
      pricing,
      log,
      scratchFolder: 'casting',
    );
    sceneForge = ImageForge(
      settings,
      registry,
      pricing,
      log,
      scratchFolder: 'scenery',
    );
    voiceBooth = VoiceBooth(settings, registry, pricing, log, voiceCasting);
    library = LibraryModel(settings);
    lineDoctor = LineDoctor(settings, registry, pricing, log);
    // Fires into the open ad's feed, which is where the canvas reads from. It
    // outlives any one ad: a batch sent just before you step back to the
    // project list still has somewhere to land.
    runner = StudioRunner(settings, registry, pricing, log, voiceCasting,
        falSchemas, project.feed);
  }

  /// Builds everything and loads the data files the models need before the
  /// first frame.
  static Future<AppState> create() async {
    final settings = SettingsStore();
    final registry = Registry();
    final pricing = Pricing(registry);
    final log = LogModel();
    final translator = Translator.instance;

    // The language has to be settled before anything builds a translated
    // string: the registry catalogue and the pipeline step labels are both
    // produced once, in Dart, rather than re-evaluated per frame.
    await translator.applyLanguage(settings.uiLanguage);
    // The registry was built a few lines above, while the catalogue was still
    // empty, so its notes came out in English and stayed there -- the listener
    // that would have caught the change is only wired up in `_wire()`, after
    // this. It went unnoticed while one note was on screen at a time; the
    // Models page now shows all of them at once.
    registry.retranslate();
    await pricing.load();

    final app = AppState._(settings, registry, pricing, log, translator);
    await app.casting.load();
    app._wire();
    return app;
  }

  final SettingsStore settings;
  final Registry registry;
  final Pricing pricing;
  final LogModel log;
  final Translator translator;

  late final Pipeline pipeline;

  /// The ad currently open in the editor.
  late final AdProject project;

  /// Projects and their ads.
  late final Workspace workspace;

  /// Single images, single clips, single readings: everything the composer can
  /// ask for that is not a whole ad.
  late final StudioRunner runner;

  /// What each fal model actually accepts, read from the model's own schema.
  /// Built first, because both the pipeline and the runner take it.
  final FalSchemas falSchemas = FalSchemas();

  /// How a person or a place is asked for -- the prompt scaffold, not a run.
  late final Casting casting;

  late final ActorLibrary actors;
  late final SceneLibrary scenes;

  /// One picture generator per editor, so an actor batch and a scene batch can
  /// never land in each other's strip.
  late final ImageForge actorForge;
  late final ImageForge sceneForge;

  /// Who reads the ad, worked out from the brief rather than picked by id.
  late final VoiceCasting voiceCasting;

  late final VoiceBooth voiceBooth;
  late final LineDoctor lineDoctor;
  late final LibraryModel library;

  /// Raised when the resolved ffmpeg path may have changed.
  final Signal ffmpegPathChanged = Signal();

  final Event<({String providerId, List<VoiceOption> voices})> voicesLoaded =
      Event();
  final Event<({String providerId, String error})> voicesFailed = Event();

  String get version => appVersion;

  /// Resolved ffmpeg binary, empty when it could not be found.
  String get ffmpegPath => Ffmpeg.resolve(settings.ffmpegPath);

  /// What Generate would run, priced and sent. Every caller goes through here
  /// so the estimate, the writing helpers and the pipeline all read the same
  /// ad, the same actor and the same scene.
  Map<String, Object?> request() =>
      project.toRequest(actors: actors, scenes: scenes);

  String _lastFfmpegPath = '';
  String _lastLanguage = '';

  void _wire() {
    _lastFfmpegPath = ffmpegPath;
    _lastLanguage = translator.currentLanguage;

    settings.addListener(() {
      final resolved = ffmpegPath;
      if (resolved != _lastFfmpegPath) {
        _lastFfmpegPath = resolved;
        ffmpegPathChanged.emit();
      }
      // Settings owns the choice; the translator carries it out.
      if (settings.uiLanguage != _lastLanguage &&
          settings.uiLanguage != translator.currentLanguage) {
        translator.applyLanguage(settings.uiLanguage);
      }
    });

    // Strings that Dart built once have to be rebuilt by hand; widget text goes
    // through tr() on every build and follows on its own.
    translator.addListener(() {
      _lastLanguage = translator.currentLanguage;
      registry.retranslate();
      pipeline.retranslate();
    });

    // A finished run should show up in the library right away.
    pipeline.finished.listen((_) => library.refresh());

    log.info(
      tr(
        'Market Queen %1. Add your API keys in Settings to get started.',
      ).arg(version),
    );
    if (ffmpegPath.isEmpty) {
      log.warning(
        tr(
          'FFmpeg was not found. It is needed for the final render; '
          'set its path in Settings.',
        ),
      );
    }
  }

  /// Deletes an actor and takes it off every ad that cast it.
  void deleteActor(String id) {
    actors.remove(id);
    workspace.forgetAsset(actorId: id);
  }

  /// Deletes a scene and takes it off every ad that used it.
  void deleteScene(String id) {
    scenes.remove(id);
    workspace.forgetAsset(sceneId: id);
  }

  /// Asks the provider for the voices on the user's account.
  Future<void> loadVoices(String providerId) async {
    final credential = registry.credentialFor(providerId);
    final task = ProviderFactory.voiceCatalog(
      providerId,
      settings.apiKey(credential),
    );

    if (task == null) {
      voicesFailed.emit((
        providerId: providerId,
        error: tr('This provider has no voice list.'),
      ));
      return;
    }

    try {
      final result = await task.run();
      final voices = (result['voices'] as List?)?.cast<VoiceOption>() ?? const [];
      voicesLoaded.emit((providerId: providerId, voices: voices));
    } on ProviderException catch (error) {
      voicesFailed.emit((providerId: providerId, error: error.message));
    }
  }

  void dispose() {
    runner.dispose();
    pipeline.dispose();
    workspace.dispose();
    project.dispose();
    actors.dispose();
    scenes.dispose();
    actorForge.dispose();
    sceneForge.dispose();
    voiceBooth.dispose();
    lineDoctor.dispose();
    library.dispose();
    registry.dispose();
    settings.dispose();
  }
}
