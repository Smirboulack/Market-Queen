import 'package:flutter/foundation.dart';

import '../i18n/translator.dart';
import 'avatar_providers.dart';
import 'image_providers.dart';
import 'provider_task.dart';
import 'text_providers.dart';
import 'types.dart';
import 'video_providers.dart';
import 'voice_providers.dart';

/// A model the user can pick: technical id + something readable.
class ModelEntry {
  const ModelEntry(this.id, this.label);

  final String id;
  final String label;
}

class ProviderEntry {
  const ProviderEntry({
    required this.id,
    required this.category,
    required this.label,
    required this.credential,
    required this.models,
    required this.defaultModel,
    required this.note,
  });

  final String id;

  /// "text", "image", "video", "avatar", "voice", "captions".
  final String category;
  final String label;
  final String credential;
  final List<ModelEntry> models;
  final String defaultModel;
  final String note;
}

class CredentialEntry {
  const CredentialEntry({
    required this.id,
    required this.label,
    required this.envVar,
    required this.signupUrl,
    required this.note,
  });

  final String id;
  final String label;
  final String envVar;
  final String signupUrl;
  final String note;
}

/// Catalogue of everything the app can talk to, plus the factory that turns a
/// provider id into a running task. Adding a provider means adding one entry
/// here and one class in the matching *_providers.dart -- nothing in the UI or
/// the pipeline changes.
class Registry extends ChangeNotifier {
  Registry() {
    _build();
  }

  List<ProviderEntry> _entries = const [];

  List<ProviderEntry> get entries => _entries;

  /// The descriptions are translated, so the list has to be rebuilt when the
  /// language changes.
  void retranslate() {
    _build();
    notifyListeners();
  }

