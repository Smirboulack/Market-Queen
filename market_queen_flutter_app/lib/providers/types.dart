/// Requests handed to providers. Everything a provider needs is in the object:
/// providers never read settings or touch the filesystem themselves.
library;

import 'dart:typed_data';

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

/// One free-form question to a writer model, answered as plain text.
///
/// The script writers all answer in a fixed JSON shape because everything
/// downstream of them is a shot list. This is the other kind of call: a
/// sentence in, a sentence out, no schema -- which is what rewriting somebody's
/// prompt is.
class TextRequest {
  TextRequest({
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.system = '',
    this.user = '',
    this.imageDataUri = '',
    this.maxTokens = 700,
  });

  final String apiKey;
  final String model;

  /// Optional override (OpenAI-compatible gateways).
  final String baseUrl;

  final String system;
  final String user;

  /// A picture the question is about, for the vision-capable writers.
  ///
  /// This is what turns "rewrite my prompt" into "look at this face and tell me
  /// what it sounds like": the same three wire formats, one more part in the
  /// message. A model without vision simply never gets handed one.
  final String imageDataUri;

  /// A rewritten prompt is a paragraph. The ceiling is here so a model that
  /// decides to explain itself cannot bill for a page of it.
  final int maxTokens;
}

class ImageRequest {
  ImageRequest({
    this.apiKey = '',
    this.model = '',
    this.prompt = '',
    this.aspectRatio = '9:16',
    this.referenceImageDataUri = '',
    this.size = '',
    this.quality = '',
  });

  final String apiKey;
  final String model;
  final String prompt;

  /// "9:16", "1:1", "16:9".
  final String aspectRatio;
  final String referenceImageDataUri;

  /// "1K", "2K", "4K", or empty for the model's own default. Only the models
  /// that declare a choice are ever handed one -- see [ImageCapabilities].
  final String size;

  /// The provider's own quality value, sent verbatim, or empty when the model
  /// has no such field.
  final String quality;
}

/// One file on its way to a provider's storage: the bytes, what they are, and
/// what to call them once they are there.
class UploadFile {
  const UploadFile(this.data, this.contentType, this.name);

  final Uint8List data;
  final String contentType;
  final String name;
}

/// The reference material a multimodal video model is handed.
///
/// This is a different way of asking for a clip. An image-to-video model takes
/// one still and animates forward from it; a reference model takes a pile of
/// material -- stills, clips, recordings -- and the prompt points at each piece
/// by handle: `@Image1`, `@Video1`, `@Audio1`. Handing it a real ad as `@Video1`
/// and a new face as `@Image1` is what reproduces the ad with that face in it,
/// cuts and b-roll included.
///
/// Each entry is whatever the endpoint reads: an http url for a provider with
/// storage behind it, and a `data:` URI for the ones this app calls directly
/// and has nowhere to upload to. The caller decides which, per modality, from
/// what the model declares -- BytePlus reads a still and a recording as base64
/// but a reference clip only as a url it can fetch.
class VideoReferences {
  const VideoReferences({
    this.images = const [],
    this.videos = const [],
    this.audios = const [],
    this.imagesField = '',
    this.videosField = '',
    this.audiosField = '',
  });

  static const none = VideoReferences();

  final List<String> images;
  final List<String> videos;
  final List<String> audios;

  /// What this model calls each list, read from its own schema.
  final String imagesField;
  final String videosField;
  final String audiosField;

  bool get isEmpty => images.isEmpty && videos.isEmpty && audios.isEmpty;

  /// Only the lists the model actually declares, and only the non-empty ones:
  /// fal rejects a field the endpoint does not know, and an empty array is not
  /// the same request as no array.
  Map<String, Object?> toInput() => {
        if (imagesField.isNotEmpty && images.isNotEmpty) imagesField: images,
        if (videosField.isNotEmpty && videos.isNotEmpty) videosField: videos,
        if (audiosField.isNotEmpty && audios.isNotEmpty) audiosField: audios,
      };

  /// The handles the prompt should use, in the order the lists were sent:
  /// "@Image1 = face.png, @Video1 = original.mp4". Logged before a run so the
  /// mapping is visible rather than guessed at.
  List<String> get handles => [
        for (var i = 0; i < images.length; ++i) '@Image${i + 1}',
        for (var i = 0; i < videos.length; ++i) '@Video${i + 1}',
        for (var i = 0; i < audios.length; ++i) '@Audio${i + 1}',
      ];
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
    this.references = VideoReferences.none,
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

