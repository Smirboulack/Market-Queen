import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What one *image* model accepts beyond the shape of the frame.
///
/// The same idea as [ModelCapabilities] and for the same reason: the models
/// disagree, the disagreements are not guessable, and a field sent to a model
/// that does not declare it is a paid request that 400s. What differs is that
/// none of these are fetched -- every image provider in the app is called
/// directly, so this is written from each one's own API reference.
///
/// Deliberately short. A model is in here only when its own documentation says
/// what it takes: OpenAI publishes three quality steps and prices each of them,
/// BytePlus and Black Forest Labs both size in pixels with a published ceiling.
/// Gemini, Ideogram, Bria and xAI are absent because their published request
/// bodies have no such field -- Ideogram's rendering speed is already half of
/// its model id, and Grok's two entries are the same model at two qualities.
/// An absent model simply gets no extra rows in the settings panel, which is
/// the honest answer rather than a menu that does nothing.
@immutable
class ImageCapabilities {
  const ImageCapabilities({
    this.sizes = const [],
    this.defaultSize = '',
    this.qualities = const [],
    this.defaultQuality = '',
    this.maxMegapixels = 0,
    this.aspectRatios = const [],
    this.explicitSizes = false,
    this.sizeSetsShape = false,
  });

  /// What the Size menu offers, in one of two spellings.
  ///
  /// Most of them are "1K", "2K", "4K" -- the long edge, in the shorthand
  /// people actually use -- and what goes on the wire is worked out from the
  /// aspect ratio by [pixelsFor], because those models size in pixels and take
  /// any frame you ask for.
  ///
  /// OpenAI does not: it publishes a closed list of frames and refuses
  /// anything else, so its entries are the literal strings the API takes
  /// ("1536x1024", "auto"). [explicitSizes] tells the two apart, and the task
  /// sends an explicit one verbatim rather than deriving a frame from a ratio
  /// the model was never offered.
  final List<String> sizes;
  final String defaultSize;

  /// True when [sizes] holds the API's own values rather than shorthand for
  /// a frame this app has to work out in pixels.
  ///
  /// Declared rather than guessed from the strings, because the two overlap:
  /// "1K" is shorthand on Seedream, where it means "long edge 1024, you sort
  /// out the rest from the ratio", and a literal on Gemini, where `image_size`
  /// takes that exact token.
  final bool explicitSizes;

  /// True when picking a size also picks the shape, so there is no separate
  /// ratio to choose.
  ///
  /// Only OpenAI: its sizes are frames -- "1536x1024" is a size *and* a
  /// landscape. Everywhere else the two are independent fields and both
  /// menus stand: Gemini takes `image_size` and `aspect_ratio` separately, so
  /// 4K and 4:5 are one request, and folding them together would lose eight
  /// of its ten shapes.
  final bool sizeSetsShape;

  /// The shapes this model will draw, in its own spelling.
  ///
  /// Empty means the three the app has always offered -- vertical, square,
  /// wide -- which is what every model here takes. A model that publishes more
  /// lists them, and the Format menu offers exactly what it lists: Gemini
  /// draws ten, and four of them are the ones an ad actually wants.
  final List<String> aspectRatios;

  /// The provider's own quality values, sent verbatim.
  final List<String> qualities;
  final String defaultQuality;

  /// The largest frame the model will produce, when it publishes one. A 1:1
  /// frame at 2K is 4.2 megapixels, which is just past what FLUX.2 will take,
  /// so the ceiling is applied rather than the request being refused.
  final double maxMegapixels;

  bool get picksSize => sizes.length > 1;
  bool get picksQuality => qualities.length > 1;

  static ImageCapabilities of(String modelId) =>
      declared[modelId] ?? const ImageCapabilities();

  /// The saved value when this model still offers it, otherwise the model's own
  /// default -- so switching from a model with 4K to one without cannot leave
  /// "4K" showing under a model that has never heard of it.
  String sizeOr(String saved) =>
      sizes.contains(saved) ? saved : (defaultSize.isEmpty ? '' : defaultSize);

