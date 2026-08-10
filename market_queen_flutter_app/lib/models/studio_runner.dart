import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart' show ProviderException, TaskCancelled;
import '../core/log_model.dart';
import '../core/paths.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../media/ffmpeg.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import '../providers/voice_casting.dart';
import 'asset_library.dart' show isVideoPath;
import 'canvas_feed.dart';

/// What the composer hands over when the send button is pressed.
///
/// One shape for the three kinds it can ask for, because the three differ only
/// in which fields they read: an image ignores [seconds], a voice ignores
/// [references]. Keeping them apart would mean three near-identical call paths
/// through the same folder-making, key-fetching, file-writing code.
class GenerationOrder {
  const GenerationOrder({
    required this.kind,
    required this.category,
    required this.prompt,
    this.references = const [],
    this.aspectRatio = '9:16',
    this.seconds = 5,
    this.count = 1,
    this.voiceSource = const {},
  });

  /// How the canvas draws the result.
  final CanvasKind kind;

  /// Which shelf of the registry the model comes off: "image", "video",
  /// "voice", "upscale". Separate from [kind] because enlarging a picture
  /// produces an image from a different set of models, and a caption burn
  /// produces a video without asking a model at all.
  final String category;

  final String prompt;

  /// Pictures and clips dropped into the bar. The first picture is what a model
  /// taking a single reference is handed -- for video, that is the opening
  /// frame.
  final List<String> references;

  final String aspectRatio;
  final int seconds;

  /// How many at once. They go out in parallel and land in the feed as they
  /// arrive, in whatever order that turns out to be.
  final int count;

  /// Voice only: the ad's own request, which already carries who is reading it
  /// -- the cast voice if there is one, the brief to search on if there is not.
  /// The composer has no voice picker of its own, because a second answer to
  /// "who is speaking" is a second thing to keep in step with the actor.
  final Map<String, Object?> voiceSource;
}

/// Fires what the composer ordered and files the results in the feed.
///
/// Deliberately thin: it makes a folder, resolves a provider and a model,
/// fans out [GenerationOrder.count] requests at once and writes each reply to
/// disk. There is no planning, no montage and no dependency between the
/// requests -- that is the pipeline's job, and this is the other half of the
/// studio, where you ask for one thing and get it.
class StudioRunner extends ChangeNotifier {
  StudioRunner(
    this._settings,
    this._registry,
    this._pricing,
    this._log,
    this._casting,
    this.feed,
  );

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;
  final VoiceCasting _casting;

  /// The feed everything lands in. Owned by the ad, not by this object: closing
  /// an ad swaps the feed's contents while a batch may still be in the air, and
  /// a batch whose ad has gone simply finds no home for its result.
  final CanvasFeed feed;

  final List<ProviderTask> _tasks = [];

  /// Requests that have left and not yet come back, across every batch.
  int _outstanding = 0;

  bool get running => _outstanding > 0;

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  /// Abandons everything in the air. The tiles they would have filled are
  /// marked failed by their own error path, so nothing is left spinning.
  void cancel() {
    for (final task in _tasks) {
      if (!task.isFinished) task.cancel();
    }
    _tasks.clear();
  }

  // ---- What a batch would cost ------------------------------------------

  /// Priced before it is sent, for the confirmation modal. Unknown when the
  /// catalogue has no line for the model, which is the honest answer -- a
  /// made-up figure on a spending confirmation is worse than none.
  CostEstimate estimate(GenerationOrder order) {
    final unit = _pricing.unitPrice(modelFor(order.category, order.seconds));
    if (unit == null) return CostEstimate.unknown;

    // Video is billed by the second everywhere the catalogue knows about; the
    // rest are billed per call.
    final units = order.category == 'video'
        ? order.seconds * order.count
        : order.count;
    return CostEstimate(true, unit.amount * units);
  }

