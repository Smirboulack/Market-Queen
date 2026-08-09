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

/// The three rewrite chips under the scenario bar.
///
/// The result is handed back rather than applied: the scenario lives in a text
/// field the user is in the middle of typing into, and the field is the only
/// thing that knows where the caret was.
class LineDoctor extends ChangeNotifier {
  LineDoctor(this._settings, this._registry, this._pricing, this._log);

  // A scenario in, a scenario out, plus the product context. Small enough that
  // a rewrite is worth pricing but not worth a spinner-with-a-total.
  static const _outputTokens = 320.0;
  static const _overheadTokens = 700.0;
  static const _tokensPerMillion = 1000000.0;

  final SettingsStore _settings;
  final Registry _registry;
  final Pricing _pricing;
  final LogModel _log;

  /// The rewritten line. Only ever emitted for the request that is still live.
  final Event<String> rewritten = Event();

  ProviderTask? _task;
  bool _running = false;
  String _error = '';

  /// Which button is spinning, so only that one shows it: "shorten", "punchier"
  /// or "enhance". Empty when nothing is running.
  String _action = '';

  bool get running => _running;
  String get action => _action;
  String get error => _error;

  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    notifyListeners();
  }

  void cancel() {
    final task = _task;
    if (task != null && !task.isFinished) task.cancel();
    _task = null;
    _running = false;
    _action = '';
    notifyListeners();
  }

  /// What one rewrite costs.
  CostEstimate estimate(Map<String, Object?> request) {
    var providerId = '${request['textProvider'] ?? ''}';
    if (providerId.isEmpty) providerId = _registry.defaultProvider('text');

    final model = _registry.resolveModel(
      providerId,
      '${request['textModel'] ?? ''}',
    );

    final unit = _pricing.unitPrice(model);
    if (unit == null || unit.unit != 'tokens') return CostEstimate.unknown;

    return CostEstimate(
      true,
      unit.amount * (_overheadTokens + _outputTokens) / _tokensPerMillion,
    );
  }

  /// [request] is the ad's request map, for the product context.
  ///
  /// [action] is the chip's own id; [instruction] is what the model is told.
  Future<void> rewrite({
    required Map<String, Object?> request,
    required String action,
    required String instruction,
    required String text,
  }) async {
    if (_running) return;

    final line = text.trim();
    if (line.isEmpty) {
      _setError(tr('Write something first.'));
      return;
    }

    var providerId = '${request['textProvider'] ?? ''}';
    if (providerId.isEmpty) providerId = _registry.defaultProvider('text');

    final model = _registry.resolveModel(
      providerId,
      '${request['textModel'] ?? ''}',
    );

    final task = ProviderFactory.script(
      providerId,
      ScriptRequest(
        mode: ScriptMode.rewriteScript,
        apiKey: _settings.apiKey(_registry.credentialFor(providerId)),
        model: model,
        productName: '${request['productName'] ?? ''}',
        productDescription: '${request['productDescription'] ?? ''}',
        audience: '${request['audience'] ?? ''}',
        avatarBrief: '${request['avatarBrief'] ?? ''}',
        extraInstructions: '${request['extraInstructions'] ?? ''}',
        lines: [line],
        rewriteInstruction: instruction,
      ),
    );

    if (task == null) {
      _setError(tr('No text provider called %1.').arg(providerId));
      return;
    }

    _error = '';
    _running = true;
    _action = action;
    _task = task;
    notifyListeners();

    try {
      final result = await task.run();
      _running = false;
      _action = '';

      final next = '${result['script'] ?? ''}'.trim();
      if (next.isEmpty) {
        _error = tr('The model returned an empty line.');
        notifyListeners();
        return;
      }

      notifyListeners();
      rewritten.emit(next);
    } on ProviderException catch (error) {
      _running = false;
      _action = '';
      if (error is! TaskCancelled) {
        _log.error(tr('Rewrite failed: %1').arg(error.message));
        _error = error.message;
      }
      notifyListeners();
    } finally {
      _task = null;
    }
  }

  void _setError(String value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }
}