  void _build() {
    // Only the "Auto" entry is translated: model names are product names.
    final auto = ModelEntry('auto', tr('Auto - best model for this shot'));

    _entries = <ProviderEntry>[
      // ---- Script writers -----------------------------------------------
      ProviderEntry(
        id: 'openai-chat',
        category: 'text',
        label: 'OpenAI',
        credential: 'openai',
        models: const [
          ModelEntry('gpt-5.6-terra', 'GPT-5.6 Terra'),
          ModelEntry('gpt-5.6-sol', 'GPT-5.6 Sol'),
          ModelEntry('gpt-5.6-luna', 'GPT-5.6 Luna'),
          ModelEntry('gpt-5.5', 'GPT-5.5'),
          ModelEntry('gpt-5.4', 'GPT-5.4'),
          ModelEntry('gpt-5.2', 'GPT-5.2'),
          ModelEntry('gpt-5.1', 'GPT-5.1'),
          ModelEntry('gpt-5', 'GPT-5'),
          ModelEntry('gpt-5-mini', 'GPT-5 mini'),
          ModelEntry('gpt-5-nano', 'GPT-5 nano'),
          ModelEntry('gpt-4.1', 'GPT-4.1'),
          ModelEntry('gpt-4o', 'GPT-4o'),
          ModelEntry('gpt-4o-mini', 'GPT-4o mini'),
        ],
        defaultModel: 'gpt-5.6-terra',
        note: tr('Reads the product photo when the model supports vision.'),
      ),

      ProviderEntry(
        id: 'anthropic-messages',
        category: 'text',
        label: 'Anthropic (Claude)',
        credential: 'anthropic',
        models: const [
          ModelEntry('claude-sonnet-5', 'Claude Sonnet 5'),
          ModelEntry('claude-opus-5', 'Claude Opus 5'),
          ModelEntry('claude-fable-5', 'Claude Fable 5'),
          ModelEntry('claude-opus-4-8', 'Claude Opus 4.8'),
          ModelEntry('claude-haiku-4-5-20251001', 'Claude Haiku 4.5'),
        ],
        defaultModel: 'claude-sonnet-5',
        note: tr('Strong at short, natural-sounding ad copy.'),
      ),

      ProviderEntry(
        id: 'gemini-generate',
        category: 'text',
        label: 'Google Gemini',
        credential: 'gemini',
        models: const [
          ModelEntry('gemini-3.5-flash', 'Gemini 3.5 Flash'),
          ModelEntry('gemini-3.6-flash', 'Gemini 3.6 Flash'),
          ModelEntry('gemini-3.5-flash-lite', 'Gemini 3.5 Flash Lite'),
          ModelEntry('gemini-3.1-pro-preview', 'Gemini 3.1 Pro'),
          ModelEntry('gemini-3.1-flash-lite', 'Gemini 3.1 Flash Lite'),
          ModelEntry('gemini-2.5-pro', 'Gemini 2.5 Pro'),
          ModelEntry('gemini-2.5-flash', 'Gemini 2.5 Flash'),
          ModelEntry('gemini-2.5-flash-lite', 'Gemini 2.5 Flash Lite'),
          ModelEntry('gemini-2.0-flash', 'Gemini 2.0 Flash'),
        ],
        defaultModel: 'gemini-3.5-flash',
        note: tr('Free tier available in most regions.'),
      ),

      // ---- Image ---------------------------------------------------------
      // Ordered best-first: "Auto" takes the first concrete entry, so the head
      // of this list is what most runs will actually use.
      ProviderEntry(
        id: 'fal-image',
        category: 'image',
        label: 'fal.ai',
        credential: 'fal',
        models: [
          auto,
          const ModelEntry('fal-ai/nano-banana/edit', 'Nano Banana (edit)'),
          const ModelEntry('fal-ai/nano-banana-2/edit', 'Nano Banana 2 (edit)'),
          const ModelEntry('fal-ai/nano-banana-pro/edit', 'Nano Banana Pro (edit)'),
          const ModelEntry('fal-ai/nano-banana', 'Nano Banana'),
          const ModelEntry('fal-ai/flux-2-pro/edit', 'FLUX.2 Pro (edit)'),
          const ModelEntry('fal-ai/flux-2-flex/edit', 'FLUX.2 Flex (edit)'),
          const ModelEntry(
              'bytedance/seedream/v5/lite/edit', 'Seedream 5.0 Lite (edit)'),
          const ModelEntry(
              'bytedance/seedream/v5/pro/edit', 'Seedream 5.0 Pro (edit)'),
          const ModelEntry('openai/gpt-image-2/edit', 'GPT Image 2 (edit)'),
          const ModelEntry(
              'xai/grok-imagine-image/quality/edit', 'Grok Imagine (edit)'),
          const ModelEntry('fal-ai/flux-pro/v1.1-ultra', 'FLUX 1.1 Pro Ultra'),
          const ModelEntry('fal-ai/flux-pro/kontext', 'FLUX.1 Kontext Pro'),
          const ModelEntry('fal-ai/flux/dev', 'FLUX.1 dev'),
          const ModelEntry('fal-ai/flux/schnell', 'FLUX.1 schnell'),
          const ModelEntry(
              'fal-ai/bytedance/seedream/v4/text-to-image', 'Seedream 4.0'),
          const ModelEntry('fal-ai/ideogram/v3', 'Ideogram 3.0'),
          const ModelEntry('fal-ai/recraft/v4/text-to-image', 'Recraft V4'),
          const ModelEntry('fal-ai/recraft/v3/text-to-image', 'Recraft V3'),
          const ModelEntry('fal-ai/qwen-image', 'Qwen Image'),
        ],
        defaultModel: 'auto',
        note: tr('The widest catalogue. Any model id from fal.ai/models also works.'),
      ),

      ProviderEntry(
        id: 'openai-image',
        category: 'image',
        label: 'OpenAI Images',
        credential: 'openai',
        models: [
          auto,
          const ModelEntry('gpt-image-2', 'GPT Image 2'),
          const ModelEntry('gpt-image-1.5', 'GPT Image 1.5'),
          const ModelEntry('gpt-image-1', 'GPT Image 1'),
          const ModelEntry('gpt-image-1-mini', 'GPT Image 1 mini'),
          const ModelEntry('dall-e-3', 'DALL-E 3'),
        ],
        defaultModel: 'auto',
        note: tr('gpt-image models can edit your product photo directly.'),
      ),

      ProviderEntry(
        id: 'replicate-image',
        category: 'image',
        label: 'Replicate',
        credential: 'replicate',
        models: [
          auto,
          const ModelEntry('google/nano-banana-2', 'Nano Banana 2'),
          const ModelEntry('google/nano-banana-pro', 'Nano Banana Pro'),
          const ModelEntry('google/nano-banana', 'Nano Banana'),
          const ModelEntry('openai/gpt-image-2', 'GPT Image 2'),
          const ModelEntry('openai/gpt-image-1.5', 'GPT Image 1.5'),
          const ModelEntry('black-forest-labs/flux-2-pro', 'FLUX.2 Pro'),
          const ModelEntry('black-forest-labs/flux-2-flex', 'FLUX.2 Flex'),
          const ModelEntry('black-forest-labs/flux-2-max', 'FLUX.2 Max'),
          const ModelEntry('bytedance/seedream-4.5', 'Seedream 4.5'),
          const ModelEntry('bytedance/seedream-5-lite', 'Seedream 5 Lite'),
          const ModelEntry('xai/grok-imagine-image', 'Grok Imagine'),
          const ModelEntry('google/imagen-4-ultra', 'Imagen 4 Ultra'),
          const ModelEntry('google/imagen-4-fast', 'Imagen 4 Fast'),
          const ModelEntry('recraft-ai/recraft-v4', 'Recraft V4'),
          const ModelEntry('wan-video/wan-2.7-image', 'Wan 2.7 Image'),
          const ModelEntry(
              'black-forest-labs/flux-1.1-pro-ultra', 'FLUX 1.1 Pro Ultra'),
          const ModelEntry(
              'black-forest-labs/flux-kontext-pro', 'FLUX.1 Kontext Pro'),
          const ModelEntry('black-forest-labs/flux-schnell', 'FLUX.1 schnell'),
          const ModelEntry('bytedance/seedream-4', 'Seedream 4.0'),
          const ModelEntry('google/imagen-4', 'Imagen 4'),
          const ModelEntry('ideogram-ai/ideogram-v3-turbo', 'Ideogram 3.0 Turbo'),
          const ModelEntry('recraft-ai/recraft-v3', 'Recraft V3'),
          const ModelEntry('stability-ai/stable-diffusion-3.5-large',
              'Stable Diffusion 3.5 Large'),
        ],
        defaultModel: 'auto',
        note: tr('Use owner/name, or owner/name:version to pin a version.'),
      ),

      // ---- Enlarging -------------------------------------------------------
      // Its own category rather than another image model, because it is the one
      // generation with no prompt: you hand it a picture from the canvas and
      // get the same picture, bigger. The task underneath is the ordinary fal
      // image task -- these endpoints read `image_url` and ignore the rest.
      ProviderEntry(
        id: 'fal-upscale',
        category: 'upscale',
        label: 'fal.ai',
        credential: 'fal',
        models: const [
          ModelEntry('fal-ai/clarity-upscaler', 'Clarity Upscaler'),
          ModelEntry('fal-ai/aura-sr', 'Aura SR'),
          ModelEntry('fal-ai/esrgan', 'Real-ESRGAN'),
        ],
        defaultModel: 'fal-ai/clarity-upscaler',
        note: tr('Enlarges a picture from the canvas. No prompt needed.'),
      ),

      // ---- Video (image to video) ----------------------------------------
      // Video is almost the whole bill, so the head of this list is the single
      // most expensive default in the app. Kling v3 Standard leads: current
      // generation, and a third of the price of the 2.x Master tier it
      // replaces.
      ProviderEntry(
        id: 'fal-video',
        category: 'video',
        label: 'fal.ai',
        credential: 'fal',
        models: [
          auto,
          // Kling 3.0 Standard stays at the head, and it is a pricing decision
          // rather than a quality one: "Auto" takes the first concrete entry,
          // so whatever sits here is what most runs buy -- and it is the newest
          // generation that fal still bills by the second, which is the only
          // shape the estimate can turn into a figure before you press send.
          // Seedance is billed in token buckets, so it is one click away
          // instead of the default nobody could price.
          const ModelEntry(
              'fal-ai/kling-video/v3/standard/image-to-video', 'Kling 3.0 Standard'),
          const ModelEntry(
              'bytedance/seedance-2.5/image-to-video', 'Seedance 2.5'),
          const ModelEntry(
              'bytedance/seedance-2.0/fast/image-to-video', 'Seedance 2.0 Fast'),
          const ModelEntry(
              'fal-ai/kling-video/v3/pro/image-to-video', 'Kling 3.0 Pro'),
          const ModelEntry('fal-ai/kling-video/v3/turbo/pro/image-to-video',
              'Kling 3.0 Turbo Pro'),
          const ModelEntry(
              'fal-ai/kling-video/v3/4k/image-to-video', 'Kling 3.0 Native 4K'),
          const ModelEntry(
              'fal-ai/kling-video/o3/standard/image-to-video', 'Kling O3 Standard'),
          const ModelEntry(
              'fal-ai/veo3.1/lite/image-to-video', 'Google Veo 3.1 Lite'),
          const ModelEntry(
              'fal-ai/veo3.1/fast/image-to-video', 'Google Veo 3.1 Fast'),
          const ModelEntry('fal-ai/veo3.1/image-to-video', 'Google Veo 3.1'),
          const ModelEntry('wan/v2.6/image-to-video', 'Wan 2.6'),
          const ModelEntry('wan/v2.6/image-to-video/flash', 'Wan 2.6 Flash'),
          const ModelEntry('fal-ai/wan/v2.7/image-to-video', 'Wan 2.7'),
          const ModelEntry(
              'bytedance/seedance-2.0/image-to-video', 'Seedance 2.0'),
          const ModelEntry(
              'fal-ai/minimax/hailuo-2.3-fast/standard/image-to-video',
              'Hailuo 2.3 Fast'),
          const ModelEntry('fal-ai/minimax/hailuo-2.3/standard/image-to-video',
              'Hailuo 2.3 Standard'),
          const ModelEntry(
              'fal-ai/minimax/hailuo-2.3/pro/image-to-video', 'Hailuo 2.3 Pro'),
          const ModelEntry(
              'fal-ai/decart/lucy-5b/image-to-video', 'Decart Lucy 5B'),
          const ModelEntry(
              'fal-ai/kling-video/v2.1/master/image-to-video', 'Kling 2.1 Master'),
          const ModelEntry('fal-ai/bytedance/seedance/v1/pro/image-to-video',
              'Seedance 1.0 Pro'),
          const ModelEntry(
              'fal-ai/minimax/hailuo-02/pro/image-to-video', 'Hailuo 02 Pro'),
          const ModelEntry('fal-ai/minimax/hailuo-02/standard/image-to-video',
              'Hailuo 02 Standard'),
          const ModelEntry(
              'fal-ai/luma-dream-machine/ray-2/image-to-video', 'Luma Ray 2'),
          const ModelEntry('fal-ai/wan/v2.2-a14b/image-to-video', 'Wan 2.2 A14B'),
          const ModelEntry('fal-ai/pika/v2.2/image-to-video', 'Pika 2.2'),
          const ModelEntry('fal-ai/pixverse/v4.5/image-to-video', 'PixVerse 4.5'),
        ],
        defaultModel: 'auto',
        note: tr('Kling, Veo, Seedance, Hailuo, Wan, Runway, Luma - one key for all.'),
      ),

      ProviderEntry(
        id: 'replicate-video',
        category: 'video',
        label: 'Replicate',
        credential: 'replicate',
        models: [
          auto,
          const ModelEntry('kwaivgi/kling-v3-video', 'Kling 3.0'),
          const ModelEntry('kwaivgi/kling-v3-omni-video', 'Kling 3.0 Omni'),
          const ModelEntry('google/veo-3.1-fast', 'Google Veo 3.1 Fast'),
          const ModelEntry('bytedance/seedance-2.0', 'Seedance 2.0'),
          const ModelEntry('wan-video/wan-2.7-i2v', 'Wan 2.7'),
          const ModelEntry('minimax/hailuo-2.3-fast', 'Hailuo 2.3 Fast'),
          const ModelEntry('alibaba/happyhorse-1.1', 'HappyHorse 1.1'),
          const ModelEntry('alibaba/happyhorse-1.0', 'HappyHorse 1.0'),
          const ModelEntry('xai/grok-imagine-video', 'Grok Imagine Video'),
          const ModelEntry('luma/ray-3.2', 'Luma Ray 3.2'),
          const ModelEntry('vidu/q3-pro', 'Vidu Q3 Pro'),
          const ModelEntry('prunaai/p-video', 'Pruna P-Video'),
          const ModelEntry('kwaivgi/kling-v2.1', 'Kling 2.1'),
          const ModelEntry('google/veo-3', 'Google Veo 3'),
          const ModelEntry('bytedance/seedance-1-pro', 'Seedance 1 Pro'),
          const ModelEntry('bytedance/seedance-1-lite', 'Seedance 1 Lite'),
          const ModelEntry('minimax/hailuo-02', 'Hailuo 02'),
          const ModelEntry('wan-video/wan-2.2-i2v-fast', 'Wan 2.2 I2V Fast'),
          const ModelEntry('pixverse/pixverse-v4.5', 'PixVerse 4.5'),
        ],
        defaultModel: 'auto',
        note: tr('Pay per second, no subscription.'),
      ),

      ProviderEntry(
        id: 'openai-video',
        category: 'video',
        label: 'OpenAI (Sora)',
        credential: 'openai',
        models: const [
          ModelEntry('sora-2', 'Sora 2'),
          ModelEntry('sora-2-pro', 'Sora 2 Pro'),
        ],
        defaultModel: 'sora-2',
        note: tr("The opening frame is resized to Sora's format automatically."),
      ),

      // ---- Talking shots ---------------------------------------------------
      // These take the audio as an input, so the clip comes back exactly as
      // long as the line and the mouth actually matches.
      ProviderEntry(
        id: 'fal-avatar',
        category: 'avatar',
        label: 'fal.ai avatars',
        credential: 'fal',
        models: [
          auto,
          const ModelEntry('fal-ai/kling-video/ai-avatar/v2/standard',
              'Kling AI Avatar v2 Standard'),
          const ModelEntry(
              'fal-ai/kling-video/ai-avatar/v2/pro', 'Kling AI Avatar v2 Pro'),
          const ModelEntry('veed/fabric-1.0', 'VEED Fabric 1.0'),
          const ModelEntry('fal-ai/infinitalk', 'InfiniTalk'),
        ],
        defaultModel: 'auto',
        note: tr('Lip-synced talking shots. The clip lasts exactly as long as the line.'),
      ),

      // ---- Voice -----------------------------------------------------------
      ProviderEntry(
        id: 'elevenlabs',
        category: 'voice',
        label: 'ElevenLabs',
        credential: 'elevenlabs',
        models: const [
          ModelEntry('eleven_v3', 'Eleven v3'),
          ModelEntry('eleven_multilingual_v2', 'Multilingual v2'),
          ModelEntry('eleven_turbo_v2_5', 'Turbo v2.5'),
          ModelEntry('eleven_flash_v2_5', 'Flash v2.5'),
        ],
        defaultModel: 'eleven_multilingual_v2',
        note: tr('Best UGC-sounding voices. Load your voice list below.'),
      ),

      ProviderEntry(
        id: 'openai-tts',
        category: 'voice',
        label: 'OpenAI TTS',
        credential: 'openai',
        models: const [
          ModelEntry('gpt-4o-mini-tts', 'GPT-4o mini TTS'),
          ModelEntry('tts-1-hd', 'TTS-1 HD'),
          ModelEntry('tts-1', 'TTS-1'),
        ],
        defaultModel: 'gpt-4o-mini-tts',
        note: tr('Cheap and fast, fixed set of voices.'),
      ),

      ProviderEntry(
        id: 'fal-voice',
        category: 'voice',
        label: 'fal.ai voices',
        credential: 'fal',
        models: const [
          ModelEntry('fal-ai/elevenlabs/tts/eleven-v3', 'ElevenLabs v3'),
          ModelEntry('fal-ai/minimax/speech-02-hd', 'MiniMax Speech 02 HD'),
          ModelEntry('fal-ai/minimax/speech-02-turbo', 'MiniMax Speech 02 Turbo'),
          ModelEntry(
              'fal-ai/elevenlabs/tts/multilingual-v2', 'ElevenLabs Multilingual v2'),
          ModelEntry('fal-ai/elevenlabs/tts/turbo-v2.5', 'ElevenLabs Turbo v2.5'),
          ModelEntry('fal-ai/kokoro/american-english', 'Kokoro (American English)'),
          ModelEntry('fal-ai/chatterbox/text-to-speech', 'Chatterbox'),
        ],
        defaultModel: 'fal-ai/elevenlabs/tts/eleven-v3',
        note: tr('Several voice engines behind the fal key you already have.'),
      ),

      // ---- Captions --------------------------------------------------------
      ProviderEntry(
        id: 'openai-whisper',
        category: 'captions',
        label: 'OpenAI Whisper',
        credential: 'openai',
        models: const [ModelEntry('whisper-1', 'Whisper')],
        defaultModel: 'whisper-1',
        note: tr('Transcribes the generated voice-over into timed subtitles.'),
      ),
    ];
  }

