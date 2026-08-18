import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../providers/registry.dart';
import 'paths.dart';

/// One row of an estimate.
class PriceLine {
  PriceLine({
    required this.step,
    required this.model,
    required this.modelId,
    required this.known,
    required this.approx,
    required this.unit,
    required this.units,
    required this.amount,
  });

  final String step;
  final String model;
  final String modelId;
  final bool known;
  final bool approx;
  final String unit;
  final double units;
  final double amount;

  Map<String, Object?> toJson() => {
        'step': step,
        'model': model,
        'modelId': modelId,
        'known': known,
        'approx': approx,
        'unit': unit,
        'units': units,
        'amount': amount,
      };
}

class PriceBreakdown {
  const PriceBreakdown({
    required this.lines,
    required this.total,
    required this.unknownCount,
    required this.approx,
  });

  static const empty =
      PriceBreakdown(lines: [], total: 0, unknownCount: 0, approx: false);

  final List<PriceLine> lines;

  /// Covers the known lines only; [unknownCount] says how many were left out,
  /// so the UI can say so instead of quietly under-reporting.
  final double total;
  final int unknownCount;
  final bool approx;

  Map<String, Object?> toJson() => {
        'lines': [for (final line in lines) line.toJson()],
        'total': total,
        'unknownCount': unknownCount,
        'approx': approx,
      };
}

/// What a single operation would cost: an amount, or nothing when the model
/// has no published price. Used by the panels that price one action rather than
/// a whole run -- a casting batch, an audition, a re-shoot.
class CostEstimate {
  const CostEstimate(this.known, this.amount, {this.exact = false});

  static const unknown = CostEstimate(false, 0);

  /// Nothing was asked for, so nothing is owed. Distinct from [unknown]: an
  /// empty prompt has a price, and it is zero.
  static const free = CostEstimate(true, 0, exact: true);

  final bool known;
  final double amount;

  /// True when the figure came from what the provider reported it had done --
  /// the tokens it billed, the frame it actually returned -- rather than from
  /// what the app expected to ask for. It is the difference between "$0.09"
  /// and "~$0.09", and on a bring-your-own-key app that difference is the
  /// whole point of showing a number at all.
  final bool exact;
}

/// What one unit of a model costs: enough to draw "$0.28/s" next to its name.
class UnitPrice {
  const UnitPrice(this.amount, this.unit, this.approx);

  final double amount;
  final String unit;
  final bool approx;
}

/// One billable call a run actually made.
class Usage {
  Usage(this.step, this.provider, this.model, this.units,
      [this.unitsOut = 0, this.quality = '', this.size = '']);

  final String step;
  final String provider;
  final String model;
  final double units;
  final double unitsOut;

  /// The frame an image call was actually made at. Without it the receipt
  /// quotes the model's headline figure -- its cheapest frame -- for a
  /// picture that may have cost eight times that.
  final String quality;
  final String size;
}

/// One step of a model whose price changes with the size of what it produces.
/// The last step in a list carries no ceiling: it is what everything above the
/// previous one costs.
class _Tier {
  const _Tier(this.maxMegapixels, this.amount);

  final double maxMegapixels;
  final double amount;

  bool get unbounded => maxMegapixels <= 0;
}

class _Price {
  _Price({
    this.unit = '',
    this.amount = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.minUnits = 0,
    this.approx = false,
    this.tiers = const [],
    this.byResolution = const {},
    this.audioMultiplier = 0,
    this.perMillionTokens = 0,
    this.extraInputImage = 0,
    this.byFrame = const {},
    this.frameFallback = const {},
    this.qualityAlias = const {},
    this.bySize = const {},
  });

  final String unit; // tokens | image | second | video | kchars | minute
  final double amount; // per unit; unused for tokens
  final double tokensIn; // dollars per 1M input tokens
  final double tokensOut; // dollars per 1M output tokens
  final double minUnits;
  final bool approx;

  /// Image models whose price steps with the frame size, cheapest first.
  final List<_Tier> tiers;

  /// Video models whose per-second price depends on the resolution asked for.
  final Map<String, double> byResolution;

