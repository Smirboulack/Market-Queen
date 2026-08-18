import '../core/http_util.dart';
import '../core/settings_store.dart';
import 'provider_task.dart';
import 'types.dart';
import 'voice_profile.dart';
import 'voice_providers.dart';

/// One preset of a provider whose voices are a fixed, documented handful.
typedef _Preset = ({
  String id,
  String engine,
  String gender,
  String age,
  String tone,
});

/// Turns a casting brief into voices the provider will actually accept.
///
/// Three jobs, deliberately separate:
///
///  * **Searching** asks the provider who fits the brief. Cached, because the
///    answer does not change between two clicks on a chip -- but only for a
///    day, because the library gains voices every week and a permanent cache
///    would quietly freeze the app on whoever was trending the day it first
///    ran.
///  * **Adopting** puts a library voice on the user's account, which is what
///    lets it speak. Once per voice, on first use.
///  * **Choosing** is the user's, or failing that the top of the list.
///
/// Generating audio is none of its business: it hands back a voice id, and what
/// the pipeline does with it -- v3, v2, at what stability -- is decided
/// elsewhere and stays that way.
class VoiceCasting {
  VoiceCasting(this._settings);

  static const _searchKey = 'voiceSearches';
  static const _adoptedKey = 'voiceAdopted';

  /// How long a shortlist is worth reusing.
  static const cacheLife = Duration(hours: 24);

  final SettingsStore _settings;

  // ---- Searching ---------------------------------------------------------