  static bool isAuto(String modelId) => modelId == 'auto';

  /// "auto" is a placeholder, not a model id. This turns it into a real one,
  /// picked from what the shot needs. Returns the id unchanged otherwise.
  String resolveModel(String providerId, String modelId, [int durationSeconds = 0]) {
    if (!isAuto(modelId)) return modelId;

    for (final entry in _entries) {
      if (entry.id != providerId) continue;

      // Models are listed best-first, so the first concrete one is the pick.
      // For a long shot we skip ahead to a family that can do 10 seconds in one
      // go, rather than leaving the pipeline to loop a 5s clip.
      final needsLongClip = entry.category == 'video' && durationSeconds > 7;

      var firstConcrete = '';
      for (final model in entry.models) {
        if (isAuto(model.id)) continue;
        if (firstConcrete.isEmpty) firstConcrete = model.id;
        if (!needsLongClip) return model.id;
        if (model.id.contains('kling') ||
            model.id.contains('hailuo') ||
            model.id.contains('seedance')) {
          return model.id;
        }
      }
      return firstConcrete;
    }
    return '';
  }

  List<ProviderEntry> providers(String category) =>
      [for (final entry in _entries) if (entry.category == category) entry];

  ProviderEntry? provider(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  String credentialFor(String providerId) => provider(providerId)?.credential ?? '';

  String defaultProvider(String category) {
    for (final entry in _entries) {
      if (entry.category == category) return entry.id;
    }
    return '';
  }

  /// Readable name for a model, or the id itself when it came from "Other...".
  String modelLabel(String providerId, String modelId) {
    final entry = provider(providerId);
    if (entry != null) {
      for (final model in entry.models) {
        if (model.id == modelId) return model.label;
      }
    }
    return modelId;
  }

  /// Rebuilt on every call, not cached: a language switch has to change the
  /// notes.
  List<CredentialEntry> credentials() => [
        CredentialEntry(
          id: 'openai',
          label: 'OpenAI',
          envVar: 'OPENAI_API_KEY',
          signupUrl: 'https://platform.openai.com/api-keys',
          note: tr('Scripts, images, Sora video, voice-over and subtitles.'),
        ),
        CredentialEntry(
          id: 'anthropic',
          label: 'Anthropic',
          envVar: 'ANTHROPIC_API_KEY',
          signupUrl: 'https://console.anthropic.com/settings/keys',
          note: tr('Scripts.'),
        ),
        CredentialEntry(
          id: 'gemini',
          label: 'Google Gemini',
          envVar: 'GEMINI_API_KEY',
          signupUrl: 'https://aistudio.google.com/apikey',
          note: tr('Scripts.'),
        ),
        CredentialEntry(
          id: 'fal',
          label: 'fal.ai',
          envVar: 'FAL_KEY',
          signupUrl: 'https://fal.ai/dashboard/keys',
          note: tr('Images, video and voices (Kling, Veo, Seedance, FLUX, MiniMax...).'),
        ),
        CredentialEntry(
          id: 'replicate',
          label: 'Replicate',
          envVar: 'REPLICATE_API_TOKEN',
          signupUrl: 'https://replicate.com/account/api-tokens',
          note: tr('Images and video.'),
        ),
        CredentialEntry(
          id: 'elevenlabs',
          label: 'ElevenLabs',
          envVar: 'ELEVENLABS_API_KEY',
          signupUrl: 'https://elevenlabs.io/app/settings/api-keys',
          note: tr('Voice-over.'),
        ),
      ];
}

/// Task factory. Returns null when the provider id is unknown.
class ProviderFactory {
  ProviderFactory._();

