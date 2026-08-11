import 'package:flutter/foundation.dart';

/// Which of the three ways of asking for a clip a model is being used in.
///
/// Not three models and not three menu entries: one model, and the mode falls
/// out of what has been dropped in. Seedance 2.5 shoots from a prompt, animates
/// a still and rebuilds an ad from thirty references, all on the same model id
/// and the same endpoint -- what changes is the shape of the request. Making
/// the user pick "Seedance 2.5 reference" from a list would be asking them to
/// restate something the attachments already say.
enum VideoMode {
  /// Prompt only.
  textToVideo,

  /// One still to animate forward from.
  imageToVideo,

  /// A pile of material the prompt points at by handle -- @Image1, @Video1,
  /// @Audio1 -- with no opening frame at all.
  referenceToVideo,
}

/// What one model actually accepts.
///
/// Two sources, one type. For the direct providers it is [declared] below,
/// written from each provider's own API reference. For the two Kling endpoints
/// still bought through fal it is read from their OpenAPI schema at run time,
/// because fal's catalogue moves faster than a release does.
///
/// It exists because the models disagree wildly and the disagreements are not
/// guessable: Seedance takes 4 to 30 seconds as an integer, Hailuo takes 6 or
/// 10 and nothing between, Veo wants 4, 6 or 8 and forces 8 above 720p, Luma
/// spells the same idea `"5s"`. Guessing from substrings in the model id --
/// which is what this replaced -- produced both halves of the same failure:
/// options never offered because we did not know they existed, and fields sent
/// to models that reject unknown fields outright.
@immutable
class ModelCapabilities {
  const ModelCapabilities({
    this.modes = const {VideoMode.imageToVideo},
    this.durations = const [],
    this.durationMin = 0,
    this.durationMax = 0,
    this.defaultDuration = '',
    this.durationIsNumber = false,
    this.resolutions = const [],
    this.defaultResolution = '',
    this.aspectRatios = const [],
    this.audioField = '',
    this.defaultAudio = true,
    this.imageField = '',
    this.imagesField = '',
    this.videosField = '',
    this.audiosField = '',
    this.imagesMax = 0,
    this.videosMax = 0,
    this.audiosMax = 0,
    this.known = false,
  });

  /// The ways this model can be asked for a clip.
  final Set<VideoMode> modes;

  /// The exact tokens the model's `duration` enum lists, in its own spelling.
  /// Sent back verbatim, because "8s" and 8 are not interchangeable.
  final List<String> durations;

  /// For the models that take any whole number of seconds in a range rather
  /// than a fixed list -- Seedance's 4 to 30, LTX's per-second billing. The
  /// menu is built from the range; the request carries the exact number.
  final int durationMin;
  final int durationMax;

  final String defaultDuration;

  /// Whether `duration` is declared as a number rather than a string.
  final bool durationIsNumber;

  final List<String> resolutions;
  final String defaultResolution;

  /// Empty when the model has no aspect-ratio input -- Kling v3 has none, and
  /// sending one is an error rather than a no-op.
  final List<String> aspectRatios;

  /// The name of the "make sound too" switch, or empty when the model has no
  /// such thing. It is `generate_audio` on most and `enable_audio` on a few.
  final String audioField;
  final bool defaultAudio;

  /// What the opening frame is called here.
  final String imageField;

  /// The list inputs of a multimodal endpoint, when it has them.
  ///
  /// A reference request is a different animal from an image-to-video one: it
  /// has no opening frame. It takes a pile of files across the three
  /// modalities, and the prompt addresses them by handle -- `@Image1`,
  /// `@Video1`, `@Audio1`. That is what makes it possible to hand it a real ad
  /// and a new face and ask for the same ad with that face in it.
  final String imagesField;
  final String videosField;
  final String audiosField;

  /// How many of each the endpoint will take.
  ///
  /// They differ by a lot -- Seedance 2.5 takes thirty pictures and ten clips,
  /// Seedance 2.0 takes nine and three, Veo takes three pictures and no clips
  /// at all -- and the only place that number used to be written down was the
  /// rejection that came back after the upload.
  final int imagesMax;
  final int videosMax;
  final int audiosMax;

  /// False when nothing is known -- an unread fal schema. The caller then falls
  /// back to what it did before rather than pretending the model has no
  /// options.
  final bool known;

  bool get supportsAudio => audioField.isNotEmpty;

  bool get takesReferences =>
      imagesField.isNotEmpty || videosField.isNotEmpty || audiosField.isNotEmpty;