  /// The frame to ask for when the shape is not negotiable.
  ///
  /// [sizeOr] answers the studio's question -- what a still asked for by hand
  /// is drawn at. This answers the pipeline's, which is narrower: a frame of
  /// an ad has to be the shape of the ad. A saved size that disagrees is
  /// dropped rather than corrected, because a model that takes an explicit
  /// size also knows which frames it sells for a given ratio -- and on the
  /// models where the size wins outright over the ratio, honouring it is how a
  /// vertical ad gets shot in 4K landscape.
  String frameFor(String saved, String aspectRatio) {
    final asked = sizeOr(saved);

    final frame = asked.toLowerCase().split('x');
    if (frame.length != 2) return asked; // "auto", "1K": not a literal frame
    final width = double.tryParse(frame[0]) ?? 0;
    final height = double.tryParse(frame[1]) ?? 0;
    if (width <= 0 || height <= 0) return asked;

    final ratio = aspectRatio.split(':');
    final wide = double.tryParse(ratio.first) ?? 0;
    final tall = ratio.length > 1 ? double.tryParse(ratio[1]) ?? 0 : 0;
    if (wide <= 0 || tall <= 0) return asked;

    return ((width / height) - (wide / tall)).abs() <= 0.05 ? asked : '';
  }

  String qualityOr(String saved) => qualities.contains(saved)
      ? saved
      : (defaultQuality.isEmpty ? '' : defaultQuality);

  /// The long edge a size token stands for.
  static int edgeOf(String token) => switch (token) {
    '1K' => 1024,
    '2K' => 2048,
    '4K' => 4096,
    _ => 0,
  };

  /// The frame to ask for, in pixels: [token]'s long edge laid over [aspect],
  /// rounded to a multiple of 32 and pulled back under [maxMegapixels] when the
  /// model publishes one.
  ({int width, int height}) pixelsFor(String token, String aspect) {
    final edge = edgeOf(token) == 0 ? edgeOf(defaultSize) : edgeOf(token);
    // Nothing picked and nothing declared -- a model id pasted into "Other
    // model id...". Two thousand is what this app asked every pixel-sized model
    // for before any of them had a menu, so an unknown one keeps getting it.
    final long = edge == 0 ? 2048 : edge;

    final ratio = _ratio(aspect);
    var width = ratio >= 1 ? long.toDouble() : long * ratio;
    var height = ratio >= 1 ? long / ratio : long.toDouble();

    if (maxMegapixels > 0) {
      final megapixels = width * height / 1e6;
      if (megapixels > maxMegapixels) {
        final scale = math.sqrt(maxMegapixels / megapixels);
        width *= scale;
        height *= scale;
      }
    }

    return (width: _round32(width), height: _round32(height));
  }

  /// Width over height, 1 when the ratio is missing or unreadable.
  static double _ratio(String aspect) {
    final parts = aspect.split(':');
    if (parts.length != 2) return 1;
    final width = double.tryParse(parts[0]) ?? 0;
    final height = double.tryParse(parts[1]) ?? 0;
    if (width <= 0 || height <= 0) return 1;
    return width / height;
  }

  /// Down to a multiple of 32, which every one of these endpoints is happy
  /// with, and never below the smallest frame any of them accepts.
  static int _round32(double value) {
    final rounded = (value / 32).floor() * 32;
    return rounded < 256 ? 256 : rounded;
  }

  // -------------------------------------------------------------------------

  /// The shapes worth offering on a model that will draw any of them.
  ///
  /// Seedream, SeedEdit and FLUX.2 are sized in pixels: this app works the
  /// frame out from the ratio itself -- see [pixelsFor] -- so the list is an
  /// editorial choice rather than a limit, and it is the same list Gemini
  /// publishes so that changing model does not change the menu under you.
  /// FLUX.1 Kontext takes a ratio string and documents everything from 21:9
  /// to 9:21, which covers all of these.
  ///
  /// Ideogram, Bria and xAI are deliberately absent: Ideogram maps a ratio
  /// onto one of its own enumerated resolutions and rejects anything else,
  /// and the other two publish a set this app has not verified. Offering a
  /// shape a model refuses is a paid request that 400s.
  static const List<String> _anyRatio = _geminiRatios;

  /// Every shape Gemini's image models draw, in the guide's order.
  static const List<String> _geminiRatios = [
    '1:1',
    '2:3',
    '3:2',
    '3:4',
    '4:3',
    '4:5',
    '5:4',
    '9:16',
    '16:9',
    '21:9',
  ];