  /// The shortlist already on file for a brief, or null when there is none or
  /// it has aged out. Synchronous, so the editor can draw the list it drew last
  /// time without a round trip.
  VoiceShortlist? remembered(String providerId, VoiceProfile profile) {
    final entry = _searches[_key(providerId, profile)];
    if (entry is! Map) return null;

    final at = entry['at'];
    if (at is! num) return null;
    final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000));
    if (age > cacheLife || age.isNegative) return null;

    final raw = entry['voices'];
    if (raw is! List) return null;

    return (
      voices: [
        for (final voice in raw)
          if (voice is Map) LibraryVoice.fromJson(voice.cast<String, Object?>()),
      ],
      relaxed: [
        for (final filter in (entry['relaxed'] as List?) ?? const []) '$filter',
      ],
    );
  }

  /// Who fits the brief, best first.
  ///
  /// [refresh] skips the cache, which is what the reload button is for: the
  /// library is somebody else's data and the user has to be able to ask again.
  Future<VoiceShortlist> shortlist({
    required String providerId,
    required String apiKey,
    required String modelId,
    required VoiceProfile profile,
    bool refresh = false,
    void Function(ProviderTask task)? onTask,
  }) async {
    // Providers with a fixed set have nothing to search and nothing to cache.
    final presets = _fromPresets(providerId, modelId, profile);
    if (presets != null) return (voices: presets, relaxed: const <String>[]);

    if (!refresh) {
      final known = remembered(providerId, profile);
      if (known != null) return known;
    }

    final task = ElevenLabsVoiceSearchTask(apiKey: apiKey, profile: profile);
    onTask?.call(task);

    final result = await task.run();
    final voices = (result['voices'] as List?)?.cast<LibraryVoice>() ?? const [];
    final relaxed = (result['relaxed'] as List?)?.cast<String>() ?? const [];

    if (voices.isEmpty && task.error.isNotEmpty) {
      throw ProviderException(task.error);
    }

    _remember(providerId, profile, voices, relaxed);
    return (voices: voices, relaxed: relaxed);
  }

  /// Forgets every shortlist. The reload button's second half: a stale entry
  /// for a brief the user is not looking at is no use to anyone either.
  void forgetSearches() => _settings.setPref(_searchKey, <String, Object?>{});

  // ---- Adopting ----------------------------------------------------------

  /// The id text-to-speech will take.
  ///
  /// A library listing is not a voice you can speak with: it has to be on the
  /// account first, and the copy has its own id. That happens here, once, and
  /// the mapping is kept -- so the audition pays for it and every render after
  /// is a straight call.
  Future<String> speakable({
    required String apiKey,
    required String voiceId,
    String ownerId = '',
    String name = '',
    void Function(ProviderTask task)? onTask,
  }) async {
    if (voiceId.isEmpty || ownerId.isEmpty) return voiceId;

    final known = '${_adopted[voiceId] ?? ''}';
    if (known.isNotEmpty) return known;

    final task = ElevenLabsVoiceAdoptTask(
      apiKey: apiKey,
      voiceId: voiceId,
      ownerId: ownerId,
      name: name,
    );
    onTask?.call(task);

    final result = await task.run();
    final adopted = '${result['voiceId'] ?? ''}';
    if (adopted.isEmpty) return voiceId;

    _settings.setPref(_adoptedKey, {..._adopted, voiceId: adopted});
    return adopted;
  }

  // ---- Choosing ----------------------------------------------------------

  /// The voice this actor is read by: the one they were cast with, or failing
  /// that whoever tops the brief.
  ///
  /// [source] is an actor's extras or a run request -- both carry `voiceId`,
  /// `voiceOwner`, `voiceName` and the brief's keys, so one call serves the
  /// audition and the render and they cannot disagree.
  Future<VoiceOption> voiceFor({
    required String providerId,
    required String apiKey,
    required String modelId,
    required Map<String, Object?> source,
    void Function(ProviderTask task)? onTask,
  }) async {
    final chosen = '${source['voiceId'] ?? ''}';
    if (chosen.isNotEmpty) {
      final id = await speakable(
        apiKey: apiKey,
        voiceId: chosen,
        ownerId: '${source['voiceOwner'] ?? ''}',
        name: '${source['voiceName'] ?? ''}',
        onTask: onTask,
      );
      return VoiceOption(id, '${source['voiceName'] ?? ''}', '');
    }

    final profile = VoiceProfile.from(source);
    final found = await shortlist(
      providerId: providerId,
      apiKey: apiKey,
      modelId: modelId,
      profile: profile,
      onTask: onTask,
    );

    if (found.voices.isEmpty) return const VoiceOption('', '', '');

    final top = found.voices.first;
    final id = await speakable(
      apiKey: apiKey,
      voiceId: top.id,
      ownerId: top.ownerId,
      name: top.name,
      onTask: onTask,
    );
    return VoiceOption(id, top.name, describeVoice(top));
  }

  // ---- Stored state ------------------------------------------------------

  Map<String, Object?> get _searches {
    final stored = _settings.pref<Object>(_searchKey);
    return stored is Map ? stored.cast<String, Object?>() : const {};
  }

  Map<String, Object?> get _adopted {
    final stored = _settings.pref<Object>(_adoptedKey);
    return stored is Map ? stored.cast<String, Object?>() : const {};
  }

  String _key(String providerId, VoiceProfile profile) =>
      '$providerId|${profile.signature}';

  void _remember(
    String providerId,
    VoiceProfile profile,
    List<LibraryVoice> voices,
    List<String> relaxed,
  ) {
    // A fresh map every time: `setPref` skips the write when it is handed the
    // value already stored, which a mutated-in-place map always is.
    final updated = Map<String, Object?>.of(_searches);
    updated[_key(providerId, profile)] = {
      'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'relaxed': relaxed,
      'voices': [for (final voice in voices) voice.toJson()],
    };
    _settings.setPref(_searchKey, updated);
  }

  // ---- Providers with a fixed set ----------------------------------------

  /// Null when the provider has a library to search rather than a shelf to pick
  /// from.
  List<LibraryVoice>? _fromPresets(
      String providerId, String modelId, VoiceProfile profile) {
    final presets = _presets[providerId];
    if (presets == null) return null;

    // fal is several engines behind one key, and a MiniMax voice name means
    // nothing to Kokoro. Only the ones the chosen engine owns are candidates.
    final model = modelId.toLowerCase();
    final candidates = [
      for (final preset in presets)
        if (preset.engine.isEmpty || model.contains(preset.engine)) preset,
    ];
    if (candidates.isEmpty) return const [];

    int score(_Preset preset) {
      var value = 0;
      if (profile.gender.isNotEmpty && preset.gender == profile.gender) {
        value += 15;
      }
      if (profile.age.isNotEmpty && preset.age == profile.age) value += 10;
      if (profile.tone.isNotEmpty && preset.tone == profile.tone) value += 5;
      return value;
    }

    final ordered = List<_Preset>.of(candidates)
      ..sort((a, b) {
        final byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : a.id.compareTo(b.id);
      });

    return [
      for (final preset in ordered.take(6))
        LibraryVoice(
          id: preset.id,
          name: preset.id,
          gender: preset.gender,
          age: preset.age,
          descriptive: preset.tone,
        ),
    ];
  }

  /// How each fixed voice reads, as the brief would describe it. Neither
  /// provider publishes these as data, so they are what the voices sound like
  /// rather than what an API said.
  static const _presets = <String, List<_Preset>>{
    'minimax-tts': [
      (id: 'Inspirational_girl', engine: '', gender: 'female', age: 'young', tone: 'upbeat'),
      (id: 'Lively_Girl', engine: '', gender: 'female', age: 'young', tone: 'excited'),
      (id: 'Sweet_Girl_2', engine: '', gender: 'female', age: 'young', tone: 'chill'),
      (id: 'Calm_Woman', engine: '', gender: 'female', age: 'middle_aged', tone: 'calm'),
      (id: 'Wise_Woman', engine: '', gender: 'female', age: 'old', tone: 'professional'),
      (id: 'Casual_Guy', engine: '', gender: 'male', age: 'young', tone: 'casual'),
      (id: 'Young_Knight', engine: '', gender: 'male', age: 'young', tone: 'confident'),
      (id: 'Friendly_Person', engine: '', gender: 'male', age: 'middle_aged', tone: 'chill'),
      (id: 'Patient_Man', engine: '', gender: 'male', age: 'middle_aged', tone: 'calm'),
      (id: 'Elegant_Man', engine: '', gender: 'male', age: 'middle_aged', tone: 'professional'),
      (id: 'Deep_Voice_Man', engine: '', gender: 'male', age: 'old', tone: 'deep'),
    ],
    // Gemini names its voices for the character rather than the speaker, so the
    // gender column is deliberately blank: the model reads the same voice as a
    // man or a woman depending on the line, and claiming otherwise here would
    // send the casting search after a difference that is not there.
  };
}