  /// The provider the composer's settings column currently names for a
  /// category, falling back to the first one the registry lists.
  String providerFor(String category) {
    final saved = _settings.prefString('${category}Provider');
    final known = _registry
        .providers(category)
        .any((provider) => provider.id == saved);
    return known ? saved : _registry.defaultProvider(category);
  }

  /// The model id it names, with "auto" already resolved into something real.
  String modelFor(String category, [int seconds = 0]) {
    final providerId = providerFor(category);
    final saved = _settings.prefString('${category}Model');
    final wanted = saved.isEmpty
        ? _registry.provider(providerId)?.defaultModel ?? ''
        : saved;
    return _registry.resolveModel(providerId, wanted, seconds);
  }

  String modelLabel(String category, [int seconds = 0]) => _registry.modelLabel(
    providerFor(category),
    modelFor(category, seconds),
  );

  // ---- Sending ------------------------------------------------------------

  /// Puts a batch in the feed and fans its requests out.
  ///
  /// Returns as soon as they are away: the caller is a button handler, and the
  /// results arrive through the feed rather than through this future. A failure
  /// to even start -- no folder, no such provider -- lands in the batch as a
  /// failed tile rather than being thrown, because the feed is where the user
  /// is looking.
  Future<CanvasBatch> send(GenerationOrder order) async {
    final providerId = providerFor(order.category);
    final model = modelFor(order.category, order.seconds);
    final count = order.count < 1 ? 1 : order.count;

    final batch = CanvasBatch(
      id: CanvasFeed.newId(),
      kind: order.kind,
      prompt: order.prompt.trim(),
      createdAt: DateTime.now(),
      modelLabel: _registry.modelLabel(providerId, model),
      aspectRatio: order.aspectRatio,
      references: List.of(order.references),
      items: [
        for (var i = 0; i < count; ++i) CanvasItem(id: CanvasFeed.newId()),
      ],
    );
    feed.add(batch);

    final dir = _folder(order.kind);
    if (dir.isEmpty) {
      _failWholeBatch(
        batch,
        //: %1 is a folder path
        tr('Could not create a folder in %1.').arg(_settings.projectsDir),
      );
      return batch;
    }

    //: %1 is a number, %2 a model name
    _log.info(tr('Generating %1 with %2.').arg(count).arg(model));

    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));

    // Read once and reused by every request in the batch: ten videos off the
    // same opening frame should not decode and re-encode that frame ten times.
    final referenceUri = order.category == 'voice'
        ? ''
        : await _firstImageDataUri(order.references);

    if (order.category == 'voice') {
      await _sendVoice(batch, order, providerId, model, apiKey, dir);
      return batch;
    }

    for (var i = 0; i < batch.items.length; ++i) {
      final item = batch.items[i];

      final task = switch (order.category) {
        'video' => ProviderFactory.video(
          providerId,
          VideoRequest(
            apiKey: apiKey,
            model: model,
            prompt: order.prompt.trim(),
            imageDataUri: referenceUri,
            aspectRatio: order.aspectRatio,
            durationSeconds: order.seconds,
          ),
        ),
        _ => ProviderFactory.image(
          providerId,
          ImageRequest(
            apiKey: apiKey,
            model: model,
            prompt: order.prompt.trim(),
            aspectRatio: order.aspectRatio,
            referenceImageDataUri: referenceUri,
          ),
        ),
      };

      if (task == null) {
        _settle(
          batch,
          item,
          //: %1 is a provider id
          error: tr('No provider called %1.').arg(providerId),
        );
        continue;
      }

      _tasks.add(task);
      _outstanding += 1;
      unawaited(
        _collect(
          batch,
          item,
          task,
          p.join(dir, '${_stamp(batch.createdAt)}-${i + 1}'),
          order.category == 'video' ? 'mp4' : 'png',
        ),
      );
    }

    notifyListeners();
    return batch;
  }

  /// The voice-over tab. One request whatever the count says: ten readings of
  /// the same line by the same voice would be ten copies of one file.
  Future<void> _sendVoice(
    CanvasBatch batch,
    GenerationOrder order,
    String providerId,
    String model,
    String apiKey,
    String dir,
  ) async {
    // Everything after the first tile is meaningless here, so the batch is
    // trimmed rather than left showing nine skeletons that will never fill.
    if (batch.items.length > 1) batch.items.removeRange(1, batch.items.length);
    final item = batch.items.first;

    final VoiceOption voice;
    try {
      voice = await _casting.voiceFor(
        providerId: providerId,
        apiKey: apiKey,
        modelId: model,
        source: order.voiceSource,
        onTask: _tasks.add,
      );
    } on ProviderException catch (error) {
      _settle(batch, item, error: error.message);
      return;
    }

    final task = ProviderFactory.voice(
      providerId,
      VoiceRequest(
        apiKey: apiKey,
        model: model,
        voiceId: voice.id,
        text: order.prompt.trim(),
      ),
    );

    if (task == null) {
      //: %1 is a provider id
      _settle(batch, item, error: tr('No provider called %1.').arg(providerId));
      return;
    }

    _tasks.add(task);
    _outstanding += 1;
    await _collect(
      batch,
      item,
      task,
      p.join(dir, '${_stamp(batch.createdAt)}-voice'),
      'mp3',
    );
  }

  /// Times a clip's speech and burns the result into a copy of it.
  ///
  /// Two steps and no model choice: Whisper reads the audio out of the file,
  /// then ffmpeg draws the .srt over the picture. The style is the pipeline's
  /// -- bold white with a hard outline, sitting above the bottom edge -- so a
  /// clip captioned here and one captioned by a full render look the same.
  Future<CanvasBatch> burnCaptions({required String videoPath}) async {
    final batch = CanvasBatch(
      id: CanvasFeed.newId(),
      kind: CanvasKind.video,
      prompt: tr('Subtitles burned in'),
      createdAt: DateTime.now(),
      modelLabel: 'Whisper',
      aspectRatio: '',
      references: [videoPath],
      items: [CanvasItem(id: CanvasFeed.newId())],
    );
    feed.add(batch);

    final item = batch.items.first;
    final dir = _folder(CanvasKind.video);

    if (dir.isEmpty || !File(videoPath).existsSync()) {
      _settle(batch, item, error: tr('That clip is no longer on disk.'));
      return batch;
    }

    final ffmpeg = Ffmpeg.resolve(_settings.ffmpegPath);
    if (ffmpeg.isEmpty) {
      _settle(
        batch,
        item,
        error: tr('FFmpeg was not found. Install it, or set its path in '
            'Settings.'),
      );
      return batch;
    }

    _outstanding += 1;
    notifyListeners();

    final stamp = _stamp(batch.createdAt);
    final srtName = '$stamp-captions.srt';
    final outputName = '$stamp-captioned.mp4';

    try {
      final transcribe = ProviderFactory.transcribe(
        'openai-whisper',
        TranscribeRequest(
          apiKey: _settings.apiKey('openai'),
          model: 'whisper-1',
          audioPath: videoPath,
          language: '',
        ),
      );
      if (transcribe == null) {
        _settle(batch, item, error: tr('No transcription provider.'));
        return batch;
      }

      _tasks.add(transcribe);
      final timed = await transcribe.run();
      final srt = '${timed['srt'] ?? ''}';
      if (srt.trim().isEmpty) {
        _settle(batch, item, error: tr('Nothing was said in that clip.'));
        return batch;
      }

      File(p.join(dir, srtName)).writeAsStringSync(srt);

      // ffmpeg runs *in* the folder and names the subtitle file by its
      // basename: the `subtitles=` filter parses its argument, and a Windows
      // absolute path with a drive letter in it is not something that parser
      // survives.
      final burn = FfmpegTask(ffmpeg, [
        '-hide_banner',
        '-y',
        '-i', videoPath,
        '-vf',
        'subtitles=${Ffmpeg.escapeFilterPath(srtName)}:'
            "force_style='$_captionStyle'",
        '-c:a', 'copy',
        outputName,
      ], workingDirectory: dir);

      _tasks.add(burn);
      await burn.run();

      _settle(batch, item, path: p.join(dir, outputName));
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Subtitles failed: %1').arg(error.message));
      }
      _settle(
        batch,
        item,
        error: error is TaskCancelled ? tr('Cancelled.') : error.message,
      );
    } on FileSystemException {
      _settle(batch, item, error: tr('Could not write the subtitle file.'));
    }

    return batch;
  }

  /// Character for character the style the pipeline burns, so a clip captioned
  /// here and one captioned by a full render are indistinguishable.
  static const _captionStyle =
      'FontName=Arial,FontSize=22,Bold=1,PrimaryColour=&H00FFFFFF,'
      'OutlineColour=&H00000000,BorderStyle=1,Outline=3,Shadow=0,'
      'Alignment=2,MarginV=90';

  /// Awaits one request, writes what came back and settles its tile.
  Future<void> _collect(
    CanvasBatch batch,
    CanvasItem item,
    ProviderTask task,
    String pathWithoutExtension,
    String fallbackExtension,
  ) async {
    try {
      final result = await task.run();

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      if (data.isEmpty) {
        _settle(batch, item, error: tr('The provider returned nothing.'));
        return;
      }

      final extension = '${result['extension'] ?? fallbackExtension}';
      final path = '$pathWithoutExtension.$extension';

      try {
        File(path).writeAsBytesSync(data);
      } on FileSystemException {
        //: %1 is a file path
        _settle(batch, item, error: tr('Could not write %1.').arg(path));
        return;
      }

      _settle(
        batch,
        item,
        path: path,
        seconds: (result['durationSeconds'] as num?)?.toDouble() ?? 0,
      );
    } on ProviderException catch (error) {
      // A cancelled task is the user's own doing and needs no red tile of its
      // own -- but the tile still has to stop spinning.
      if (error is! TaskCancelled) {
        _log.error(tr('Generation failed: %1').arg(error.message));
      }
      _settle(
        batch,
        item,
        error: error is TaskCancelled ? tr('Cancelled.') : error.message,
      );
    }
  }

  void _settle(
    CanvasBatch batch,
    CanvasItem item, {
    String path = '',
    String error = '',
    double seconds = 0,
  }) {
    if (_outstanding > 0) _outstanding -= 1;

    feed.settle(
      batch.id,
      item.id,
      status: error.isEmpty ? CanvasStatus.done : CanvasStatus.failed,
      path: path,
      error: error,
      seconds: seconds,
    );
    notifyListeners();
  }

  void _failWholeBatch(CanvasBatch batch, String error) {
    for (final item in batch.items) {
      feed.settle(
        batch.id,
        item.id,
        status: CanvasStatus.failed,
        error: error,
      );
    }
    _log.error(error);
    notifyListeners();
  }

  // ---- Files --------------------------------------------------------------

  /// One folder per kind under the projects directory, so the canvas output
  /// sits beside the rendered ads rather than hiding in the config dir.
  String _folder(CanvasKind kind) {
    final leaf = switch (kind) {
      CanvasKind.video => 'clips',
      CanvasKind.audio => 'voice',
      _ => 'stills',
    };
    return Paths.ensureDir(p.join(_settings.projectsDir, 'studio', leaf));
  }

  Future<String> _firstImageDataUri(List<String> references) async {
    for (final path in references) {
      if (isVideoPath(path)) continue;
      // Through ffmpeg when the Dart codecs cannot read it: a reference dragged
      // off a shop page is as likely to be AVIF as anything.
      final uri = await imageDataUri(
        Ffmpeg.resolve(_settings.ffmpegPath),
        path,
      );
      if (uri.isEmpty) _log.warning(unreadableImage(path));
      return uri;
    }
    return '';
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
