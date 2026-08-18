import 'package:flutter/foundation.dart';

import '../core/http_util.dart';
import '../core/log_model.dart';
import '../core/settings_store.dart';
import '../i18n/translator.dart';
import '../providers/registry.dart';
import '../providers/types.dart';
import '../providers/voice_providers.dart';
import 'voice_forge.dart' show VoiceForge;

/// The voices the user keeps, as against the ten thousand they could pick.
///
/// Designing and cloning both leave something permanent on the provider
/// account, and until now the app could put voices there and never show them
/// again: a voice designed for one actor was invisible to the next, so the
/// second actor got a second design and the account filled up with near
/// duplicates nobody could see, let alone delete.
///
/// So the shelf is one list, loaded once and shared by every actor. Two verbs
/// live here and they are deliberately different from each other:
///
///  * [keep] puts a shared-library voice on the account, which is what makes it
///    reusable. It is the same call a render makes on first use -- doing it up
///    front only means the user chose the moment. ElevenLabs only: it is a
///    shared library that has anything to adopt *from*, and the providers that
///    ship a fixed set of presets need nothing kept.
///  * [remove] deletes one, which reaches every actor using it and cannot be
///    undone. Taking a voice off *one* actor is not this: that is a write to
///    the actor and nothing leaves the account.
///
/// The account it reads is whichever the app's voice preference names -- the
/// same one the workshop makes voices on and the same one the render reads
/// with. Switching providers is therefore a different shelf, not a filtered
/// view of one, which is why [load] is re-run rather than re-sorted.
class VoiceShelf extends ChangeNotifier {
  VoiceShelf(this._settings, this._registry, this._log);

  final SettingsStore _settings;
  final Registry _registry;
  final LogModel _log;

  List<AccountVoice> _voices = const [];
  bool _loading = false;
  bool _working = false;
  String _error = '';

  /// Which account the list in hand was read from, empty before the first read.
  /// Compared on every [load] so switching provider always refetches.
  String _loadedFrom = '';

  /// Everything the user made or saved, newest last -- the account's own order,
  /// which is the order they were created in.
  List<AccountVoice> get voices => List.unmodifiable(_voices);

  bool get loading => _loading;

  /// A keep or a delete is in flight. Separate from [loading] so the list can
  /// stay readable while one row is being worked on.
  bool get working => _working;

  String get error => _error;

  /// The account the shelf belongs to. Same rule as [VoiceForge.provider], and
  /// deliberately the same preference.
  String get provider {
    final saved = _settings.prefString('voiceProvider');
    return VoiceForge.worksWith(saved) ? saved : VoiceForge.providers.first;
  }

  String get _apiKey => _settings.apiKey(_registry.credentialFor(provider));

  /// Whether there is a key to read the shelf with.
  bool get ready => _apiKey.isNotEmpty;

  /// Whether this provider has a shared library to save voices out of. Without
  /// one the ribbon on a search result has nothing to do.
  bool get adopts => provider == 'elevenlabs';

  /// Whether the account already holds [voiceId].
  ///
  /// Takes either id: a row of the shared library carries the listing's id, and
  /// the account's copy of it carries its own. Both mean "saved".
  bool holds(String voiceId) {
    if (voiceId.isEmpty) return false;
    for (final voice in _voices) {
      if (voice.id == voiceId || voice.sharedId == voiceId) return true;
    }
    return false;
  }

  /// Reads the account, once per session unless [refresh] is set.
  ///
  /// Not on construction: an account read costs a round trip on a key the user
  /// may not have entered yet, and nothing needs the shelf until somebody opens
  /// the voice section.
  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    final account = provider;
    if (_loadedFrom == account && !refresh) return;
    if (!ready) {
      _voices = const [];
      _loadedFrom = '';
      _error = '';
      notifyListeners();
      return;
    }

    _loading = true;
    _error = '';
    // Cleared up front rather than left standing: the list on screen belongs to
    // the account that was open a moment ago, and showing ElevenLabs voices
    // under a MiniMax heading while the fetch runs is a list you could act on.
    if (_loadedFrom != account) _voices = const [];
    notifyListeners();

    try {
      final result = await (account == 'elevenlabs'
              ? ElevenLabsAccountVoicesTask(_apiKey)
              : MiniMaxAccountVoicesTask(_apiKey))
          .run();
      final all = (result['voices'] as List?)?.cast<AccountVoice>() ?? const [];
      // Only theirs. The premade voices are on every account ever made and are
      // not something anybody kept.
      _voices = [
        for (final voice in all)
          if (voice.mine) voice,
      ];
      _loadedFrom = account;
      _loading = false;
      notifyListeners();
    } on ProviderException catch (error) {
      _error = error.message;
      _loading = false;
      notifyListeners();
    }
  }

  /// Saves a shared-library voice onto the account and returns the copy's id,
  /// or an empty string when it failed.
  Future<String> keep({
    required String voiceId,
    required String ownerId,
    required String name,
  }) async {
    if (_working || voiceId.isEmpty || !adopts) return '';

    _working = true;
    _error = '';
    notifyListeners();

    try {
      final result = await ElevenLabsVoiceAdoptTask(
        apiKey: _apiKey,
        voiceId: voiceId,
        ownerId: ownerId,
        name: name,
      ).run();
      final kept = '${result['voiceId'] ?? ''}';
      _working = false;
      //: %1 is a voice's name
      if (kept.isNotEmpty) _log.success(tr('Voice "%1" is on your account.').arg(name));
      notifyListeners();
      // The copy's own id and its labels are the account's to report, so the
      // shelf is re-read rather than guessed at.
      await load(refresh: true);
      return kept;
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Could not keep the voice: %1').arg(error.message));
        _error = error.message;
      }
      _working = false;
      notifyListeners();
      return '';
    }
  }

  /// Deletes [voiceId] from the account. True when it is gone.
  Future<bool> remove(String voiceId) async {
    if (_working || voiceId.isEmpty) return false;

    // Which of MiniMax's two buckets it came out of, which their delete call
    // insists on. Read off the list rather than guessed: a designed voice
    // deleted as a cloned one is a 400 and a row that never goes away.
    final cloned = _voices
        .where((voice) => voice.id == voiceId)
        .every((voice) => voice.category != 'generated');

    _working = true;
    _error = '';
    notifyListeners();

    try {
      await (provider == 'elevenlabs'
              ? ElevenLabsVoiceDeleteTask(apiKey: _apiKey, voiceId: voiceId)
              : MiniMaxVoiceDeleteTask(
                  apiKey: _apiKey,
                  voiceId: voiceId,
                  cloned: cloned,
                ))
          .run();
      _voices = [
        for (final voice in _voices)
          if (voice.id != voiceId) voice,
      ];
      _working = false;
      notifyListeners();
      return true;
    } on ProviderException catch (error) {
      if (error is! TaskCancelled) {
        _log.error(tr('Could not delete the voice: %1').arg(error.message));
        _error = error.message;
      }
      _working = false;
      notifyListeners();
      return false;
    }
  }

  /// Where a kept voice came from, in one word -- what the row under its name
  /// says.
  static String provenanceOf(AccountVoice voice) => switch (voice.category) {
        'generated' => tr('Designed'),
        'cloned' || 'professional' => tr('Cloned'),
        _ => tr('Library'),
      };
}
