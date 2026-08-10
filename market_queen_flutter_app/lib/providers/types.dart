/// Requests handed to providers. Everything a provider needs is in the object:
/// providers never read settings or touch the filesystem themselves.
library;

/// Two jobs, one transport. Writing a scenario from nothing and reworking one
/// the user already wrote differ only in the prompt, and are otherwise the same
/// call to the same three providers, returning the same `shots` shape.
enum ScriptMode {
  /// The model writes the words and the visuals.
  writeScript,

  /// The user's own scenario, handed back rewritten. The scenario bar's
  /// Enhance / Shorten / Punchier.
  rewriteScript,

  /// The user's own scenario, already cut into shots, handed back with a camera
  /// on each one. Not a word of it may change: the model answers by position
  /// and only the kind and the two prompts are read back.
  planShots,
}

class ScriptRequest {
  ScriptRequest({
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.mode = ScriptMode.writeScript,
    this.lines = const [],
    this.rewriteInstruction = '',
    this.productName = '',
    this.productDescription = '',
    this.audience = '',
    this.tone = '',
    this.language = '',
    this.avatarBrief = '',
    this.extraInstructions = '',
    this.referenceImageDataUri = '',
    this.durationSeconds = 20,
    this.shotCount = 4,
  });

  final String apiKey;
  final String model;

  /// Optional override (OpenAI-compatible gateways).
  final String baseUrl;
  final ScriptMode mode;

  /// rewriteScript: the scenario to rework, as one entry.
  /// planShots: the shot lines, in order, one entry each.
  final List<String> lines;

  /// rewriteScript only: what to do to it ("make it shorter", "punchier").
  final String rewriteInstruction;

  final String productName;
  final String productDescription;
  final String audience;
  final String tone;
  final String language;

  /// Who is speaking on camera.
  final String avatarBrief;
  final String extraInstructions;

  /// Product photo, passed to vision-capable models.
  final String referenceImageDataUri;

  final int durationSeconds;

  /// How many camera setups to write the ad across.
  final int shotCount;
}

class ImageRequest {
  ImageRequest({
    this.apiKey = '',
    this.model = '',
    this.prompt = '',
    this.aspectRatio = '9:16',
    this.referenceImageDataUri = '',
  });

  final String apiKey;
  final String model;
  final String prompt;

  /// "9:16", "1:1", "16:9".
  final String aspectRatio;
  final String referenceImageDataUri;
}

class VideoRequest {
  VideoRequest({
    this.apiKey = '',
    this.model = '',
    this.prompt = '',
    this.imageDataUri = '',
    this.aspectRatio = '9:16',
    this.durationSeconds = 5,
    this.imageField = '',
    this.extraInput = const {},
  });

  final String apiKey;
  final String model;
  final String prompt;

  /// First frame.
  final String imageDataUri;
  final String aspectRatio;
  final int durationSeconds;

  /// What this model calls its opening frame.
  ///
  /// `image_url` on most of fal, `start_image_url` on Kling. Empty means "we do
  /// not know", and the provider falls back to guessing from the model id the
  /// way it always did.
  final String imageField;

  /// Model-specific inputs the caller read out of the model's own schema:
  /// the duration in the exact spelling its enum uses, the resolution, the
  /// audio switch under whichever name it goes by here.
  ///
  /// Every fal endpoint rejects fields it does not declare, so guessing at
  /// these from the model id was both incomplete and actively harmful. When
  /// this is non-empty the provider sends it as given and adds nothing of its
  /// own.
  final Map<String, Object?> extraInput;
}

/// A talking shot: a still plus the audio it should be saying.
///
/// This is the difference between an ad and a video of someone whose mouth does
/// not match the words. The clip that comes back is exactly as long as the
/// audio, so nothing downstream has to stretch, loop or trim it.
class AvatarRequest {
  AvatarRequest({
    this.apiKey = '',
    this.model = '',
    this.imageDataUri = '',
    this.audioDataUri = '',
    this.prompt = '',
  });

  final String apiKey;
  final String model;

  /// The actor, framed for this shot.
  final String imageDataUri;

  /// What they say during it.
  final String audioDataUri;

  /// Optional nudge on the motion.
  final String prompt;
}

class VoiceRequest {
  VoiceRequest({
    this.apiKey = '',
    this.model = '',
    this.voiceId = '',
    this.text = '',
    this.speed = 1.0,
    this.stability = 0.45,
    this.similarity = 0.8,
    this.style = 0.35,
    this.previousText = '',
    this.nextText = '',
  });

  final String apiKey;
  final String model;
  final String voiceId;
  final String text;
  final double speed;

  // ElevenLabs voice_settings. The defaults are the values that used to be
  // hardcoded in the provider, so a request that leaves them alone behaves
  // exactly as it did before the booth exposed them.
  final double stability;
  final double similarity;
  final double style;