  /// What a generated soundtrack multiplies the clip by, where the model
  /// charges for one. Zero means it makes no difference.
  final double audioMultiplier;

  /// The provider's own published rate, for the models that bill by token and
  /// report the count back. This is what turns an estimate into a receipt.
  final double perMillionTokens;

  /// Charged per reference image past the first.
  final double extraInputImage;

  /// Image models that publish a price per (quality, frame) pair, keyed
  /// "high/1024x1536". Exact where it has an entry.
  final Map<String, double> byFrame;

  /// Image models that publish a price per frame and have no quality step at
  /// all, keyed by the size token alone: "1K", "512px". Gemini's four are
  /// this shape -- the resolution is the only thing that moves the bill.
  final Map<String, double> bySize;

  /// The price at the model's base frame, per quality, for the frames
  /// [byFrame] does not list. Scaled by area -- see [amountForFrame].
  final Map<String, double> frameFallback;

  /// A quality step that stands in for another when pricing.
  ///
  /// One entry today: OpenAI's "auto" lets the model choose the effort, and
  /// medium is both what it usually lands on and the middle of the three. It
  /// matters that this is a *lookup* alias rather than a number of its own,
  /// because it lets auto reach the published pair for a frame -- auto at
  /// 1536x1024 is quoted at medium's 0.041 rather than scaled up from the
  /// square to 0.079, which was wrong by double.
  final Map<String, String> qualityAlias;

  /// The frame [frameFallback] is quoted at. Every OpenAI quality step lists
  /// its 1024x1024 price, and the larger frames are token-billed in proportion
  /// to their area, so that square is the unit the scaling starts from.
  static const double _fallbackPixels = 1024 * 1024;

  /// What one image costs at this quality and this frame.
  ///
  /// Three answers in order of how much they are worth trusting: the published
  /// pair; the published price at the base frame scaled by how much bigger
  /// this frame is; or the model's flat [amount]. Only the first is exact --
  /// [exactFrame] says which happened, so the interface can put a tilde on the
  /// other two rather than presenting a projection as a quote.
  double amountForFrame(String quality, String size) {
    // A model with no quality step answers from the size alone.
    final flat = bySize[size];
    if (flat != null) return flat;

    final step = quality.isEmpty ? 'auto' : quality;
    final priced = qualityAlias[step] ?? step;

    final published = byFrame['$step/$size'] ?? byFrame['$priced/$size'];
    if (published != null) return published;

    final base = frameFallback[step] ?? frameFallback[priced];
    if (base == null) return amount;

    final pixels = _pixelsOf(size);
    if (pixels <= 0) return base;
    return base * pixels / _fallbackPixels;
  }

  bool exactFrame(String quality, String size) =>
      bySize.containsKey(size) ||
      byFrame.containsKey('${quality.isEmpty ? 'auto' : quality}/$size');

  /// "2048x1152" -> 2359296. Zero for "auto" and anything unparseable, which
  /// is the signal to stop scaling and quote the base frame.
  static double _pixelsOf(String size) {
    final parts = size.toLowerCase().split('x');
    if (parts.length != 2) return 0;
    final width = double.tryParse(parts[0]) ?? 0;
    final height = double.tryParse(parts[1]) ?? 0;
    return width <= 0 || height <= 0 ? 0 : width * height;
  }

  bool get known => unit.isNotEmpty;

  /// The per-unit price for a frame of [megapixels], falling back to [amount]
  /// when the model has no tiers or the size is not known yet.
  double amountForSize(double megapixels) {
    if (tiers.isEmpty || megapixels <= 0) return amount;
    for (final tier in tiers) {
      if (tier.unbounded || megapixels <= tier.maxMegapixels) return tier.amount;
    }
    return tiers.last.amount;
  }

  /// The per-second price at [resolution], with the soundtrack counted in.
  /// Falls back to [amount] for a resolution the model does not list -- which
  /// is the right answer for the models that charge one rate for all of them.
  double amountForShot(String resolution, {bool audio = false}) {
    final base = byResolution[resolution.toLowerCase()] ?? amount;
    return audio && audioMultiplier > 0 ? base * audioMultiplier : base;
  }
}

