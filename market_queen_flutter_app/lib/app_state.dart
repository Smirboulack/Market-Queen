import 'core/http_util.dart';
import 'core/log_model.dart';
import 'core/pricing.dart';
import 'core/settings_store.dart';
import 'core/signal.dart';
import 'core/version.dart';
import 'i18n/translator.dart';
import 'media/ffmpeg.dart';
import 'models/actor_library.dart';
import 'models/ad_project.dart';
import 'models/casting.dart';
import 'models/director.dart';
import 'models/library_model.dart';
import 'models/line_doctor.dart';
import 'models/voice_booth.dart';
import 'pipeline/pipeline.dart';
import 'providers/registry.dart';
import 'providers/types.dart';

/// The single object the UI talks to. It owns the engine pieces and exposes the
/// few OS-level helpers the interface needs.
///
/// This is the Flutter counterpart of the QML `App` singleton: same members,
/// same lifetimes, wired with listeners instead of signal/slot connections.
class AppState {
  AppState._(this.settings, this.registry, this.pricing, this.log, this.translator) {
    pipeline = Pipeline(settings, registry, pricing, log);
    project = AdProject(settings, registry);
    casting = Casting(settings, registry, pricing, log);
    actors = ActorLibrary();
    voiceBooth = VoiceBooth(settings, registry, pricing, log);
    library = LibraryModel(settings);
    // One casting instance: the director works from the same house rules the
    // portraits were cast against.
    director = Director(settings, registry, pricing, casting, log);
    lineDoctor = LineDoctor(settings, registry, pricing, log);
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
  late final AdProject project;
  late final Casting casting;
  late final ActorLibrary actors;
  late final VoiceBooth voiceBooth;
  late final Director director;
  late final LineDoctor lineDoctor;
  late final LibraryModel library;

  /// Raised when the resolved ffmpeg path may have changed.
  final Signal ffmpegPathChanged = Signal();

  final Event<({String providerId, List<VoiceOption> voices})> voicesLoaded = Event();
  final Event<({String providerId, String error})> voicesFailed = Event();

  String get version => appVersion;

  /// Resolved ffmpeg binary, empty when it could not be found.
  String get ffmpegPath => Ffmpeg.resolve(settings.ffmpegPath);

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

    log.info(tr('Market Queen %1. Add your API keys in Settings to get started.')
        .arg(version));
    if (ffmpegPath.isEmpty) {
      log.warning(tr('FFmpeg was not found. It is needed for the final render; '
          'set its path in Settings.'));
    }
  }

  /// Asks the provider for the voices on the user's account.
  Future<void> loadVoices(String providerId) async {
    final credential = registry.credentialFor(providerId);
    final task =
        ProviderFactory.voiceCatalog(providerId, settings.apiKey(credential));

    if (task == null) {
      voicesFailed.emit(
          (providerId: providerId, error: tr('This provider has no voice list.')));
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
    pipeline.dispose();
    project.dispose();
    casting.dispose();
    actors.dispose();
    voiceBooth.dispose();
    director.dispose();
    lineDoctor.dispose();
    library.dispose();
    registry.dispose();
    settings.dispose();
  }
}
