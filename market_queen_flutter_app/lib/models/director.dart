import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/pricing.dart';
import '../core/settings_store.dart';
import '../core/signal.dart';
import '../i18n/translator.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import 'casting.dart';

/// Turns the user's lines into shots.
///
/// This is the only LLM call left in the studio, and it deliberately never
/// touches a spoken word: the user writes what is said, the model only says
/// what the camera sees. It works from the same realism rules as the casting
/// prompt, because a perfect actor dropped into a commercial storyboard still
/// produces a commercial.
class Director extends ChangeNotifier {
  Director(this._settings, this._registry, this._pricing, this._casting, this._log);

  // The direction pass is one short answer per scene plus the rules. Close
  // enough to price it honestly before the call, which is all the estimate
  // promises.
  static const _outputTokensPerScene = 160.0;
  static const _overheadTokens = 900.0;
  static const _tokensPerMillion = 1000000.0;

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final Casting _casting;
  final LogModel _log;

  /// One entry per scene, in order: { imagePrompt, videoPrompt }.
  final Event<List<Map<String, Object?>>> directed = Event();

  ProviderTask? _task;
  bool _running = false;
  String _error = '';

  bool get running => _running;
  String get error => _error;

  void _setError(String value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }

  void cancel() {
    final task = _task;
    if (task != null && !task.isFinished) task.cancel();
    _task = null;
    _running = false;
    notifyListeners();
  }

  /// What one direction pass costs.
  CostEstimate estimate(Map<String, Object?> request) {
    var providerId = '${request['textProvider'] ?? ''}';
    if (providerId.isEmpty) providerId = _registry.defaultProvider('text');

    final model =
        _registry.resolveModel(providerId, '${request['textModel'] ?? ''}');

    final unit = _pricing.unitPrice(model);
    if (unit == null || unit.unit != 'tokens') return CostEstimate.unknown;

    final scenes = (request['scenes'] as List?)?.length ?? 0;
    final tokens = _overheadTokens + scenes * _outputTokensPerScene;

    // unitPrice reports the output rate for token models, which is the larger
    // of the two -- so this rounds up rather than flattering the total.
    return CostEstimate(true, unit.amount * tokens / _tokensPerMillion);
  }

  /// [request] is AdProject's request map: product, actor and scenes.
  Future<void> direct(Map<String, Object?> request) async {
    if (_running) return;

    final scenes = (request['scenes'] as List?) ?? const [];

    // Only scenes that actually have a line, so a blank row does not shift the
    // answer out of step with the editor.
    final lines = <String>[];
    final kinds = <String>[];
    final beats = <String>[];
    for (final entry in scenes) {
      if (entry is! Map) continue;
      final line = '${entry['line'] ?? ''}'.trim();
      if (line.isEmpty) continue;
      lines.add(line);
      kinds.add('${entry['kind'] ?? 'talking'}');
      beats.add('${entry['beat'] ?? ''}');
    }

    if (lines.isEmpty) {
      _setError(tr('Write at least one line first.'));
      return;
    }

    var providerId = '${request['textProvider'] ?? ''}';
    if (providerId.isEmpty) providerId = _registry.defaultProvider('text');

    final model =
        _registry.resolveModel(providerId, '${request['textModel'] ?? ''}');

    // The product photo, so the model describes the real object rather than an
    // idea of it. The actor's portrait is not sent: it is the frame generator
    // that needs the face, not the writer.
    var referenceUri = '';
    final productImage = '${request['productImagePath'] ?? ''}';
    if (productImage.isNotEmpty && File(productImage).existsSync()) {
      referenceUri = Http.imageToDataUri(productImage);
    }

    final task = ProviderFactory.script(
      providerId,
      ScriptRequest(
        mode: ScriptMode.directVisuals,
        apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
        model: model,
        productName: '${request['productName'] ?? ''}',
        productDescription: '${request['productDescription'] ?? ''}',
        actorBrief: '${request['avatarBrief'] ?? ''}',
        actorDecor: '${request['extraInstructions'] ?? ''}',
        directionRules: _casting.directionRules,
        lines: lines,
        kinds: kinds,
        beats: beats,
        referenceImageDataUri: referenceUri,
      ),
    );

    if (task == null) {
      _setError(tr('No text provider called %1.').arg(providerId));
      return;
    }

    _error = '';
    _running = true;
    _task = task;
    notifyListeners();

    _log.info(tr('Directing %1 scene(s) with %2.').arg(lines.length).arg(model));

    try {
      final result = await task.run();
      _running = false;

      final raw = (result['shots'] as List?) ?? const [];
      final shots = [
        for (final entry in raw)
          if (entry is Map) entry.cast<String, Object?>(),
      ];

      if (shots.isEmpty) {
        _error = tr('The model returned no shots.');
        notifyListeners();
        return;
      }

      // Short answers are applied as far as they go rather than dropped: five
      // directed scenes out of six beats none, and the gap is visible in the
      // editor.
      if (shots.length < lines.length) {
        _log.warning(tr('Only %1 of %2 scenes came back directed.')
            .arg(shots.length)
            .arg(lines.length));
      }

      _log.success(tr('%1 scene(s) directed.').arg(shots.length));
      notifyListeners();
      directed.emit(shots);
    } on ProviderException catch (error) {
      _running = false;
      if (error is! TaskCancelled) {
        _log.error(tr('Direction failed: %1').arg(error.message));
        _error = error.message;
      }
      notifyListeners();
    } finally {
      _task = null;
    }
  }
}