  // Request stitching. An ad recorded scene by scene would otherwise reset its
  // delivery at every join; telling the engine what came before and after each
  // chunk is what keeps one continuous read across the cuts.
  final String previousText;
  final String nextText;
}

/// Instant voice cloning from the user's own recordings. This creates a
/// permanent voice on their provider account, so it is never implicit.
class VoiceCloneRequest {
  VoiceCloneRequest({
    this.apiKey = '',
    this.name = '',
    this.description = '',
    this.samplePaths = const [],
  });

  final String apiKey;
  final String name;
  final String description;
  final List<String> samplePaths;
}

class TranscribeRequest {
  TranscribeRequest({
    this.apiKey = '',
    this.model = '',
    this.audioPath = '',
    this.language = '',
  });

  final String apiKey;
  final String model;
  final String audioPath;
  final String language;
}

/// A voice on the user's account, or one of a provider's fixed presets.
class VoiceOption {
  const VoiceOption(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;
}

/// A voice a search turned up, with the metadata it was matched on.
///
/// The metadata travels with the voice so the interface can show *why* it is on
/// the list -- "fr-FR · female · young · social media" under the name is what
/// turns a shortlist into an argument.
class LibraryVoice {
  const LibraryVoice({
    required this.id,
    this.ownerId = '',
    this.name = '',
    this.language = '',
    this.locale = '',
    this.accent = '',
    this.gender = '',
    this.age = '',
    this.useCase = '',
    this.descriptive = '',
    this.previewUrl = '',
    this.verified = false,
    this.free = true,
    this.premiumRate = false,
    this.clonedBy = 0,
  });

  factory LibraryVoice.fromShared(Map<String, Object?> json) {
    String at(String key) => '${json[key] ?? ''}'.toLowerCase().trim();

    final language = at('language');
    var verified = false;
    final languages = json['verified_languages'];
    if (languages is List) {
      for (final entry in languages) {
        if (entry is Map && '${entry['language'] ?? ''}'.toLowerCase() == language) {
          verified = true;
          break;
        }
      }
    }

    final rate = json['rate'];

    return LibraryVoice(
      id: '${json['voice_id'] ?? ''}',
      ownerId: '${json['public_owner_id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      language: language,
      locale: '${json['locale'] ?? ''}',
      accent: at('accent'),
      gender: at('gender'),
      age: at('age'),
      useCase: at('use_case'),
      descriptive: at('descriptive'),
      previewUrl: '${json['preview_url'] ?? ''}',
      verified: verified,
      free: json['free_users_allowed'] == true,
      // 1.0 is the ordinary rate; anything above it bills the user extra for
      // the same sentence.
      premiumRate: rate is num && rate > 1,
      clonedBy: json['cloned_by_count'] is num
          ? (json['cloned_by_count']! as num).toInt()
          : 0,
    );
  }

  factory LibraryVoice.fromJson(Map<String, Object?> json) => LibraryVoice(
    id: '${json['id'] ?? ''}',
    ownerId: '${json['ownerId'] ?? ''}',
    name: '${json['name'] ?? ''}',
    language: '${json['language'] ?? ''}',
    locale: '${json['locale'] ?? ''}',
    accent: '${json['accent'] ?? ''}',
    gender: '${json['gender'] ?? ''}',
    age: '${json['age'] ?? ''}',
    useCase: '${json['useCase'] ?? ''}',
    descriptive: '${json['descriptive'] ?? ''}',
    previewUrl: '${json['previewUrl'] ?? ''}',
    verified: json['verified'] == true,
    free: json['free'] != false,
    premiumRate: json['premiumRate'] == true,
    clonedBy: json['clonedBy'] is num ? (json['clonedBy']! as num).toInt() : 0,
  );

  final String id;

  /// Who published it. Needed to put the voice on the account before it can
  /// speak; empty for a voice that is already there.
  final String ownerId;

  final String name;
  final String language;
  final String locale;
  final String accent;
  final String gender;
  final String age;
  final String useCase;
  final String descriptive;

  /// A few seconds of the voice, hosted. Free to play -- no credits, no key.
  final String previewUrl;

  /// Its owner has confirmed it in this language, rather than it merely being
  /// able to attempt it.
  final bool verified;

  final bool free;
  final bool premiumRate;
  final int clonedBy;

  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'language': language,
    'locale': locale,
    'accent': accent,
    'gender': gender,
    'age': age,
    'useCase': useCase,
    'descriptive': descriptive,
    'previewUrl': previewUrl,
    'verified': verified,
    'free': free,
    'premiumRate': premiumRate,
    'clonedBy': clonedBy,
  };
}

/// What one search came back with: the voices, and how much of the brief had to
/// be given up to find them.
typedef VoiceShortlist = ({List<LibraryVoice> voices, List<String> relaxed});