  static ProviderTask? script(String providerId, ScriptRequest request) =>
      switch (providerId) {
        'openai-chat' => OpenAiScriptTask(request),
        'anthropic-messages' => AnthropicScriptTask(request),
        'gemini-generate' => GeminiScriptTask(request),
        _ => null,
      };

  static ProviderTask? image(String providerId, ImageRequest request) =>
      switch (providerId) {
        'openai-image' => OpenAiImageTask(request),
        'fal-image' => FalImageTask(request),
        'replicate-image' => ReplicateImageTask(request),
        // The upscalers take the picture as `image_url` and hand one back the
        // same way an image model does, so they need no task of their own.
        'fal-upscale' => FalImageTask(request),
        _ => null,
      };

  static ProviderTask? video(String providerId, VideoRequest request) =>
      switch (providerId) {
        'fal-video' => FalVideoTask(request),
        'replicate-video' => ReplicateVideoTask(request),
        'openai-video' => SoraVideoTask(request),
        _ => null,
      };

  static ProviderTask? avatar(String providerId, AvatarRequest request) =>
      switch (providerId) {
        'fal-avatar' => FalAvatarTask(request),
        _ => null,
      };

  static ProviderTask? voice(String providerId, VoiceRequest request) =>
      switch (providerId) {
        'elevenlabs' => ElevenLabsVoiceTask(request),
        'openai-tts' => OpenAiVoiceTask(request),
        'fal-voice' => FalVoiceTask(request),
        _ => null,
      };

  static ProviderTask? transcribe(String providerId, TranscribeRequest request) =>
      switch (providerId) {
        'openai-whisper' => WhisperCaptionTask(request),
        _ => null,
      };

  /// Lists the voices available on the user's account (ElevenLabs / OpenAI).
  static ProviderTask? voiceCatalog(String providerId, String apiKey) =>
      switch (providerId) {
        'elevenlabs' => ElevenLabsVoiceListTask(apiKey),
        'openai-tts' => OpenAiVoiceListTask(),
        'fal-voice' => FalVoiceListTask(),
        _ => null,
      };
}
