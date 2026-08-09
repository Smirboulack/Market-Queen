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
  const CostEstimate(this.known, this.amount);

  static const unknown = CostEstimate(false, 0);

  final bool known;
  final double amount;
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
  Usage(this.step, this.provider, this.model, this.units, [this.unitsOut = 0]);

  final String step;
  final String provider;
  final String model;
  final double units;
  final double unitsOut;
}

class _Price {
  _Price({
    this.unit = '',
    this.amount = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.minUnits = 0,
    this.approx = false,
  });

  final String unit; // tokens | image | second | video | kchars | minute
  final double amount; // per unit; unused for tokens
  final double tokensIn; // dollars per 1M input tokens
  final double tokensOut; // dollars per 1M output tokens
  final double minUnits;
  final bool approx;

  bool get known => unit.isNotEmpty;
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

  // Hook, caption and each shot's line and two prompts come back in about this
  // much per shot, plus a little fixed overhead.
  static const _scriptOutputTokensPerShot = 220.0;

  // Every shot is kept at or under this so its clip is bought at the
  // five-second floor every video model offers.
  static const _secondsPerShot = 5.0;

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
      );
      if (price.known) _prices['$key'] = price;
    });

    _updated = '${decoded['updated'] ?? ''}';
    return true;
  }

  static double _toDouble(Object? value) =>
      value is num ? value.toDouble() : 0.0;

  _Price _priceFor(String modelId) => _prices[modelId] ?? _Price();

  /// Seconds of speech a script of [words] words takes. The pipeline sizes its
  /// clips from the same figure, so the estimate matches what it will buy.
  static double speechSeconds(int words) => math.max(3.0, words / _wordsPerSecond);

  /// Characters of speech in an ad of this length -- the TTS billing unit.
  static double speechCharacters(int durationSeconds) =>
      math.max(1.0, durationSeconds * _wordsPerSecond * _charsPerWord);

  /// How many shots an ad of this length is cut into.
  ///
  /// Video models sell clips in fixed sizes, five seconds being the smallest
  /// everyone offers. Keeping every shot at or under five seconds means each
  /// one is bought at that floor with nothing wasted, and no shot ever has to
  /// be stretched or looped to fill its slot.
  static int shotCount(int durationSeconds) =>
      (durationSeconds / _secondsPerShot).ceil().clamp(2, 10);

  /// Seconds of video bought for one shot of [shotSeconds] on screen.
  ///
  /// Mirrors what the video providers accept: they round anything over seven
  /// seconds up to a ten-second clip, everything else to five.
  static int clipSeconds(double shotSeconds) => shotSeconds > 7.0 ? 10 : 5;

  static int wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  /// Empty when the price is unknown.
  UnitPrice? unitPrice(String modelId) {
    final price = _priceFor(modelId);
    if (!price.known) return null;
    return UnitPrice(
      price.unit == 'tokens' ? price.tokensOut : price.amount,
      price.unit,
      price.approx,
    );
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
  PriceBreakdown estimate(Map<String, Object?> request) {
    String text(String key) => '${request[key] ?? ''}';

    final ownScript = text('script').trim();
    final duration = (request['durationSeconds'] as num?)?.toInt() ?? 20;
    final hasPhoto = text('productImagePath').isNotEmpty;

    // The studio hands over an explicit scene list; the old form does not, and
    // its shot count still has to be inferred from the length asked for.
    final scenes = (request['scenes'] as List?) ?? const [];
    var sceneCount = 0;
    for (final entry in scenes) {
      if (entry is Map && '${entry['line'] ?? ''}'.trim().isNotEmpty) sceneCount += 1;
    }

    // The voice-over drives both the TTS bill and the clip length, so work it
    // out first. A script the user wrote is measurable; otherwise we go by the
    // length they asked for.
    final voiceSeconds =
        ownScript.isEmpty ? duration.toDouble() : speechSeconds(wordCount(ownScript));
    final voiceChars = ownScript.isEmpty
        ? speechCharacters(duration)
        : ownScript.length.toDouble();

    // The ad is cut into shots, and each one buys its own frame and its own
    // clip. This is what multiplies the bill, so it has to be in the estimate.
    final shots = sceneCount > 0 ? sceneCount : shotCount(duration);
    final clip = clipSeconds(voiceSeconds / shots);

    final lines = <PriceLine>[];

    // ---- Script ---------------------------------------------------------
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

      lines.add(_line('script', text('textProvider'), text('textModel'), inputTokens,
          shots * _scriptOutputTokensPerShot));
    }

    // ---- Voice-over -----------------------------------------------------
    lines.add(_line(
      'voice',
      text('voiceProvider'),
      _registry.resolveModel(text('voiceProvider'), text('voiceModel')),
      voiceChars / 1000.0,
    ));

    // ---- Frames ---------------------------------------------------------
    // The user's own photo covers the first shot; the rest are generated.
    final ownFrame = request['useProductPhotoAsFrame'] == true && hasPhoto;
    final generatedFrames = ownFrame ? shots - 1 : shots;
    if (generatedFrames > 0) {
      lines.add(_line(
        'frames',
        text('imageProvider'),
        _registry.resolveModel(text('imageProvider'), text('imageModel')),
        generatedFrames.toDouble(),
      ));
    }

    // ---- Video ----------------------------------------------------------
    // A studio ad is a list of scenes, and a talking one is bought by the
    // second of speech rather than by the clip: the avatar model is handed the
    // line's audio and gives back exactly that much video. Product scenes have
    // no face to sync and stay on the by-the-clip image-to-video path.
    if (scenes.isNotEmpty) {
      var talking = 0;
      var broll = 0;
      var talkingSeconds = 0.0;

      for (final entry in scenes) {
        if (entry is! Map) continue;
        final sceneLine = '${entry['line'] ?? ''}'.trim();
        if (sceneLine.isEmpty) continue;
        if (entry['kind'] == 'broll') {
          broll += 1;
        } else {
          talking += 1;
          talkingSeconds += speechSeconds(wordCount(sceneLine));
        }
      }

      if (talking > 0) {
        lines.add(_line(
          'video',
          text('avatarProvider'),
          _registry.resolveModel(text('avatarProvider'), text('avatarModel')),
          talkingSeconds,
          talking.toDouble(),
        ));
      }
      if (broll > 0) {
        lines.add(_line(
          'video',
          text('videoProvider'),
          _registry.resolveModel(text('videoProvider'), text('videoModel'), clip),
          broll.toDouble() * clip,
          broll.toDouble(),
        ));
      }
    } else {
      lines.add(_line(
        'video',
        text('videoProvider'),
        _registry.resolveModel(text('videoProvider'), text('videoModel'), clip),
        shots.toDouble() * clip,
        shots.toDouble(),
      ));
    }

    // ---- Subtitles ------------------------------------------------------
    if (request['captionsEnabled'] != false) {
      lines.add(_line('captions', text('captionsProvider'), text('captionsModel'),
          voiceSeconds / 60.0));
    }

    return _total(lines);
  }

  /// Same shape, from what a finished run actually consumed.
  PriceBreakdown actual(List<Usage> consumed) => _total([
        for (final use in consumed)
          _line(use.step, use.provider, use.model, use.units, use.unitsOut),
      ]);
}
