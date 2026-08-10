import '../i18n/translator.dart';
import 'types.dart';

/// One entry of the language chip: a language, and optionally the region it is
/// spoken in.
///
/// Region is carried as ElevenLabs' `locale`, never as its `accent`. That is
/// not a detail. Their `accent` vocabulary is scoped to the language a voice
/// speaks, and the value "french" belongs to *English* -- it means an English
/// voice with a French accent. Asking for `language=fr&accent=french` returns
/// English voices, which is precisely how a French brief used to come back read
/// by an American:
///
///     language=fr accent=french    -> Benji [en], Cyril [en], Lama [en]
///     language=fr locale=fr-FR     -> Nathalie [fr], Antonin [fr], David [fr]
///
/// The locales below are the ones the library actually has voices under.
class VoiceLocale {
  const VoiceLocale(this.flag, this.label, this.language, [this.locale = '']);

  final String flag;
  final String label;

  /// ElevenLabs' `language` filter: ISO 639-1, lower case.
  final String language;

  /// ElevenLabs' `locale` filter. Empty means "any region of that language".
  /// Note Chinese: the library files it under `cmn-CN` / `cmn-TW`, not `zh-*`.
  final String locale;

  /// What the actor stores. The locale when there is one, so the two are
  /// distinguishable at a glance in a saved file.
  String get id => locale.isEmpty ? language : locale;

  String get menuLabel => '$flag  $label';

  static List<VoiceLocale> get all => [
    VoiceLocale('🇫🇷', tr('French — all regions'), 'fr'),
    VoiceLocale('🇫🇷', tr('French — France'), 'fr', 'fr-FR'),
    VoiceLocale('🇨🇦', tr('French — Quebec'), 'fr', 'fr-CA'),
    VoiceLocale('🇧🇪', tr('French — Belgium'), 'fr', 'fr-BE'),
    VoiceLocale('🇨🇭', tr('French — Switzerland'), 'fr', 'fr-CH'),
    VoiceLocale('🇬🇧', tr('English — all regions'), 'en'),
    VoiceLocale('🇺🇸', tr('English — United States'), 'en', 'en-US'),
    VoiceLocale('🇬🇧', tr('English — United Kingdom'), 'en', 'en-GB'),
    VoiceLocale('🇦🇺', tr('English — Australia'), 'en', 'en-AU'),
    VoiceLocale('🇨🇦', tr('English — Canada'), 'en', 'en-CA'),
    VoiceLocale('🇪🇸', tr('Spanish — all regions'), 'es'),
    VoiceLocale('🇪🇸', tr('Spanish — Spain'), 'es', 'es-ES'),
    VoiceLocale('🇲🇽', tr('Spanish — Mexico'), 'es', 'es-MX'),
    VoiceLocale('🇦🇷', tr('Spanish — Argentina'), 'es', 'es-AR'),
    VoiceLocale('🇩🇪', tr('German'), 'de'),
    VoiceLocale('🇮🇹', tr('Italian'), 'it'),
    VoiceLocale('🇧🇷', tr('Portuguese — Brazil'), 'pt', 'pt-BR'),
    VoiceLocale('🇵🇹', tr('Portuguese — Portugal'), 'pt', 'pt-PT'),
    VoiceLocale('🇳🇱', tr('Dutch'), 'nl'),
    VoiceLocale('🇧🇪', tr('Dutch — Flemish'), 'nl', 'nl-BE'),
    VoiceLocale('🇵🇱', tr('Polish'), 'pl'),
    VoiceLocale('🇷🇺', tr('Russian'), 'ru'),
    VoiceLocale('🇨🇳', tr('Chinese — Mainland'), 'zh', 'cmn-CN'),
    VoiceLocale('🇹🇼', tr('Chinese — Taiwan'), 'zh', 'cmn-TW'),
    VoiceLocale('🇸🇦', tr('Arabic'), 'ar'),
    VoiceLocale('🇪🇬', tr('Arabic — Egypt'), 'ar', 'ar-EG'),
    VoiceLocale('🇲🇦', tr('Arabic — Morocco'), 'ar', 'ar-MA'),
  ];

