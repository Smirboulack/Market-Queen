import 'package:flutter/foundation.dart';

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../providers/provider_task.dart';
import '../providers/registry.dart';
import '../providers/types.dart';

/// What the prompt being rewritten is for.
///
/// A picture model wants a photograph described; a video model wants the same
/// thing plus what moves; an actor wants words somebody can say out loud. One
/// instruction for all three would produce prose that suits none of them.
enum PromptKind { image, video, script, voice, actor, scene }

/// Who will do the rewriting, and whether it costs anything.
@immutable
class PromptWriter {
  const PromptWriter({
    this.providerId = '',
    this.modelId = '',
    this.label = '',
    this.account = '',
    this.free = false,
  });

  final String providerId;
  final String modelId;

  /// The model's own name, for the tooltip.
  final String label;

  /// The account it will be billed to, when it is billed at all.
  final String account;

  /// True when the provider publishes a free quota for this model and hands out
  /// the key without a card. The user still brings their own key; nobody is
  /// charged until that quota runs out, which is what the tooltip says.
  final bool free;

  bool get exists => providerId.isNotEmpty && modelId.isNotEmpty;
}

/// Rewrites the prompt in the bar into one a model can do more with.
///
/// It runs on a writer the user already has a key for, and it prefers a free
/// one: every provider in the catalogue that publishes a free tier is tried
/// before the one they picked for writing scripts, because pressing a button
/// marked "improve this" should not quietly cost money. When only a paid writer
/// is available it still works -- and says so on the button, before it is
/// pressed.
class PromptDoctor extends ChangeNotifier {
  PromptDoctor(this._settings, this._registry, this._log);

  final SettingsStore _settings;
  final Registry _registry;
  final LogModel _log;

  ProviderTask? _running;
  String _error = '';

  bool get busy => _running != null;
  String get error => _error;

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  void cancel() {
    final task = _running;
    _running = null;
    if (task != null && !task.isFinished) task.cancel();
  }

  /// Which writer would run, on the keys that are actually present.
  ///
  /// Free first, and within that the writer the user has already chosen, so
  /// somebody who picked Gemini keeps Gemini. Nothing at all when no writer has
  /// a key -- the button then says what to do about it rather than failing on
  /// the press.
  PromptWriter get writer {
    final chosen = _registry.providerOrDefault(
      'text',
      _settings.prefString('textProvider'),
    );

    // The chosen provider gets first refusal on both passes.
    final providers = <ProviderEntry>[
      for (final entry in _registry.providers('text'))
        if (entry.id == chosen) entry,
      for (final entry in _registry.providers('text'))
        if (entry.id != chosen) entry,
    ];

    for (final wantFree in [true, false]) {
      for (final provider in providers) {
        if (!_settings.hasApiKey(provider.credential)) continue;

        for (final model in provider.models) {
          if (model.isFree != wantFree) continue;
          if (_settings.modelHidden(provider.id, model.id)) continue;

          return PromptWriter(
            providerId: provider.id,
            modelId: model.id,
            label: model.label,
            account: provider.label,
            free: model.isFree,
          );
        }
      }
    }

    return const PromptWriter();
  }