  static const Map<String, ImageCapabilities> declared = {
    // ---- OpenAI ------------------------------------------------------------
    // Both menus come straight off the image-generation guide. The seven
    // frames are the ones it enumerates and the only ones the endpoint takes:
    // a maximum edge of 3840, both edges a multiple of 16, at most 3:1, and
    // between 0.66 and 8.29 megapixels -- so the list is closed and is sent
    // verbatim rather than derived from an aspect ratio.
    //
    // "auto" leads both menus because it is the API's own default: the model
    // picks the frame and the effort from the prompt. It is the right thing to
    // ask for when you do not care, and the wrong thing when you are counting
    // cents, which is why both are on the menu rather than one being assumed.
    'gpt-image-2': ImageCapabilities(
      sizes: [
        'auto',
        '1024x1024',
        '1536x1024',
        '1024x1536',
        '2048x2048',
        '2048x1152',
        '3840x2160',
        '2160x3840',
      ],
      defaultSize: 'auto',
      explicitSizes: true,
      sizeSetsShape: true,
      qualities: ['auto', 'low', 'medium', 'high'],
      defaultQuality: 'auto',
    ),

    // ---- Google, Gemini ----------------------------------------------------
    // `image_size` and `aspect_ratio` are fields on `response_format`, and
    // both take the API's own tokens, so what the menus hold is what goes on
    // the wire. The ten ratios are the guide's list in full; 2.5 Flash Image
    // predates the field and draws 1024x1024 whatever it is told, so it
    // declares neither and is sent neither.
    'gemini-3-pro-image': ImageCapabilities(
      sizes: ['1K', '2K', '4K'],
      defaultSize: '1K',
      explicitSizes: true,
      aspectRatios: _geminiRatios,
    ),
    'gemini-3.1-flash-image': ImageCapabilities(
      sizes: ['512px', '1K', '2K', '4K'],
      defaultSize: '1K',
      explicitSizes: true,
      aspectRatios: _geminiRatios,
    ),
    // 1K and nothing else, so no Size menu: a one-entry list is a control
    // that cannot be operated. The token is still sent, because the field is
    // what the endpoint prices from.
    'gemini-3.1-flash-lite-image': ImageCapabilities(
      sizes: ['1K'],
      defaultSize: '1K',
      explicitSizes: true,
      aspectRatios: _geminiRatios,
    ),
    'gemini-2.5-flash-image': ImageCapabilities(
      aspectRatios: _geminiRatios,
    ),

    // ---- BytePlus, Seedream ------------------------------------------------
    // Sized in pixels, and billed in two tiers: flat up to 2.36 megapixels,
    // roughly double above it. That is exactly the step between 2K and 4K, so
    // the menu is where the user finds out.
    'seedream-4-5-251128': ImageCapabilities(
      sizes: ['1K', '2K', '4K'],
      defaultSize: '2K',
      aspectRatios: _anyRatio,
    ),
    'seedream-5-0-lite-260128': ImageCapabilities(
      sizes: ['1K', '2K', '4K'],
      defaultSize: '2K',
      aspectRatios: _anyRatio,
    ),
    'dola-seedream-5-0-pro-260628': ImageCapabilities(
      sizes: ['1K', '2K', '4K'],
      defaultSize: '2K',
      aspectRatios: _anyRatio,
    ),
    'seededit-3-0-i2i-250628': ImageCapabilities(
      sizes: ['1K', '2K', '4K'],
      defaultSize: '2K',
      aspectRatios: _anyRatio,
    ),

    // ---- Black Forest Labs, FLUX.2 -----------------------------------------
    // width/height in pixels, 64 minimum, four megapixels of output maximum --
    // which is why there is no 4K here and why a square 2K frame comes back a
    // little under 2048.
    'flux-2-pro': ImageCapabilities(
      sizes: ['1K', '2K'],
      defaultSize: '1K',
      maxMegapixels: 4,
      aspectRatios: _anyRatio,
    ),
    'flux-2-flex': ImageCapabilities(
      sizes: ['1K', '2K'],
      defaultSize: '1K',
      maxMegapixels: 4,
      aspectRatios: _anyRatio,
    ),
    'flux-2-max': ImageCapabilities(
      sizes: ['1K', '2K'],
      defaultSize: '1K',
      maxMegapixels: 4,
      aspectRatios: _anyRatio,
    ),
    'flux-2-klein-9b': ImageCapabilities(
      sizes: ['1K', '2K'],
      defaultSize: '1K',
      maxMegapixels: 4,
      aspectRatios: _anyRatio,
    ),
    // Kontext is the other way round from FLUX.2: an `aspect_ratio` string
    // and no pixel fields at all, so it declares the shapes and no sizes.
    'flux-kontext-pro': ImageCapabilities(aspectRatios: _anyRatio),
    'flux-2-klein-4b': ImageCapabilities(
      sizes: ['1K', '2K'],
      defaultSize: '1K',
      maxMegapixels: 4,
      aspectRatios: _anyRatio,
    ),
  };
}

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
    this.inlinesImages = false,
    this.inlinesVideos = false,
    this.inlinesAudios = false,
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

  /// Which of the three lists this endpoint will take as a `data:` URI.
  ///
  /// The distinction only exists for the providers this app calls directly,
  /// because it has nowhere to host a file: anything it cannot inline, it
  /// cannot send at all. And the endpoints genuinely differ. BytePlus takes a
  /// still or a recording as base64 -- `data:image/png;base64,...`,
  /// `data:audio/wav;base64,...` -- and a reference *video* only as a url it
  /// can fetch or an asset id from its own library. MiniMax takes all three as
  /// base64 under the same 64 MB body ceiling.
  ///
  /// Left false for the fal endpoints, where it is not consulted: fal has
  /// storage, so the material is uploaded and travels as urls.
  final bool inlinesImages;
  final bool inlinesVideos;
  final bool inlinesAudios;

  /// False when nothing is known -- an unread fal schema. The caller then falls
  /// back to what it did before rather than pretending the model has no
  /// options.
  final bool known;

  bool get supportsAudio => audioField.isNotEmpty;

  bool get takesReferences =>
      imagesField.isNotEmpty ||
      videosField.isNotEmpty ||
      audiosField.isNotEmpty;

  /// Platform ceilings, applied on top of whatever a model declares. They live
  /// here rather than in the runner because the bar has to draw the same
  /// numbers the send path enforces -- a counter that says 0/30 over a request
  /// that is trimmed at 9 is worse than no counter.
  ///
  /// Below what the biggest model would take: Seedance 2.5 declares thirty
  /// stills, ten clips and ten recordings, and a request that size is neither
  /// something anybody assembles by hand in a prompt bar nor something the
  /// 64 MB body ceiling leaves room for.
  static const platformMaxImages = 10;
  static const platformMaxVideos = 3;
  static const platformMaxAudios = 3;

  static const maxImageBytes = 30 * 1024 * 1024;
  static const maxVideoBytes = 200 * 1024 * 1024;
  static const maxAudioBytes = 15 * 1024 * 1024;

  /// What a whole request may weigh once everything in it is base64. Both
  /// multimodal providers this app calls directly publish the same number, and
  /// both say it about the body rather than about any one file.
  static const maxInlineBodyBytes = 64 * 1024 * 1024;

  ({int images, int videos, int audios}) get referenceLimits => (
    images: _limit(imagesField, imagesMax, platformMaxImages),
    videos: _limit(videosField, videosMax, platformMaxVideos),
    audios: _limit(audiosField, audiosMax, platformMaxAudios),
  );

  /// The same, for a provider this app has to inline for: a modality the
  /// endpoint will not read as base64 is not offered at all, because there is
  /// no second way to hand it over.
  ({int images, int videos, int audios}) get inlineLimits {
    final declared = referenceLimits;
    return (
      images: inlinesImages ? declared.images : 0,
      videos: inlinesVideos ? declared.videos : 0,
      audios: inlinesAudios ? declared.audios : 0,
    );
  }

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
  /// A range is expanded one second at a time so every supported duration
  /// is available in the menu.
  List<String> get durationChoices {
    if (durations.isNotEmpty) return durations;
    if (durationMax <= 0) return const [];

    final min = durationMin > 0 ? durationMin : 1;

    return [
      for (var seconds = min; seconds <= durationMax; seconds++) '$seconds',
    ];
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
      input['duration'] = durationIsNumber || durations.isEmpty
          ? secondsOf(token)
          : token;
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
      // 1080p was documented for this model after the rest of this table was
      // written. The price catalogue already carried the rate for it -- billed
      // at 11.7 per million tokens rather than 10.7 -- so the only thing
      // missing was the menu offering it.
      resolutions: ['480p', '720p', '1080p'],
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
      // Stills and recordings go in as base64; a reference clip is a url this
      // app cannot make. See [inlinesImages].
      inlinesImages: true,
      inlinesAudios: true,
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
      inlinesImages: true,
      inlinesAudios: true,
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
      inlinesImages: true,
      inlinesAudios: true,
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
      inlinesImages: true,
      inlinesAudios: true,
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
      // The one endpoint here that reads all three as base64: a public url and
      // an `mm_file://` id are alternatives rather than the only way in.
      inlinesImages: true,
      inlinesVideos: true,
      inlinesAudios: true,
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

/// Which of the four delivery dials a voice engine actually honours.
///
/// The dials are not a house style laid over every provider: they are
/// ElevenLabs' `voice_settings`, and a provider that has no equivalent field
/// simply drops them. Drawn all four regardless, the panel was telling the user
/// that MiniMax reads with the stability and the style exaggeration they had
/// set, when MiniMax is sent a voice id and a speed and nothing else -- three
/// controls that did nothing, and no way to find that out except by paying for
/// two reads and hearing no difference.
///
/// The stability steps come from the same place they always did: v3 has three
/// settings rather than a continuum, and a value between them is snapped.
class VoiceCapabilities {
  const VoiceCapabilities({
    this.speed = false,
    this.stability = false,
    this.similarity = false,
    this.style = false,
    this.stabilitySteps = const [],
    this.audioTags = false,
    this.known = true,
  });

  final bool speed;
  final bool stability;
  final bool similarity;
  final bool style;

  /// False for an engine nobody has described here. Same flag and same reason
  /// as [ModelCapabilities.known]: the fallback draws everything, and a test
  /// can tell "we checked, it takes all four" from "we never looked".
  final bool known;

  /// When set, the only stability values the engine takes.
  final List<double> stabilitySteps;

  /// Whether the engine reads delivery tags written into the text --
  /// `[excited]`, `[laughs]`, `[whispers]`. Eleven v3 does; everything else in
  /// the app would say the word out loud, which is the whole reason this is a
  /// declared capability rather than something the writer decides.
  final bool audioTags;

  bool honours(String key) => switch (key) {
    'voiceSpeed' => speed,
    'voiceStability' => stability,
    'voiceSimilarity' => similarity,
    'voiceStyle' => style,
    _ => false,
  };

  /// ElevenLabs' classic engines: the whole panel applies.
  static const elevenLabs = VoiceCapabilities(
    speed: true,
    stability: true,
    similarity: true,
    style: true,
  );

  /// Eleven v3: a different architecture. No speed at all, and stability is
  /// Creative / Natural / Robust rather than a slider.
  static const elevenV3 = VoiceCapabilities(
    stability: true,
    similarity: true,
    style: true,
    stabilitySteps: [0.0, 0.5, 1.0],
    audioTags: true,
  );

  /// MiniMax Speech: `voice_setting` carries a voice id and a speed.
  static const miniMax = VoiceCapabilities(speed: true);

  /// Nothing declared. Everything is drawn, because an engine nobody has
  /// described here is more likely to take the settings than to refuse them.
  static const unknown = VoiceCapabilities(
    speed: true,
    stability: true,
    similarity: true,
    style: true,
    known: false,
  );

  static VoiceCapabilities of(String providerId, String modelId) =>
      switch (providerId) {
        'elevenlabs' =>
          modelId.toLowerCase().contains('v3') ? elevenV3 : elevenLabs,
        'minimax-tts' => miniMax,
        _ => unknown,
      };
}

/// Delivery tags: the square-bracket direction Eleven v3 reads out of the text
/// itself -- `[excited]`, `[laughs]`, `[whispers]`.
///
/// They live in the script because that is the only channel a text-to-speech
/// call has, which makes them a hazard everywhere else. A tag left in the text
/// is read aloud by an engine that does not know it, printed in a subtitle,
/// counted in a word count and written into the project manifest. So the script
/// carries them -- the user can see and edit their own direction -- and
/// everything downstream takes the stripped text, except the one call that
/// knows what to do with them.
class DeliveryTags {
  DeliveryTags._();

  /// A tag, and only a tag: one bracketed run of letters, spaces and hyphens.
  /// Deliberately narrow, so `[1]` in a script or a bracketed aside survives.
  static final _tag = RegExp(r'\[[a-zA-Z][a-zA-Z \-]{0,30}\]');

  /// The words, with the direction taken out and the gap it left closed up.
  ///
  /// Nothing else is touched. It is tempting to tidy the space in front of a
  /// question mark too, and it would be wrong: French puts one there on
  /// purpose, and this runs over sentences the user wrote.
  static String strip(String text) => text
      .replaceAll(_tag, ' ')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .trim();

  static bool present(String text) => _tag.hasMatch(text);

  /// The text as this engine should receive it.
  static String forEngine(String text, VoiceCapabilities engine) =>
      engine.audioTags ? text : strip(text);

  /// The short vocabulary the writers are allowed to use.
  ///
  /// ElevenLabs publishes far more, including sound effects and accents. This
  /// is the subset that directs a person talking to a phone camera, and it is
  /// short on purpose: the model is documented as sometimes speaking a tag
  /// aloud, and a small familiar set is the part of that risk we can control.
  static const vocabulary = [
    '[excited]',
    '[laughs]',
    '[sighs]',
    '[whispers]',
    '[curious]',
    '[sarcastic]',
    '[mischievously]',
  ];
}