  /// Set instead of [imageDataUri] for the models that take reference material.
  /// When it is non-empty there is no opening frame: the references are the
  /// input, and the prompt addresses them by handle.
  final VideoReferences references;
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
    this.resolution = '',
  });

  final String apiKey;
  final String model;

  /// The actor, framed for this shot.
  final String imageDataUri;

  /// What they say during it.
  final String audioDataUri;

  /// Optional nudge on the motion.
  final String prompt;

  /// "720p" or "1080p", for the engines that price and cap themselves by it.
  /// Empty leaves the provider's own default alone.
  final String resolution;
}

/// A voice conjured out of a description instead of picked off a shelf.
///
/// The point of it, for this app, is the actor made from a photograph: nothing
/// in a picture is a voice, but a young woman filming herself in a kitchen has
/// a plausible one, and describing it is something a vision model can do. What
/// comes back is an *inference*, never a recovery -- see [VoicePreview].
class VoiceDesignRequest {
  VoiceDesignRequest({
    this.apiKey = '',
    this.model = 'eleven_ttv_v3',
    this.description = '',
    this.previewText = '',
    this.referenceAudioBase64 = '',
    this.promptStrength = 0.5,
    this.loudness = 0.5,
    this.guidance = 5.0,
    this.seed = 0,
  });

  final String apiKey;

  /// `eleven_ttv_v3` or `eleven_multilingual_ttv_v2`. Only the v3 engine reads
  /// [referenceAudioBase64].
  final String model;

  /// What the voice should sound like, in words. ElevenLabs wants at least
  /// twenty characters of it.
  final String description;

  /// The line the previews read. Their endpoint takes 100–1000 characters or
  /// nothing at all; anything shorter is dropped and the engine writes its own.
  final String previewText;

  /// A recording to take the timbre from, base64 with no data: prefix.
  final String referenceAudioBase64;

  /// How much of the answer comes from the words rather than the recording.
  final double promptStrength;

  final double loudness;

  /// How closely the engine sticks to the description. Higher is more literal
  /// and less varied.
  final double guidance;

  /// Zero means "let it choose", which is what makes two presses differ.
  final int seed;
}

/// One of the three takes a design comes back with.
///
/// It is not a voice yet: it exists only inside the design call until somebody
/// picks it, which is what [VoiceSaveRequest] does with the id.
class VoicePreview {
  const VoicePreview({
    required this.generatedVoiceId,
    required this.audio,
    this.extension = 'mp3',
    this.durationSeconds = 0,
    this.language = '',
  });

  final String generatedVoiceId;
  final Uint8List audio;
  final String extension;
  final double durationSeconds;
  final String language;
}

/// Keeping one of the three. The two that were played and passed over travel
/// with it: ElevenLabs asks for them, and they are what teaches the designer
/// what a rejection looks like.
class VoiceSaveRequest {
  VoiceSaveRequest({
    this.apiKey = '',
    this.name = '',
    this.description = '',
    this.generatedVoiceId = '',
    this.passedOver = const [],
  });

  final String apiKey;
  final String name;
  final String description;
  final String generatedVoiceId;
  final List<String> passedOver;
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

/// A voice the user actually keeps, as against one they could pick.
///
/// [VoiceOption] answers "what can this provider say a line with"; this answers
/// "what is on my shelf" -- which is a different question with different
/// consequences, because everything here was either designed, cloned or saved
/// on purpose and deleting one takes it off every actor using it.
///
/// [sharedId] is the whole reason this is not a [VoiceOption]. A voice adopted
/// out of the shared library gets a fresh id on the account, so the shortlist
/// row and the shelf entry for one voice carry two different ids; without the
/// original the interface cannot tell that the row you are looking at is
/// already saved, and offers to save it again.
class AccountVoice {
  const AccountVoice({
    required this.id,
    this.name = '',
    this.category = '',
    this.description = '',
    this.previewUrl = '',
    this.sharedId = '',
  });

  final String id;
  final String name;

  /// ElevenLabs' own word for where it came from: `premade`, `cloned`,
  /// `generated` or `professional`.
  final String category;

  final String description;
  final String previewUrl;

  /// The shared-library id this was adopted from, empty when it was not.
  final String sharedId;

  /// Whether the user made this one, as against it being stock. The shelf shows
  /// only theirs: twenty premade voices nobody chose are not "my voices".
  bool get mine => category.isNotEmpty && category != 'premade';
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
