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

  /// rewriteScript only: the scenario to rework, as one entry.
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
  });

  final String apiKey;
  final String model;
  final String prompt;

  /// First frame.
  final String imageDataUri;
  final String aspectRatio;
  final int durationSeconds;
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
