import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/paths.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../media/ffmpeg.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import 'asset_library.dart';

/// Turns a written description into a handful of stills.
///
/// One object, used by both editors: an actor and a scene are the same request
/// with a different prompt. The stills land in a scratch folder and only the
/// one the user keeps is ever copied anywhere permanent -- saving the asset is
/// what adopts it.
class ImageForge extends ChangeNotifier {
  ImageForge(
    this._settings,
    this._registry,
    this._pricing,
    this._log, {
    required this.scratchFolder,
  });

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;

  /// Sub-directory of the config folder this forge writes into, so an actor
  /// batch and a scene batch never overwrite one another.
  final String scratchFolder;

  final List<String> _images = [];
  final List<ProviderTask> _tasks = [];

  int _requested = 0;
  int _received = 0;
  int _failed = 0;
  String _error = '';

  /// Newest batch, oldest first.
  List<String> get images => List.unmodifiable(_images);
  int get received => _received;
  int get requested => _requested;
  String get error => _error;

  bool get running => _requested > 0 && _received + _failed < _requested;

  String get _scratchDir =>
      Paths.ensureDir(p.join(Paths.configDir, scratchFolder));

  /// What one batch of [count] would cost.
  CostEstimate estimate(int count) {
    final unit = _pricing.unitPrice(_model());
    if (unit == null) return CostEstimate.unknown;
    return CostEstimate(true, unit.amount * count);
  }

  String _provider() {
    final saved = _settings.prefString('imageProvider');
    return saved.isEmpty ? _registry.defaultProvider('image') : saved;
  }

  String _model() =>
      _registry.resolveModel(_provider(), _settings.prefString('imageModel'));

  void reset() {
    cancel();
    _images.clear();
    _requested = _received = _failed = 0;
    _error = '';
    notifyListeners();
  }

  void cancel() {
    for (final task in _tasks) {
      if (!task.isFinished) task.cancel();
    }
    _tasks.clear();

    if (_requested > 0) {
      _requested = _received + _failed;
      notifyListeners();
    }
  }

  void _setError(String value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }

  void _finishOne() {
    if (_received + _failed >= _requested &&
        _received == 0 &&
        _failed > 0 &&
        _error.isEmpty) {
      // Every request failed: the reason is already in the log, but the panel
      // needs to say so where the user is looking.
      _error = tr('Nothing came back. Check the log.');
    }
    notifyListeners();
  }

  /// Fires [count] requests at once.
  ///
  /// [references] is the asset's own media list; the first picture in it is
  /// handed to the model, which is what keeps the same face or the same room
  /// across a batch. Clips are skipped: no image model takes one.
  Future<void> generate({
    required String prompt,
    String aspectRatio = '9:16',
    List<String> references = const [],
    int count = 2,
  }) async {
    if (running) return;
    if (prompt.trim().isEmpty) {
      _setError(tr('Describe it first, or drop a picture in.'));
      return;
    }

    final dir = _scratchDir;
    if (dir.isEmpty) {
      _setError(tr('Could not create the scratch folder.'));
      return;
    }

    // A new batch replaces the previous one: keeping them would make the strip
    // a pile rather than a choice.
    _images.clear();
    _tasks.clear();
    _received = _failed = 0;
    _requested = count < 1 ? 1 : count;
    _error = '';
    notifyListeners();

    final providerId = _provider();
    final model = _model();

    var referenceUri = '';
    for (final path in references) {
      if (isVideoPath(path)) continue;
      // Through ffmpeg when the Dart codecs cannot read it: a reference dropped
      // straight off a shop page is as likely to be AVIF as anything.
      referenceUri = await imageDataUri(Ffmpeg.resolve(_settings.ffmpegPath), path);
      if (referenceUri.isEmpty) _log.warning(unreadableImage(path));
      break;
    }

    _log.info(tr('Generating %1 picture(s) with %2.').arg(_requested).arg(model));

    final stamp = _timestamp(DateTime.now());
    final apiKey = _settings.apiKey(_registry.credentialFor(providerId));

    for (var i = 0; i < _requested; ++i) {
      final task = ProviderFactory.image(
        providerId,
        ImageRequest(
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          aspectRatio: aspectRatio,
          referenceImageDataUri: referenceUri,
        ),
      );

      if (task == null) {
        _failed += 1;
        _setError(tr('No image provider called %1.').arg(providerId));
        _finishOne();
        continue;
      }

      _tasks.add(task);
      unawaited(_collect(task, dir, stamp, i));
    }
  }

  Future<void> _collect(
    ProviderTask task,
    String dir,
    String stamp,
    int index,
  ) async {
    try {
      final result = await task.run();

      final data = result['data'] as Uint8List? ?? Uint8List(0);
      final extension = '${result['extension'] ?? 'png'}';
      final path = p.join(dir, '$stamp-${index + 1}.$extension');

      try {
        File(path).writeAsBytesSync(data);
      } on FileSystemException {
        _failed += 1;
        _setError(tr('Could not write %1.').arg(path));
        _finishOne();
        return;
      }

      _received += 1;
      _images.add(path);
      _finishOne();
    } on ProviderException catch (error) {
      _failed += 1;
      if (error is! TaskCancelled) {
        _log.error(tr('Picture failed: %1').arg(error.message));
        _error = error.message;
      }
      _finishOne();
    }
  }

  static String _timestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
