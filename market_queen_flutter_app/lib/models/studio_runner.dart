import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart' show Http, ProviderException, TaskCancelled;
import '../core/log_model.dart';
import '../core/paths.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../media/ffmpeg.dart';
import '../providers/capabilities.dart';
import '../providers/model_schemas.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import '../providers/video_providers.dart' show FalReferenceUploadTask;
import '../providers/voice_casting.dart';
import 'asset_library.dart' show isAudioPath, isVideoPath;
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
    this.resolution = '',
    this.audio = true,
    this.size = '',
    this.quality = '',
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

  /// Video only, and only when the model offers a choice: "720p", "1080p".
  final String resolution;

  /// Video only. Whether the model should also generate a soundtrack, for the
  /// ones that can. Ignored by models with no such switch.
  final bool audio;

  /// Pictures only, and only where the model offers a choice: "1K", "2K", "4K".
  final String size;

  /// Pictures only: the provider's own quality value. Empty everywhere else.
  final String quality;
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
    this._modelSchemas,
    this.feed,
  );

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;
  final VoiceCasting _casting;
  final ModelSchemas _modelSchemas;

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

  /// Priced before it is sent, for the confirmation modal and the line under
  /// the prompt. Unknown when the catalogue has no line for the model, or when
  /// what it bills by is not something the order knows -- which is the honest
  /// answer either way: a made-up figure next to a spend button is worse than
  /// none.
  CostEstimate estimate(GenerationOrder order) {
    final unit = _pricing.unitPrice(modelFor(order.category, order.seconds));
    if (unit == null) return CostEstimate.unknown;

    final count = order.count < 1 ? 1 : order.count;

    // How many units one press buys, in whatever the model bills by. It used to
    // be "seconds x count for video, count for everything else", which
    // overcharged the models that sell a clip flat and quoted the price of one
    // thousand characters as the price of a reading.
    final units = switch (unit.unit) {
      'second' => order.seconds * count.toDouble(),
      'video' || 'image' => count.toDouble(),
      'kchars' => math.max(1, order.prompt.trim().length) / 1000.0,
      // A minute of audio to subtitle, a million tokens: neither is known
      // before the thing exists.
      _ => 0.0,
    };
    if (units <= 0) return CostEstimate.unknown;

    return CostEstimate(true, unit.amount * units);
  }

  /// The provider the composer's settings column currently names for a
  /// category, falling back to the first one the registry lists.
  String providerFor(String category) => _registry.providerOrDefault(
        category,
        _settings.prefString('${category}Provider'),
      );

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

    if (order.category == 'voice') {
      await _sendVoice(batch, order, providerId, model, apiKey, dir);
      return batch;
    }

    // Read once per batch: what this model calls its opening frame, which of
    // duration, resolution and audio it actually declares, and how much
    // reference material it will take.
    //
    // Waited for rather than read: this is the send path, and a fal model whose
    // schema has not landed yet would be handed an opening frame it may not
    // take. A directly-called model answers from the catalogue without a round
    // trip.
    final capabilities = order.category == 'video'
        ? await _modelSchemas.ensure(providerId, model)
        : const ModelCapabilities();

    final shaped = capabilities.known
        ? capabilities.videoInput(
            seconds: order.seconds,
            resolution: order.resolution,
            audio: order.audio,
            aspectRatio: order.aspectRatio,
          )
        : null;

    // Which of the three ways to ask, decided by what was dropped in rather
    // than by which model was picked. One still is an opening frame; a second
    // picture, a clip or a recording is reference material; nothing at all
    // shoots from the prompt. The model narrows it further -- Hailuo has no
    // reference mode however much you attach -- and [modeFor] falls through to
    // what it can actually do.
    final counted = _countByKind(order.references);
    final mode = capabilities.modeFor(
      images: counted.images,
      videos: counted.videos,
      audios: counted.audios,
    );

    // Done once and reused by every request in the batch -- ten variations off
    // the same clip should carry it once.
    var references = VideoReferences.none;
    var referenceUri = '';

    if (mode == VideoMode.referenceToVideo) {
      try {
        references =
            await _gatherReferences(capabilities, order.references, apiKey, providerId);
      } on ProviderException catch (error) {
        _failWholeBatch(batch, error.message);
        return batch;
      }
      if (references.isEmpty) {
        _failWholeBatch(
          batch,
          tr('This model works from reference material. Drop in the picture, '
              'the clip or the recording it should work from.'),
        );
        return batch;
      }
      //: %1 is a list like "@Image1 = face.png, @Video1 = ad.mp4"
      _log.info(tr('Reference material: %1. Point at it from the prompt.')
          .arg(_handleList(references, order.references)));
    } else if (mode == VideoMode.imageToVideo) {
      referenceUri = await _firstImageDataUri(order.references);
      if (order.category == 'video' && referenceUri.isEmpty) {
        _failWholeBatch(
          batch,
          tr('This model animates a still. Drop in the picture it should start '
              'from, or pick one that shoots from the prompt alone.'),
        );
        return batch;
      }
    }
    // textToVideo carries neither, which is the whole point of it.

    if (order.category == 'video') {
      _log.info(switch (mode) {
        //: %1 is a model name
        VideoMode.textToVideo => tr('Shooting from the prompt on %1.').arg(model),
        VideoMode.imageToVideo => tr('Animating your still on %1.').arg(model),
        VideoMode.referenceToVideo =>
          tr('Working from your reference material on %1.').arg(model),
      });
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
            imageField: shaped?.imageField ?? '',
            extraInput: shaped?.input ?? const {},
            references: references,
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
            size: order.size,
            quality: order.quality,
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
    // The transcriber the Models page has chosen, rather than OpenAI's Whisper
    // whatever it says. Groq serves the same weights on a free tier, which is
    // the whole reason that choice exists -- and the bar underneath the prompt
    // now names the model it is about to use, so naming one and calling another
    // is no longer merely wasteful.
    final providerId = providerFor('captions');
    final model = modelFor('captions');

    final batch = CanvasBatch(
      id: CanvasFeed.newId(),
      kind: CanvasKind.video,
      prompt: tr('Subtitles burned in'),
      createdAt: DateTime.now(),
      modelLabel: _registry.modelLabel(providerId, model),
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
        providerId,
        TranscribeRequest(
          apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
          model: model,
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

  // Fal's published ceilings for reference material, and the counts the model
  // itself declares. Both live on [ModelCapabilities] so the bar can draw the
  // same numbers this enforces: a file over the limit comes back as a rejection
  // from the API halfway through a paid run, so it is stopped here with a
  // sentence that says which file and why.
  static const _maxImageBytes = ModelCapabilities.maxImageBytes;
  static const _maxVideoBytes = ModelCapabilities.maxVideoBytes;
  static const _maxAudioBytes = ModelCapabilities.maxAudioBytes;

  /// How many of each modality were dropped in, before any model has had a say.
  /// This is what decides whether the request is an opening frame or a pile of
  /// references, so it counts files rather than what the model would accept.
  ({int images, int videos, int audios}) _countByKind(List<String> paths) {
    var images = 0;
    var videos = 0;
    var audios = 0;

    for (final path in paths) {
      if (isVideoPath(path)) {
        videos += 1;
      } else if (isAudioPath(path)) {
        audios += 1;
      } else {
        images += 1;
      }
    }
    return (images: images, videos: videos, audios: audios);
  }

  /// Sorts what was dropped into the bar by modality and hands it over in
  /// whichever form the provider takes.
  ///
  /// Two forms, and it is a question of who is storing the file. fal has its
  /// own storage, so material bought through it is uploaded and travels as
  /// urls -- which is the only sane way to move a 200 MB clip. The direct
  /// providers have no storage this app can write to, so their references are
  /// inlined as data URIs, and that only stretches to stills.
  ///
  /// A modality the model does not declare is dropped rather than sent: an
  /// endpoint rejects a field it never had.
  Future<VideoReferences> _gatherReferences(
    ModelCapabilities capabilities,
    List<String> paths,
    String apiKey,
    String providerId,
  ) async {
    return ModelSchemas.fetches(providerId)
        ? _uploadReferences(capabilities, paths, apiKey)
        : _inlineReferences(capabilities, paths);
  }

  /// References for a directly-called provider, as data URIs.
  ///
  /// Stills only, and the refusal is deliberate rather than a silent drop: a
  /// clip the user attached and paid to have ignored is worse than being told
  /// it cannot be sent. Every one of these APIs takes a reference video as a
  /// url it can fetch, and this app has nowhere to put one -- so the honest
  /// answer is that it is not wired yet, not that the model cannot do it.
  Future<VideoReferences> _inlineReferences(
    ModelCapabilities capabilities,
    List<String> paths,
  ) async {
    final images = <String>[];

    for (final path in paths) {
      if (isVideoPath(path) || isAudioPath(path)) {
        throw ProviderException(
          //: %1 is a file name
          tr('%1 can only be sent to this provider as a hosted link, which the '
                  'app cannot make yet. Stills work; clips and recordings do '
                  'not.')
              .arg(p.basename(path)),
        );
      }
      if (capabilities.imagesField.isEmpty) continue;

      // Through the same converter the single-reference path uses, so a
      // screenshot saved as AVIF or HEIC still arrives as something the model
      // will look at.
      final uri = await imageDataUri(Ffmpeg.resolve(_settings.ffmpegPath), path);
      if (uri.isEmpty) throw ProviderException(unreadableImage(path));

      final data = Http.dataUriPayload(uri);
      if (data.length > _maxImageBytes) {
        throw ProviderException(_tooBig(path, _maxImageBytes));
      }
      images.add(uri);
    }

    final limit = capabilities.referenceLimits.images;
    if (images.length > limit) {
      //: %1 is a number of files
      _log.warning(tr('Only the first %1 were sent; the rest were left out.')
          .arg(limit));
      images.removeRange(limit, images.length);
    }

    return images.isEmpty
        ? VideoReferences.none
        : VideoReferences(
            images: images,
            imagesField: capabilities.imagesField,
          );
  }

  /// The same pile, put in fal's storage and returned as urls under the names
  /// this model gave its lists.
  ///
  /// Uploaded rather than inlined because of the clips: a reference video is
  /// allowed to be 200 MB, and base64 in a JSON body is not a serious way to
  /// move that.
  Future<VideoReferences> _uploadReferences(
    ModelCapabilities capabilities,
    List<String> paths,
    String apiKey,
  ) async {
    final images = <UploadFile>[];
    final videos = <UploadFile>[];
    final audios = <UploadFile>[];

    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;

      if (isVideoPath(path)) {
        if (capabilities.videosField.isEmpty) continue;
        videos.add(_readForUpload(file, _maxVideoBytes));
      } else if (isAudioPath(path)) {
        if (capabilities.audiosField.isEmpty) continue;
        audios.add(_readForUpload(file, _maxAudioBytes));
      } else {
        if (capabilities.imagesField.isEmpty) continue;
        // Through the same converter the single-reference path uses, so a
        // screenshot saved as AVIF or HEIC still arrives as something the model
        // will look at.
        final uri = await imageDataUri(Ffmpeg.resolve(_settings.ffmpegPath), path);
        if (uri.isEmpty) throw ProviderException(unreadableImage(path));

        var mimeType = '';
        final data = Http.dataUriPayload(uri, mimeType: (value) => mimeType = value);
        if (data.length > _maxImageBytes) {
          throw ProviderException(_tooBig(path, _maxImageBytes));
        }
        images.add(UploadFile(data, mimeType, p.basename(path)));
      }
    }

    final limits = capabilities.referenceLimits;
    _trim(images, limits.images);
    _trim(videos, limits.videos);
    _trim(audios, limits.audios);

    if (images.isEmpty && videos.isEmpty && audios.isEmpty) {
      return VideoReferences.none;
    }

    final task = FalReferenceUploadTask(
      apiKey: apiKey,
      images: images,
      videos: videos,
      audios: audios,
    );
    task.onProgress(_log.info);
    _tasks.add(task);

    final result = await task.run();
    List<String> urls(String key) => [
      for (final url in (result[key] as List? ?? const [])) '$url',
    ];

    return VideoReferences(
      images: urls('images'),
      videos: urls('videos'),
      audios: urls('audios'),
      imagesField: capabilities.imagesField,
      videosField: capabilities.videosField,
      audiosField: capabilities.audiosField,
    );
  }

  UploadFile _readForUpload(File file, int maxBytes) {
    final data = file.readAsBytesSync();
    if (data.length > maxBytes) throw ProviderException(_tooBig(file.path, maxBytes));
    return UploadFile(
      data,
      Http.mediaTypeOf(file.path, data).toString(),
      p.basename(file.path),
    );
  }

  String _tooBig(String path, int maxBytes) =>
      //: %1 is a file name, %2 a size such as "200 MB"
      tr('%1 is too large to send as a reference. The limit is %2.')
          .arg(p.basename(path))
          .arg('${maxBytes ~/ (1024 * 1024)} MB');

  /// Keeps the first [limit] and says so, rather than letting the API refuse
  /// the whole request over the eleventh file.
  void _trim(List<UploadFile> files, int limit) {
    if (files.length <= limit) return;
    //: %1 is a number of files
    _log.warning(tr('Only the first %1 were sent; the rest were left out.')
        .arg(limit));
    files.removeRange(limit, files.length);
  }

  /// "@Image1 = face.png, @Video1 = ad.mp4" -- the mapping the prompt has to
  /// use, which is otherwise invisible.
  String _handleList(VideoReferences references, List<String> paths) {
    final names = [
      for (final path in paths)
        if (!isVideoPath(path) && !isAudioPath(path)) p.basename(path),
      for (final path in paths)
        if (isVideoPath(path)) p.basename(path),
      for (final path in paths)
        if (isAudioPath(path)) p.basename(path),
    ];

    final handles = references.handles;
    return [
      for (var i = 0; i < handles.length && i < names.length; ++i)
        '${handles[i]} = ${names[i]}',
    ].join(', ');
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