  /// Platform ceilings, applied on top of whatever a model declares. They live
  /// here rather than in the runner because the bar has to draw the same
  /// numbers the send path enforces -- a counter that says 0/30 over a request
  /// that is trimmed at 9 is worse than no counter.
  static const platformMaxImages = 30;
  static const platformMaxVideos = 10;
  static const platformMaxAudios = 10;

  static const maxImageBytes = 30 * 1024 * 1024;
  static const maxVideoBytes = 200 * 1024 * 1024;
  static const maxAudioBytes = 15 * 1024 * 1024;

  ({int images, int videos, int audios}) get referenceLimits => (
        images: _limit(imagesField, imagesMax, platformMaxImages),
        videos: _limit(videosField, videosMax, platformMaxVideos),
        audios: _limit(audiosField, audiosMax, platformMaxAudios),
      );

  static int _limit(String field, int declared, int ceiling) {
    if (field.isEmpty) return 0;
    if (declared <= 0) return ceiling;
    return declared < ceiling ? declared : ceiling;
  }

  /// Which way to ask, given what has been dropped in.
  ///
  /// One still and nothing else is an opening frame, because that is what
  /// somebody means by dropping one picture on a video prompt. Anything more --
  /// a second picture, a clip, a recording -- is reference material, because
  /// there is no such thing as a second opening frame. With nothing attached it
  /// shoots from the prompt.
  ///
  /// Each step falls through to what the model can actually do, so a model with
  /// only one mode always gets that one.
  VideoMode modeFor({int images = 0, int videos = 0, int audios = 0}) {
    final wantsReferences = videos > 0 || audios > 0 || images > 1;

    if (wantsReferences && modes.contains(VideoMode.referenceToVideo)) {
      return VideoMode.referenceToVideo;
    }
    if (images > 0 && modes.contains(VideoMode.imageToVideo)) {
      return VideoMode.imageToVideo;
    }
    if (images == 0 && videos == 0 && audios == 0) {
      if (modes.contains(VideoMode.textToVideo)) return VideoMode.textToVideo;
    }
    // Nothing fits: hand back the one thing it does, so the task can say what
    // is missing in its own words rather than being handed a mode it has never
    // heard of.
    if (modes.contains(VideoMode.imageToVideo)) return VideoMode.imageToVideo;
    if (modes.contains(VideoMode.referenceToVideo)) {
      return VideoMode.referenceToVideo;
    }
    return VideoMode.textToVideo;
  }

  /// The seconds a duration token stands for, for pricing and planning.
  /// Returns 0 for "auto" and anything unparseable.
  static int secondsOf(String token) {
    final digits = RegExp(r'\d+').firstMatch(token);
    return digits == null ? 0 : int.parse(digits.group(0)!);
  }

  /// Every length this model will accept, as tokens in its own spelling.
  ///
  /// A fixed enum is returned as it stands. A range is turned into a ladder --
  /// the useful lengths rather than all twenty-seven of them, because a menu
  /// with an entry for every second between 4 and 30 is a menu nobody reads --
  /// with the ends always included so the model's real ceiling is reachable.
  /// That ceiling is the point: Seedance 2.5 runs to thirty seconds and the
  /// studio was offering it five.
  List<String> get durationChoices {
    if (durations.isNotEmpty) return durations;
    if (durationMax <= 0) return const [];

    const ladder = [3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30];
    final choices = <int>{
      durationMin > 0 ? durationMin : ladder.first,
      for (final step in ladder)
        if (step >= durationMin && step <= durationMax) step,
      durationMax,
    }.where((seconds) => seconds >= durationMin && seconds <= durationMax).toList()
      ..sort();

    return [for (final seconds in choices) '$seconds'];
  }

  /// The token closest to [seconds] that this model will accept.
  ///
  /// Asking Hailuo for 8 seconds when it offers 6 and 10 has to resolve to one
  /// of the two rather than being sent as-is and rejected. "auto" is never
  /// chosen by proximity -- it is only used when it is the only thing on offer.
  String durationFor(int seconds) {
    if (durationMax > 0 && durations.isEmpty) {
      final clamped = seconds.clamp(
        durationMin > 0 ? durationMin : 1,
        durationMax,
      );
      return '$clamped';
    }
    if (durations.isEmpty) return '';

    var best = '';
    var bestGap = 1 << 30;
    var bestValue = 0;

    for (final token in durations) {
      final value = secondsOf(token);
      if (value == 0) continue;

      final gap = (value - seconds).abs();
      // A tie goes to the longer clip. Eight seconds of speech on a model that
      // offers six and ten is the everyday case, and the two failures are not
      // equal: ten seconds is trimmed to eight in the cut and costs a little
      // more, while six cuts two seconds off the line and the shot ends
      // mid-sentence.
      if (gap < bestGap || (gap == bestGap && value > bestValue)) {
        bestGap = gap;
        bestValue = value;
        best = token;
      }
    }
    if (best.isNotEmpty) return best;
    return defaultDuration.isEmpty ? durations.first : defaultDuration;
  }