  /// Hands [prompt] to that writer and gives back what came out.
  ///
  /// Returns an empty string when there was nothing to do, nobody to do it, or
  /// it failed -- [error] then says why, in the user's own words. The prompt is
  /// never replaced by an error message.
  Future<String> improve({
    required String prompt,
    required PromptKind kind,
    String context = '',
  }) async {
    if (busy) return '';

    final asked = prompt.trim();
    if (asked.isEmpty) {
      _setError(tr('Write something first, then let a model widen it.'));
      return '';
    }

    final chosen = writer;
    if (!chosen.exists) {
      _setError(tr('No writer has a key yet. Add one under Models.'));
      return '';
    }

    final task = ProviderFactory.text(
      chosen.providerId,
      TextRequest(
        apiKey: _settings.apiKey(_registry.credentialFor(chosen.providerId)),
        model: chosen.modelId,
        system: systemPromptFor(kind),
        user: [
          if (context.trim().isNotEmpty) '${context.trim()}\n',
          asked,
        ].join(),
      ),
    );
    if (task == null) {
      _setError(tr('No writer called %1.').arg(chosen.providerId));
      return '';
    }

    _running = task;
    _error = '';
    notifyListeners();

    try {
      final result = await task.run();
      final improved = '${result['text'] ?? ''}'.trim();
      _running = null;
      notifyListeners();
      return improved;
    } on ProviderException catch (error) {
      _running = null;
      if (error is! TaskCancelled) {
        _log.error(tr('Could not improve the prompt: %1').arg(error.message));
        _error = error.message;
      }
      notifyListeners();
      return '';
    }
  }

  void _setError(String message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }

  /// Visible for testing: the instruction is the whole feature, and a change to
  /// it is a change to what comes back.
  ///
  /// Three rules are in every one of them, and each is there because the
  /// obvious failure without it is worse than no rewriting at all: answer with
  /// the prompt and nothing else, keep the handles verbatim -- `@Image1` is the
  /// name of a file the model will be handed, not a word -- and stay in the
  /// user's language, because half these prompts are French and a model asked
  /// to "improve" one will otherwise hand back English.
  @visibleForTesting
  static String systemPromptFor(PromptKind kind) {
    const common =
        'Answer with the rewritten prompt and nothing else: no preface, no '
        'explanation, no quotation marks, no markdown.\n'
        'Write it in the same language as the prompt you were given.\n'
        'Keep every @handle exactly as it is (@Image1, @Video1, @Audio1, and '
        'the names of people): they are the names of the files and the cast the '
        'model will be handed.\n'
        'Keep what was asked for. Add the detail that was left out; invent no '
        'new subject, no new product and no new claim.\n';

    return switch (kind) {
      PromptKind.image =>
        'You turn a short description into a prompt for an image model that '
            'has to produce a photograph, not an illustration.\n'
            'Say what is in frame, how it is framed and from what distance, the '
            'lens, the light and where it comes from, the surfaces and '
            'materials, and the mood. Real photography, real skin, no gloss.\n'
            'Two or three sentences at most.\n'
            '\n$common',
      PromptKind.video =>
        'You turn a short description into a prompt for a video model.\n'
            'Say what is in frame, what moves and how, what the camera does '
            'over the few seconds of the shot, the light and the mood. One '
            'continuous shot, handheld and real rather than cinematic and '
            'staged.\n'
            'Two or three sentences at most.\n'
            '\n$common',
      PromptKind.script || PromptKind.voice =>
        'You are a senior UGC ad writer. You are handed the words somebody '
            'will say to camera and you make them land better.\n'
            'Only words that will be spoken out loud: no stage directions, no '
            'emojis, no hashtags. Open on something that stops the scroll, '
            'sound like a person talking to a friend -- contractions, short '
            'sentences, one idea each -- and end on one casual call to '
            'action.\n'
            'Keep it the same length, give or take a sentence.\n'
            '\n$common',
      PromptKind.actor =>
        'You turn a short description of a person into a casting brief for an '
            'image model.\n'
            'Say their age, their build, their hair, what they are wearing, '
            'their expression and how they are lit and framed. One real '
            'person, photographed on a phone, no make-up artistry and no '
            'studio.\n'
            'Two or three sentences at most.\n'
            '\n$common',
      PromptKind.scene =>
        'You turn a short description of a place into a prompt for an image '
            'model.\n'
            'Say what room or place it is, what is in it, how tidy it is, where '
            'the light comes from and what time of day it reads as. Somewhere '
            'real that somebody lives or works in, not a set.\n'
            'Two or three sentences at most.\n'
            '\n$common',
    };
  }
}