/// What each model costs, and what a run is about to cost.
///
/// The numbers live in resources/pricing.json rather than in this file:
/// provider prices move often, and a data file can be corrected by a pull
/// request instead of a release. A pricing.json dropped in the config directory
/// overrides the bundled one, so nobody has to wait for us to notice a change.
///
/// A model the catalogue does not know is never guessed at: it is reported as
/// unknown and left out of the total. Everything here is an estimate and is
/// labelled as one -- it is not a billing source.
class Pricing {
  Pricing(this._registry);

  // A speaker in an ad delivers roughly this many words a second; the pipeline
  // uses the same number when ffmpeg is unavailable, so the two agree.
  static const _wordsPerSecond = 2.6;

  // Average characters per word, including the trailing space.
  static const _charsPerWord = 6.0;

  // Roughly four characters to a token, the usual English figure.
  static const _charsPerToken = 4.0;

  // System prompt plus the JSON scaffolding the writer is asked to fill in.
  static const _scriptOverheadTokens = 800.0;

  // A product photo handed to a vision model.
  static const _imageTokens = 1100.0;

  // Hook, caption and the read itself come back in about this much, plus a
  // little fixed overhead.
  static const _scriptOutputTokensPerShot = 220.0;

  final Registry _registry;
  final Map<String, _Price> _prices = {};

  String _updated = '';
  bool _overridden = false;

  /// Date the prices were last checked, "yyyy-MM-dd".
  String get updated => _updated;

  /// True when a user file replaced the bundled catalogue.
  bool get overridden => _overridden;

  /// Where such a file would go, whether or not it exists.
  String get overridePath => p.join(Paths.configDir, 'pricing.json');

  Future<void> load() async {
    // The user's file wins outright rather than merging: a half-overridden
    // catalogue would be impossible to reason about when a number looks wrong.
    _overridden = _loadFromFile(overridePath);
    if (!_overridden) {
      _loadFromJson(await rootBundle.loadString('assets/resources/pricing.json'));
    }
  }