  /// The value the settings column should start from: what the model itself
  /// defaults to, or the first thing it offers.
  String get firstResolution => resolutions.isEmpty
      ? ''
      : (resolutions.contains(defaultResolution)
          ? defaultResolution
          : resolutions.first);

  /// Everything this model wants for one clip, in its own spelling.
  ///
  /// Returned rather than built at each call site so the composer's preview,
  /// the runner and the pipeline cannot disagree about what will be sent.
  ({String imageField, Map<String, Object?> input}) videoInput({
    required int seconds,
    String resolution = '',
    bool audio = true,
    String aspectRatio = '',
  }) {
    final input = <String, Object?>{};

    final token = durationFor(seconds);
    if (token.isNotEmpty) {
      input['duration'] =
          durationIsNumber || durations.isEmpty ? secondsOf(token) : token;
    }
    if (resolutions.contains(resolution)) {
      input['resolution'] = resolution;
    }
    if (audioField.isNotEmpty) {
      input[audioField] = audio;
    }
    // Only when the model declares one: Kling v3 has no aspect ratio at all,
    // and sending it there is an error rather than a no-op.
    if (aspectRatios.contains(aspectRatio)) {
      input['aspect_ratio'] = aspectRatio;
    }

    return (imageField: imageField, input: input);
  }

  /// Bumped whenever a new field is read out of a fal schema. A cache written
  /// by an older build knows nothing about it, and silently answering "this
  /// model takes no references" for a fortnight is worse than one extra fetch.
  static const cacheVersion = 4;

  Map<String, Object?> toJson() => {
        'v': cacheVersion,
        'durations': durations,
        'defaultDuration': defaultDuration,
        'durationIsNumber': durationIsNumber,
        'resolutions': resolutions,
        'defaultResolution': defaultResolution,
        'aspectRatios': aspectRatios,
        'audioField': audioField,
        'defaultAudio': defaultAudio,
        'imageField': imageField,
        'imagesField': imagesField,
        'videosField': videosField,
        'audiosField': audiosField,
        'imagesMax': imagesMax,
        'videosMax': videosMax,
        'audiosMax': audiosMax,
      };

  factory ModelCapabilities.fromJson(Map<String, Object?> json) {
    List<String> list(Object? value) => [
          if (value is List)
            for (final entry in value) '$entry',
        ];

    final imagesField = '${json['imagesField'] ?? ''}';
    final videosField = '${json['videosField'] ?? ''}';
    final audiosField = '${json['audiosField'] ?? ''}';
    final imageField = '${json['imageField'] ?? ''}';

    return ModelCapabilities(
      // A fal endpoint is one shape or the other and says so by which fields
      // it declares. Nothing in the schema says whether the prompt alone would
      // be accepted, so that is not claimed.
      modes: {
        if (imagesField.isNotEmpty ||
            videosField.isNotEmpty ||
            audiosField.isNotEmpty)
          VideoMode.referenceToVideo,
        if (imageField.isNotEmpty) VideoMode.imageToVideo,
      },
      durations: list(json['durations']),
      defaultDuration: '${json['defaultDuration'] ?? ''}',
      durationIsNumber: json['durationIsNumber'] == true,
      resolutions: list(json['resolutions']),
      defaultResolution: '${json['defaultResolution'] ?? ''}',
      aspectRatios: list(json['aspectRatios']),
      audioField: '${json['audioField'] ?? ''}',
      defaultAudio: json['defaultAudio'] != false,
      imageField: imageField,
      imagesField: imagesField,
      videosField: videosField,
      audiosField: audiosField,
      imagesMax: (json['imagesMax'] as num?)?.toInt() ?? 0,
      videosMax: (json['videosMax'] as num?)?.toInt() ?? 0,
      audiosMax: (json['audiosMax'] as num?)?.toInt() ?? 0,
      known: true,
    );
  }