  static VoiceLocale? find(String id) {
    for (final entry in all) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

/// One optional trait of a casting brief.
///
/// The values are ElevenLabs' own, verbatim and lower case, because that is the
/// only spelling their search honours: `gender=Female` and `use_cases=Social
/// Media` both return zero voices where `female` and `social_media` return
/// hundreds. A trait therefore goes into the query untouched.
class VoiceTrait {
  const VoiceTrait(this.key, this.label, this.options);

  /// The key it is stored under, on the actor and in the run request.
  final String key;
  final String label;

  /// Label shown, value filtered on.
  final List<(String, String)> options;

  static List<VoiceTrait> get all => [
    VoiceTrait('voiceGender', tr('Gender'), [
      (tr('Female'), 'female'),
      (tr('Male'), 'male'),
    ]),
    VoiceTrait('voiceAge', tr('Age'), [
      (tr('Young'), 'young'),
      (tr('Adult'), 'middle_aged'),
      (tr('Mature'), 'old'),
    ]),
    // Their `use_cases`. Social media is kept distinct from advertisement on
    // purpose: it is the filter that returns creator voices rather than
    // announcers, and collapsing UGC onto "advertisement" throws that away.
    VoiceTrait('voiceUse', tr('For'), [
      (tr('Social media'), 'social_media'),
      (tr('Advertisement'), 'advertisement'),
      (tr('Conversational'), 'conversational'),
      (tr('Narration'), 'narrative_story'),
      (tr('Explainer'), 'informative_educational'),
      (tr('Characters'), 'characters_animation'),
    ]),
    // Their `descriptives`, and only ones the library really uses: "energetic"
    // and "warm" are not in the vocabulary at all and return nothing.
    VoiceTrait('voiceTone', tr('Tone'), [
      (tr('Upbeat'), 'upbeat'),
      (tr('Excited'), 'excited'),
      (tr('Casual'), 'casual'),
      (tr('Confident'), 'confident'),
      (tr('Calm'), 'calm'),
      (tr('Chill'), 'chill'),
      (tr('Professional'), 'professional'),
      (tr('Deep'), 'deep'),
    ]),
  ];

  /// What a stored value reads as. Empty when nothing is set, so a brief can be
  /// written out by joining whatever comes back.
  static String labelFor(String key, String value) {
    if (value.isEmpty) return '';
    for (final trait in all) {
      if (trait.key != key) continue;
      for (final option in trait.options) {
        if (option.$2 == value) return option.$1;
      }
    }
    return value;
  }
}

/// Who should read the ad, described the way a casting brief is.
///
/// This is what the app asks for instead of a voice id, and -- the part that
/// matters -- it is turned into a real Voice Library query rather than used to
/// sift a generic list after the fact. Ten thousand voices cannot be filtered
/// client-side; asking the library for `fr` + `fr-FR` + `female` + `young` +
/// `social_media` returns twelve, and they are the right twelve.
class VoiceProfile {
  const VoiceProfile({
    this.locale = '',
    this.gender = '',
    this.age = '',
    this.useCase = '',
    this.tone = '',
  });

  /// Reads a brief out of an actor's extras or a run request: both carry these
  /// keys, so one accessor serves the editor and the render.
  factory VoiceProfile.from(Map<String, Object?> source) => VoiceProfile(
    locale: '${source['voiceLocale'] ?? ''}',
    gender: '${source['voiceGender'] ?? ''}',
    age: '${source['voiceAge'] ?? ''}',
    useCase: '${source['voiceUse'] ?? ''}',
    tone: '${source['voiceTone'] ?? ''}',
  );

  /// Every key a brief occupies, for the callers that copy it wholesale.
  static const keys = <String>[
    'voiceLocale',
    'voiceGender',
    'voiceAge',
    'voiceUse',
    'voiceTone',
  ];

  /// The order filters are given up in when a brief matches nobody, least
  /// telling first. `language` is absent on purpose: it is never given up.
  ///
  /// Region goes before gender, which looks backwards next to the ranking
  /// weights -- it is not. A Belgian woman is a better answer to "a woman from
  /// France" than a man from France is, so region is what bends first.
  static const relaxationOrder = <String>[
    'descriptives',
    'use_cases',
    'age',
    'locale',
    'gender',
  ];

  final String locale;
  final String gender;
  final String age;
  final String useCase;
  final String tone;

  bool get isEmpty =>
      locale.isEmpty &&
      gender.isEmpty &&
      age.isEmpty &&
      useCase.isEmpty &&
      tone.isEmpty;

  /// The language actually asked for. An unset chip does not mean "any
  /// language": it means the one the ad is written in, which is the one the
  /// interface is in.
  String get language =>
      VoiceLocale.find(locale)?.language ?? Translator.instance.currentLanguage;

  /// The region, when one was asked for. Empty means any region.
  String get region => VoiceLocale.find(locale)?.locale ?? '';

  /// The query, in the exact spelling the search honours. Only what was asked
  /// for is sent: an unset trait widens the search rather than narrowing it to
  /// nothing.
  Map<String, String> get filters => {
    if (language.isNotEmpty) 'language': language,
    if (region.isNotEmpty) 'locale': region,
    if (gender.isNotEmpty) 'gender': gender,
    if (age.isNotEmpty) 'age': age,
    if (useCase.isNotEmpty) 'use_cases': useCase,
    if (tone.isNotEmpty) 'descriptives': tone,
  };

  /// What a search under this brief is filed under.
  String get signature => filters.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('&');

  /// The brief in one line, for the log and the editor.
  String get description => [
    VoiceLocale.find(locale)?.label ?? '',
    VoiceTrait.labelFor('voiceGender', gender),
    VoiceTrait.labelFor('voiceAge', age),
    VoiceTrait.labelFor('voiceUse', useCase),
    VoiceTrait.labelFor('voiceTone', tone),
  ].where((part) => part.isNotEmpty).join(' · ');

  /// What a dropped filter is called, for the line that admits the search had
  /// to be widened.
  static String filterLabel(String filter) => switch (filter) {
    'locale' => tr('region'),
    'gender' => tr('gender'),
    'age' => tr('age'),
    'use_cases' => tr('use'),
    'descriptives' => tr('tone'),
    _ => filter,
  };
}

/// What a voice is, in the same words the chips use.
///
/// Shown under the name in the shortlist, which is what makes the shortlist an
/// argument rather than a list: the user can see that every line really does
/// say `fr-FR · Femme · Jeune · Réseaux sociaux`.
String describeVoice(LibraryVoice voice) {
  final parts = <String>[
    voice.locale.isNotEmpty ? voice.locale : voice.language,
    if (voice.accent.isNotEmpty && voice.accent != 'standard') voice.accent,
    VoiceTrait.labelFor('voiceGender', voice.gender),
    VoiceTrait.labelFor('voiceAge', voice.age),
    VoiceTrait.labelFor('voiceUse', voice.useCase),
    VoiceTrait.labelFor('voiceTone', voice.descriptive),
  ];
  return parts.where((part) => part.isNotEmpty).join(' · ');
}