  bool _loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return false;
    try {
      return _loadFromJson(file.readAsStringSync());
    } on FileSystemException {
      return false;
    }
  }

  bool _loadFromJson(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;

    final models = decoded['models'];
    if (models is! Map || models.isEmpty) return false;

    _prices.clear();
    models.forEach((key, value) {
      if (value is! Map) return;
      // Recorded on purpose, but still has no price.
      if (value['unknown'] == true) return;

      final price = _Price(
        unit: '${value['unit'] ?? ''}',
        amount: _toDouble(value['amount']),
        tokensIn: _toDouble(value['in']),
        tokensOut: _toDouble(value['out']),
        minUnits: _toDouble(value['minUnits']),
        approx: value['approx'] == true,
        tiers: _tiersFrom(value['tiers']),
        byResolution: _ratesFrom(value['byResolution']),
        audioMultiplier: _toDouble(value['audioMultiplier']),
        perMillionTokens: _toDouble(value['perMillionTokens']),
        extraInputImage: _toDouble(value['extraInputImage']),
        byFrame: _ratesFrom(value['byFrame']),
        frameFallback: _ratesFrom(value['frameFallback']),
        qualityAlias: _aliasFrom(value['qualityAlias']),
        // Not lowercased: "512px" and "1K" are tokens the API defines, and
        // the menu holds them in exactly that spelling.
        bySize: _sizesFrom(value['bySize']),
      );
      if (price.known) _prices['$key'] = price;
    });

    _updated = '${decoded['updated'] ?? ''}';
    return true;
  }

  static double _toDouble(Object? value) =>
      value is num ? value.toDouble() : 0.0;

  static List<_Tier> _tiersFrom(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is Map)
          _Tier(_toDouble(entry['maxMegapixels']), _toDouble(entry['amount'])),
    ];
  }

  /// Resolution keys are folded to lower case on the way in, so "4K" in the
  /// file and "4k" off a model's schema are the same rate.
  static Map<String, double> _ratesFrom(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        '${entry.key}'.toLowerCase(): _toDouble(entry.value),
    };
  }

  static Map<String, double> _sizesFrom(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries) '${entry.key}': _toDouble(entry.value),
    };
  }

  static Map<String, String> _aliasFrom(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        '${entry.key}'.toLowerCase(): '${entry.value}'.toLowerCase(),
    };
  }

  _Price _priceFor(String modelId) => _prices[modelId] ?? _Price();

  /// Seconds of speech a script of [words] words takes. The pipeline sizes its
  /// clips from the same figure, so the estimate matches what it will buy.
  static double speechSeconds(int words) => math.max(3.0, words / _wordsPerSecond);

  /// Characters of speech in an ad of this length -- the TTS billing unit.
  static double speechCharacters(int durationSeconds) =>
      math.max(1.0, durationSeconds * _wordsPerSecond * _charsPerWord);

  static int wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  /// Empty when the price is unknown.
  ///
  /// [resolution], [audio] and [megapixels] narrow it to what is actually
  /// about to be asked for, where the model prices those differently -- a
  /// Seedance second at 1080p is four times one at 480p. All three are
  /// optional, and left out the answer is the model's headline rate, which is
  /// what the model menu wants.
  UnitPrice? unitPrice(
    String modelId, {
    String resolution = '',
    bool audio = false,
    double megapixels = 0,
    String size = '',
    String quality = '',
  }) {
    final price = _priceFor(modelId);
    if (!price.known) return null;

    // A model that prices by frame answers from its own table; the rest size
    // themselves in megapixels and answer from their tiers.
    final byFrame = price.byFrame.isNotEmpty ||
        price.frameFallback.isNotEmpty ||
        price.bySize.isNotEmpty;

    final amount = switch (price.unit) {
      'tokens' => price.tokensOut,
      'image' => byFrame
          ? price.amountForFrame(quality, size)
          : price.amountForSize(megapixels),
      'second' => price.amountForShot(resolution, audio: audio),
      _ => price.amount,
    };

    // A published pair is a quote and loses the tilde, even on a model whose
    // headline figure is flagged approximate -- which gpt-image-2's is,
    // precisely because it stands for nine different numbers.
    final approx =
        byFrame ? !price.exactFrame(quality, size) : price.approx;

    return UnitPrice(amount, price.unit, approx);
  }

  /// What one finished generation actually cost.
  ///
  /// The estimate before a request and the figure after it are different
  /// questions, and this is the second one: the frame that came back rather
  /// than the one asked for, and -- where the provider says so -- the tokens
  /// it billed rather than the tokens the formula predicted. A result priced
  /// from [tokens] is marked exact and shown without a tilde, because it is
  /// not an approximation of anything.
  ///
  /// Unknown when the catalogue has no line for the model. Never guessed: a
  /// figure under a picture is a claim about somebody's bill.
  CostEstimate charged({
    required String modelId,
    double tokens = 0,
    double megapixels = 0,
    double seconds = 0,
    String resolution = '',
    bool audio = false,
    int extraInputImages = 0,
    String size = '',
    String quality = '',
  }) {
    final price = _priceFor(modelId);
    if (!price.known) return CostEstimate.unknown;

    final extras = extraInputImages > 0
        ? extraInputImages * price.extraInputImage
        : 0.0;

    // What the provider itself reported it had consumed. Nothing to estimate
    // and nothing to round: this is the line that will appear on the bill.
    if (tokens > 0 && price.perMillionTokens > 0) {
      return CostEstimate(
        true,
        tokens / 1e6 * price.perMillionTokens + extras,
        exact: true,
      );
    }

    switch (price.unit) {
      case 'image':
        // A model priced by frame is billed on the frame that came back, which
        // is what makes "auto" answerable after the fact: the request did not
        // say what it wanted and the file says what it got.
        if (price.byFrame.isNotEmpty ||
            price.frameFallback.isNotEmpty ||
            price.bySize.isNotEmpty) {
          final frame = size.isNotEmpty && size != 'auto'
              ? size
              : _frameOf(megapixels);
          return CostEstimate(
            true,
            price.amountForFrame(quality, frame) + extras,
            exact: price.exactFrame(quality, frame),
          );
        }

        // The size the provider sent back, so a 4K frame is billed at the 4K
        // step even if the menu said something else.
        return CostEstimate(
          true,
          price.amountForSize(megapixels) + extras,
          exact: megapixels > 0 && !price.approx,
        );
      case 'second':
        if (seconds <= 0) return CostEstimate.unknown;
        final billed = math.max(seconds, price.minUnits);
        return CostEstimate(
          true,
          billed * price.amountForShot(resolution, audio: audio) + extras,
          exact: false,
        );
      case 'video':
        return CostEstimate(true, price.amount + extras, exact: !price.approx);
      default:
        return CostEstimate.unknown;
    }
  }

  /// One row of the estimate. What the two quantities mean depends on how the
  /// model bills: for tokens, input and output counts; for a flat per-clip
  /// video price, seconds and the number of clips; everything else uses
  /// [units] alone.
  PriceLine _line(
    String step,
    String providerId,
    String modelId,
    double units, [
    double unitsOut = 0,
    // The frame actually being bought. An image model's price is a table of
    // nine numbers, not one: quoting the headline figure for a 4K frame is how
    // six stills came back eight times dearer than the estimate said.
    String quality = '',
    String size = '',
  ]) {
    final price = _priceFor(modelId);
    final label = _registry.modelLabel(providerId, modelId);

    if (!price.known) {
      return PriceLine(
        step: step,
        model: label,
        modelId: modelId,
        known: false,
        approx: false,
        unit: price.unit,
        units: 0,
        amount: 0,
      );
    }

    double amount;
    double shown = units;

    if (price.unit == 'tokens') {
      amount = units / 1e6 * price.tokensIn + unitsOut / 1e6 * price.tokensOut;
      shown = units + unitsOut;
    } else if (price.unit == 'video') {
      // Some models charge a flat fee per generation rather than by the
      // second, so the seconds asked for do not enter into it -- only how many
      // clips the cut needs, which the caller passes as the second quantity.
      shown = math.max(1.0, unitsOut);
      amount = shown * price.amount;
    } else if (price.unit == 'image' &&
        (price.byFrame.isNotEmpty ||
            price.frameFallback.isNotEmpty ||
            price.bySize.isNotEmpty)) {
      shown = math.max(units, price.minUnits);
      amount = shown * price.amountForFrame(quality, size);
      return PriceLine(
        step: step,
        model: label,
        modelId: modelId,
        known: true,
        approx: !price.exactFrame(quality, size),
        unit: price.unit,
        units: shown,
        amount: amount,
      );
    } else {
      // Providers with a floor bill it even for a shorter request.
      shown = math.max(units, price.minUnits);
      amount = shown * price.amount;
    }

    return PriceLine(
      step: step,
      model: label,
      modelId: modelId,
      known: true,
      approx: price.approx,
      unit: price.unit,
      units: shown,
      amount: amount,
    );
  }

  static PriceBreakdown _total(List<PriceLine> lines) {
    var total = 0.0;
    var unknown = 0;
    var approx = false;

    for (final line in lines) {
      if (!line.known) {
        unknown += 1;
        continue;
      }
      total += line.amount;
      approx = approx || line.approx;
    }

    return PriceBreakdown(
      lines: lines,
      total: total,
      unknownCount: unknown,
      approx: approx,
    );
  }

  /// What the studio is about to spend, taking the same map AdProject builds
  /// for the pipeline.
  ///
  /// It reads as four lines because the ad is four calls: write it, read it,
  /// draw the actor, film them. There is no shot count in here any more --
  /// the ad is one take, so every quantity is the whole ad rather than a share
  /// of it, and the estimate cannot drift from the run by miscounting shots.
  PriceBreakdown estimate(Map<String, Object?> request) {
    String text(String key) => '${request[key] ?? ''}';

    final ownScript = text('script').trim();
    final duration = (request['durationSeconds'] as num?)?.toInt() ?? 20;
    final hasPhoto = text('productImagePath').isNotEmpty;

    // The read drives both the TTS bill and the length of the clip, because
    // the avatar model gives back exactly as much video as it was handed
    // audio. A script the user wrote is measurable; otherwise we go by the
    // length they asked for.
    final voiceSeconds =
        ownScript.isEmpty ? duration.toDouble() : speechSeconds(wordCount(ownScript));
    final voiceChars = ownScript.isEmpty
        ? speechCharacters(duration)
        : ownScript.length.toDouble();

    final lines = <PriceLine>[];

    // ---- Script ---------------------------------------------------------
    // Only bought when there is nothing written. A scenario the user typed is
    // filmed as typed, so no model reads it first.
    if (ownScript.isEmpty) {
      final brief = text('productName') +
          text('productDescription') +
          text('audience') +
          text('tone') +
          text('language') +
          text('avatarBrief') +
          text('extraInstructions');

      var inputTokens = _scriptOverheadTokens + brief.length / _charsPerToken;
      if (hasPhoto) inputTokens += _imageTokens;

      lines.add(_line('script', text('textProvider'),
          _registry.resolveModel(text('textProvider'), text('textModel')),
          inputTokens, _scriptOutputTokensPerShot));
    }

    // ---- Voice-over -----------------------------------------------------
    lines.add(_line(
      'voice',
      text('voiceProvider'),
      _registry.resolveModel(text('voiceProvider'), text('voiceModel')),
      voiceChars / 1000.0,
    ));

    // ---- The frame ------------------------------------------------------
    // One picture, and only when the user has not supplied it themselves.
    if (!(request['useProductPhotoAsFrame'] == true && hasPhoto)) {
      lines.add(_line(
        'frames',
        text('imageProvider'),
        _registry.resolveModel(text('imageProvider'), text('imageModel')),
        1,
        0,
        text('imageQuality'),
        text('imageSize'),
      ));
    }

    // ---- The take -------------------------------------------------------
    // Bought by the second of speech rather than by the clip: the avatar model
    // is handed the read and gives back exactly that much video.
    lines.add(_line(
      'video',
      text('avatarProvider'),
      _registry.resolveModel(text('avatarProvider'), text('avatarModel')),
      voiceSeconds,
      1,
    ));

    return _total(lines);
  }

  /// The published frame closest to what came back, so a result generated on
  /// "auto" can still be priced from the file rather than from the request.
  ///
  /// Nearest by area rather than by shape: the price follows the pixel count,
  /// and a 1536x1024 and a 1024x1536 cost the same on every line of the table.
  static String _frameOf(double megapixels) {
    if (megapixels <= 0) return '';

    const frames = {
      '1024x1024': 1.048576,
      '1536x1024': 1.572864,
      '2048x2048': 4.194304,
      '2048x1152': 2.359296,
      '3840x2160': 8.2944,
    };

    var best = '';
    var closest = double.infinity;
    frames.forEach((frame, area) {
      final gap = (area - megapixels).abs();
      if (gap < closest) {
        closest = gap;
        best = frame;
      }
    });
    return best;
  }

  /// What a one-shot call to a writer would cost.
  ///
  /// The rewrite button prices itself with this: it is the only place in the
  /// app where the user picks a text model for a single, immediate action, so
  /// the figure has to be per-press rather than per-million-tokens. Approximate
  /// by nature -- how long an answer comes back is the model's decision -- and
  /// shown as such.
  CostEstimate tokenCost(
    String modelId, {
    required double inTokens,
    required double outTokens,
  }) {
    final price = _priceFor(modelId);
    if (!price.known || price.unit != 'tokens') return CostEstimate.unknown;

    return CostEstimate(
      true,
      inTokens / 1e6 * price.tokensIn + outTokens / 1e6 * price.tokensOut,
    );
  }

  /// Roughly four characters to a token, the usual English figure. Public so
  /// the callers that size a one-off call use the same conversion the
  /// estimate does.
  static double tokensIn(String text) => text.length / _charsPerToken;

  /// Same shape, from what a finished run actually consumed.
  PriceBreakdown actual(List<Usage> consumed) => _total([
        for (final use in consumed)
          _line(use.step, use.provider, use.model, use.units, use.unitsOut,
              use.quality, use.size),
      ]);
}