  // -------------------------------------------------------------------------
  // What the direct providers accept
  // -------------------------------------------------------------------------
  //
  // Written from each provider's own API reference -- the working, with a
  // source URL behind every line, is in docs/audit-fournisseurs-api.md. These
  // are the numbers the menus offer and the numbers the request carries, so a
  // model that can do thirty seconds is offered thirty seconds.
  //
  // `imageField` is the app's own name for the opening frame rather than the
  // provider's: the direct tasks build their own bodies and each one knows what
  // its API calls that field. What the caller needs from here is only whether
  // there *is* one.

  static const Map<String, ModelCapabilities> declared = {
    // ---- BytePlus, Seedance ------------------------------------------------
    // The reference model of the list. Thirty images, ten clips and ten
    // recordings in one request, and thirty seconds of output.
    'dreamina-seedance-2-5-260628': ModelCapabilities(
      modes: {
        VideoMode.textToVideo,
        VideoMode.imageToVideo,
        VideoMode.referenceToVideo,
      },
      durationMin: 4,
      durationMax: 30,
      durationIsNumber: true,
      resolutions: ['480p', '720p'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16', '1:1', '4:3', '3:4'],
      audioField: 'generate_audio',
      imageField: 'first_frame',
      imagesField: 'reference_image',
      videosField: 'reference_video',
      audiosField: 'reference_audio',
      imagesMax: 30,
      videosMax: 10,
      audiosMax: 10,
      known: true,
    ),
    'dreamina-seedance-2-0-260128': ModelCapabilities(
      modes: {
        VideoMode.textToVideo,
        VideoMode.imageToVideo,
        VideoMode.referenceToVideo,
      },
      durationMin: 4,
      durationMax: 15,
      durationIsNumber: true,
      resolutions: ['480p', '720p', '1080p', '4k'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16', '1:1', '4:3', '3:4'],
      audioField: 'generate_audio',
      imageField: 'first_frame',
      imagesField: 'reference_image',
      videosField: 'reference_video',
      audiosField: 'reference_audio',
      imagesMax: 9,
      videosMax: 3,
      audiosMax: 3,
      known: true,
    ),
    'dreamina-seedance-2-0-fast-260128': ModelCapabilities(
      modes: {
        VideoMode.textToVideo,
        VideoMode.imageToVideo,
        VideoMode.referenceToVideo,
      },
      durationMin: 4,
      durationMax: 15,
      durationIsNumber: true,
      resolutions: ['480p', '720p'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16', '1:1', '4:3', '3:4'],
      audioField: 'generate_audio',
      imageField: 'first_frame',
      imagesField: 'reference_image',
      videosField: 'reference_video',
      audiosField: 'reference_audio',
      imagesMax: 9,
      videosMax: 3,
      audiosMax: 3,
      known: true,
    ),
    'dreamina-seedance-2-0-mini-260615': ModelCapabilities(
      modes: {
        VideoMode.textToVideo,
        VideoMode.imageToVideo,
        VideoMode.referenceToVideo,
      },
      durationMin: 4,
      durationMax: 15,
      durationIsNumber: true,
      resolutions: ['480p', '720p'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16', '1:1', '4:3', '3:4'],
      audioField: 'generate_audio',
      imageField: 'first_frame',
      imagesField: 'reference_image',
      videosField: 'reference_video',
      audiosField: 'reference_audio',
      imagesMax: 9,
      videosMax: 3,
      audiosMax: 3,
      known: true,
    ),
    // The 1.x models take a first frame and a prompt and nothing else.
    'seedance-1-5-pro-251215': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 12,
      durationIsNumber: true,
      resolutions: ['480p', '720p', '1080p'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16', '1:1', '4:3', '3:4'],
      audioField: 'generate_audio',
      imageField: 'first_frame',
      known: true,
    ),

    // ---- LTX ---------------------------------------------------------------
    // Billed by the second with no minimum and no duration enum published, so
    // the ladder runs the full documented range and the request carries the
    // exact number.
    'ltx-2-3-fast': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 20,
      durationIsNumber: true,
      resolutions: ['720p', '1080p', '1440p', '4k'],
      defaultResolution: '720p',
      audioField: 'generate_audio',
      defaultAudio: false,
      imageField: 'image_uri',
      known: true,
    ),
    'ltx-2-3-pro': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 20,
      durationIsNumber: true,
      resolutions: ['720p', '1080p', '1440p', '4k'],
      defaultResolution: '720p',
      audioField: 'generate_audio',
      defaultAudio: false,
      imageField: 'image_uri',
      known: true,
    ),
    'ltx-2-5-fast': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 20,
      durationIsNumber: true,
      resolutions: ['720p', '1080p', '1440p', '4k'],
      defaultResolution: '720p',
      audioField: 'generate_audio',
      defaultAudio: false,
      imageField: 'image_uri',
      known: true,
    ),
    'ltx-2-5-pro': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 20,
      durationIsNumber: true,
      resolutions: ['720p', '1080p'],
      defaultResolution: '720p',
      audioField: 'generate_audio',
      defaultAudio: false,
      imageField: 'image_uri',
      known: true,
    ),

    // ---- Google Veo --------------------------------------------------------
    // Three lengths and nothing between, and 1080p and 4K are eight seconds
    // only -- which the settings column cannot express, so the task clamps.
    // Audio is not a switch here: Veo always writes its own.
    // No reference mode declared: Veo does take up to three reference images,
    // but the exact shape of that field is not on any page reachable without a
    // Google Cloud console login, and a body guessed at is a paid request that
    // 400s. Two stills therefore animate from the first rather than silently
    // becoming something else.
    'veo-3.1-generate-preview': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['4', '6', '8'],
      defaultDuration: '8',
      durationIsNumber: true,
      resolutions: ['720p', '1080p', '4k'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16'],
      imageField: 'image',
      known: true,
    ),
    'veo-3.1-fast-generate-preview': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['4', '6', '8'],
      defaultDuration: '8',
      durationIsNumber: true,
      resolutions: ['720p', '1080p', '4k'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16'],
      imageField: 'image',
      known: true,
    ),

    // ---- MiniMax -----------------------------------------------------------
    'MiniMax-H3': ModelCapabilities(
      modes: {
        VideoMode.textToVideo,
        VideoMode.imageToVideo,
        VideoMode.referenceToVideo,
      },
      durationMin: 4,
      durationMax: 15,
      durationIsNumber: true,
      resolutions: ['768P', '2K'],
      defaultResolution: '768P',
      aspectRatios: ['16:9', '9:16', '1:1', '4:3', '3:4', '21:9'],
      imageField: 'first_frame',
      imagesField: 'image_url',
      videosField: 'video_url',
      audiosField: 'audio_url',
      imagesMax: 9,
      videosMax: 3,
      audiosMax: 3,
      known: true,
    ),
    'MiniMax-Hailuo-2.3': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['6', '10'],
      defaultDuration: '6',
      durationIsNumber: true,
      resolutions: ['512P', '768P', '1080P'],
      defaultResolution: '768P',
      imageField: 'first_frame_image',
      known: true,
    ),
    'MiniMax-Hailuo-2.3-Fast': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['6', '10'],
      defaultDuration: '6',
      resolutions: ['512P', '768P', '1080P'],
      defaultResolution: '768P',
      durationIsNumber: true,
      imageField: 'first_frame_image',
      known: true,
    ),

    // ---- OpenAI Sora -------------------------------------------------------
    // Sizes rather than resolutions, and the opening frame has to match the
    // chosen one exactly -- the task resizes it.
    'sora-2': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['4', '8', '12'],
      defaultDuration: '4',
      resolutions: ['720p'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16'],
      imageField: 'input_reference',
      known: true,
    ),
    'sora-2-pro': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['4', '8', '12'],
      defaultDuration: '4',
      resolutions: ['720p', '1080p'],
      defaultResolution: '720p',
      aspectRatios: ['16:9', '9:16'],
      imageField: 'input_reference',
      known: true,
    ),

    // ---- xAI ---------------------------------------------------------------
    // No duration enum and no resolution input published; the SDK example
    // passes a plain number of seconds.
    'grok-imagine-video': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 12,
      durationIsNumber: true,
      imageField: 'image_url',
      known: true,
    ),
    'grok-imagine-video-1.5': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durationMin: 4,
      durationMax: 12,
      durationIsNumber: true,
      imageField: 'image_url',
      known: true,
    ),

    // ---- Luma --------------------------------------------------------------
    // Spells its lengths with the unit, and takes a closing frame as well as
    // an opening one.
    'ray-2': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['5s', '9s'],
      defaultDuration: '5s',
      resolutions: ['540p', '720p', '1080p', '4k'],
      defaultResolution: '720p',
      aspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4', '21:9', '9:21'],
      imageField: 'frame0',
      known: true,
    ),
    'ray-flash-2': ModelCapabilities(
      modes: {VideoMode.textToVideo, VideoMode.imageToVideo},
      durations: ['5s', '9s'],
      defaultDuration: '5s',
      resolutions: ['540p', '720p', '1080p', '4k'],
      defaultResolution: '720p',
      aspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4', '21:9', '9:21'],
      imageField: 'frame0',
      known: true,
    ),
  };
}
