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
///
/// There used to be a `tier` on here marking the models a provider publishes a
/// free quota for. It is gone, and deliberately: a free quota is a promotion,
/// it is metered in units nothing in this app can see, and the moment it runs
/// out the same model bills like any other. Labelling a model "free" in a menu
/// somebody spends money from is a claim we cannot stand behind on the one
/// screen where being wrong costs them.
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

  /// "text", "image", "video", "avatar", "voice", "captions", "upscale".
  /// What the pipeline asks for. The Models menu groups these into the five
  /// panels below, which is a different cut: subtitles and voice-over are two
  /// categories but one panel, because both are "Audio" to somebody choosing.
  final String category;
  final String label;
  final String credential;
  final List<ModelEntry> models;
  final String defaultModel;
  final String note;
}

/// One shelf of the Models menu.
///
/// Configuration used to be two screens: keys in Settings, shortlists in
/// Models, and nothing said which key unlocked which model. A panel puts the
/// two together -- pick a provider, type its key, tick what you want from it --
/// and the providers are filtered by what they actually do, so nobody has to
/// scroll past a video house looking for somewhere to write a script.
class PanelEntry {
  const PanelEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.categories,
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;

  /// Provider categories that belong on this shelf, in display order.
  ///
  /// More than one is the exception: enlarging is its own category because the
  /// pipeline asks for it separately, but it is bought from the same accounts
  /// as the pictures and belongs on the same shelf as them.
  final List<String> categories;
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
/// provider id into a running task.
///
/// Every entry here calls the provider's own API with the user's own key. There
/// is exactly one exception, and it is deliberate: Kling sells API access in
/// packs starting at several hundred dollars with an expiry date, which is the
/// wrong shape for somebody trying the app out, so Kling -- and only Kling --
/// is reached through fal.ai, which resells it by the second. Nothing else is
/// allowed on that path.
class Registry extends ChangeNotifier {
  Registry() {
    _build();
  }

  /// The shelves of the Models menu, in the order they are drawn.
  ///
  /// Keys come first and are a shelf of their own. They used to be a band
  /// inside every account card, which meant one account that sells on four
  /// shelves had its key field drawn four times -- and setting the app up
  /// meant touring every tab looking for the cards that still had an empty
  /// one. Keys are a thing you do once; picking models is a thing you come
  /// back to. Two jobs, two places.
  static const List<PanelEntry> panels = [
    PanelEntry(
      id: 'keys',
      title: 'API keys',
      subtitle: 'Paste a key for each account you want to buy from. '
          'Everything on the other tabs is switched on by these.',
      icon: 'key-line',
      // No categories: this shelf lists accounts rather than models, and gets
      // its cards from the credential list directly.
      categories: [],
    ),
    PanelEntry(
      id: 'llm',
      title: 'LLM',
      subtitle: 'The writers. Nothing writes your ad unless you ask it to.',
      icon: 'draft-line',
      categories: ['text'],
    ),
    PanelEntry(
      id: 'avatar',
      title: 'Talking actors',
      subtitle: 'A face, a voice track, and a clip exactly as long as the line.',
      icon: 'user-voice-line',
      categories: ['avatar'],
    ),
    PanelEntry(
      id: 'image',
      title: 'Images',
      subtitle: 'Stills, actors, product shots -- and blowing one up.',
      icon: 'image-line',
      categories: ['image', 'upscale'],
    ),
    PanelEntry(
      id: 'video',
      title: 'Video',
      subtitle: 'Animate a still, or shoot from a prompt.',
      icon: 'clapperboard-line',
      categories: ['video'],
    ),
    PanelEntry(
      id: 'audio',
      title: 'Audio',
      subtitle: 'Who reads your script, and the subtitles that follow it.',
      icon: 'volume-up-line',
      categories: ['voice', 'captions'],
    ),
  ];

  List<ProviderEntry> _entries = const [];

  List<ProviderEntry> get entries => _entries;

  /// The descriptions are translated, so the list has to be rebuilt when the
  /// language changes.
  void retranslate() {
    _build();
    notifyListeners();
  }

  void _build() {
    // Nothing here is translated: model names are product names, and the one
    // entry that used to be a phrase -- "Auto - best model for this shot" --
    // is gone. It sat at the top of every menu, said nothing about what would
    // actually be billed, and had to be opened and read past to reach the
    // model you wanted. The head of each list is the default instead, which is
    // what Auto resolved to anyway.
    _entries = <ProviderEntry>[
      // ---- LLM -----------------------------------------------------------
      // Gemini leads because its Flash models are the cheapest writers on the
      // list: the first entry of a category is what a fresh install picks.
      // Move this block down to hand the default back to OpenAI -- anyone who
      // has already chosen keeps their choice either way, since a saved
      // preference wins over this order.
      ProviderEntry(
        id: 'gemini-generate',
        category: 'text',
        label: 'Google Gemini',
        credential: 'gemini',
        models: const [
          ModelEntry('gemini-3.6-flash', 'Gemini 3.6 Flash'),
          ModelEntry('gemini-3.5-flash', 'Gemini 3.5 Flash'),
          ModelEntry('gemini-3.5-flash-lite', 'Gemini 3.5 Flash Lite'),
          ModelEntry('gemini-3.1-flash-lite', 'Gemini 3.1 Flash Lite'),
          ModelEntry('gemini-3.1-pro-preview', 'Gemini 3.1 Pro'),
          ModelEntry('gemini-2.5-pro', 'Gemini 2.5 Pro'),
        ],
        defaultModel: 'gemini-3.5-flash',
        note: tr('The cheapest writers here. Google reads what you send on '
            'this key.'),
      ),

      ProviderEntry(
        id: 'openai-chat',
        category: 'text',
        label: 'OpenAI',
        credential: 'openai',
        models: const [
          ModelEntry('gpt-5.6-terra', 'GPT-5.6 Terra'),
          ModelEntry('gpt-5.6-luna', 'GPT-5.6 Luna'),
          ModelEntry('gpt-5.6-sol', 'GPT-5.6 Sol'),
          ModelEntry('gpt-5.5', 'GPT-5.5'),
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
          ModelEntry('claude-haiku-4-5-20251001', 'Claude Haiku 4.5'),
        ],
        defaultModel: 'claude-sonnet-5',
        note: tr('Strong at short, natural-sounding ad copy.'),
      ),

      ProviderEntry(
        id: 'xai-chat',
        category: 'text',
        label: 'xAI (Grok)',
        credential: 'xai',
        models: const [
          ModelEntry('grok-4.5', 'Grok 4.5'),
          ModelEntry('grok-4.3', 'Grok 4.3'),
        ],
        defaultModel: 'grok-4.5',
        note: tr('One key also covers Grok Imagine for stills and clips.'),
      ),

      ProviderEntry(
        id: 'minimax-chat',
        category: 'text',
        label: 'MiniMax',
        credential: 'minimax',
        models: const [
          ModelEntry('MiniMax-M3', 'MiniMax M3'),
          ModelEntry('MiniMax-M2.7', 'MiniMax M2.7'),
        ],
        defaultModel: 'MiniMax-M3',
        note: tr('Same key as MiniMax video and voice.'),
      ),

      // ---- Talking actors --------------------------------------------------
      // These take the audio as an input, so the clip comes back exactly as
      // long as the line and the mouth actually matches.
      ProviderEntry(
        id: 'heygen-avatar',
        category: 'avatar',
        label: 'HeyGen',
        credential: 'heygen',
        models: const [
          // The engine, not a model id: HeyGen has one endpoint and picks the
          // renderer from `engine.type`. Avatar IV is their default for new
          // integrations and the only one that animates an arbitrary photo, so
          // it leads -- the others need an avatar registered on the account.
          ModelEntry('avatar_iv', 'Avatar IV'),
          ModelEntry('avatar_v', 'Avatar V'),
          ModelEntry('avatar_iii', 'Avatar III (4K)'),
        ],
        defaultModel: 'avatar_iv',
        note: tr('Animates a photo you supply. Avatar V and III need an avatar '
            'registered on your HeyGen account first.'),
      ),

      ProviderEntry(
        id: 'fal-avatar',
        category: 'avatar',
        label: 'Kling Avatar (via fal.ai)',
        credential: 'fal',
        models: const [
          ModelEntry('fal-ai/kling-video/ai-avatar/v2/standard',
              'Kling AI Avatar v2 Standard'),
          ModelEntry(
              'fal-ai/kling-video/ai-avatar/v2/pro', 'Kling AI Avatar v2 Pro'),
        ],
        defaultModel: 'fal-ai/kling-video/ai-avatar/v2/standard',
        note: tr('Kling sells its own API in packs of several hundred dollars, '
            'so it is the one model reached through a reseller.'),
      ),

      // ---- Images ----------------------------------------------------------
      // Ordered best-first: the head of each list is its default, so it is what
      // most runs will actually use.
      //
      // Gemini leads the category for the same reason it leads the writers: it
      // is the only one that draws anything without a funded account.
      ProviderEntry(
        id: 'gemini-image',
        category: 'image',
        label: 'Google Gemini',
        credential: 'gemini',
        models: const [
          ModelEntry('gemini-3.1-flash-image', 'Nano Banana 2'),
          ModelEntry('gemini-3.1-flash-lite-image', 'Nano Banana 2 Lite'),
          ModelEntry('gemini-3-pro-image', 'Nano Banana Pro'),
          ModelEntry('gemini-2.5-flash-image', 'Nano Banana'),
        ],
        defaultModel: 'gemini-3.1-flash-image',
        note: tr('Edits your product photo directly. Every picture carries '
            'an invisible SynthID watermark.'),
      ),

      ProviderEntry(
        id: 'bfl-image',
        category: 'image',
        label: 'Black Forest Labs (FLUX)',
        credential: 'bfl',
        models: const [
          // Up to eight reference images on the API, which is what keeps a
          // product looking like itself across a whole ad.
          ModelEntry('flux-2-pro', 'FLUX.2 [pro]'),
          ModelEntry('flux-2-flex', 'FLUX.2 [flex]'),
          ModelEntry('flux-2-max', 'FLUX.2 [max]'),
          ModelEntry('flux-2-klein-9b', 'FLUX.2 [klein] 9B'),
          ModelEntry('flux-2-klein-4b', 'FLUX.2 [klein] 4B'),
          ModelEntry('flux-kontext-pro', 'FLUX.1 Kontext [pro]'),
        ],
        defaultModel: 'flux-2-pro',
        note: tr('Priced by the megapixel, and the exact cost comes back with '
            'the job rather than being estimated.'),
      ),

      ProviderEntry(
        id: 'bytedance-image',
        category: 'image',
        label: 'BytePlus (Seedream)',
        credential: 'bytedance',
        models: const [
          // No plain "Seedream 5.0": 5.0 ships as Lite and Pro only, and the
          // id that was here answered nothing on ModelArk.
          ModelEntry('seedream-4-5-251128', 'Seedream 4.5'),
          ModelEntry('seedream-5-0-lite-260128', 'Seedream 5.0 Lite'),
          ModelEntry('dola-seedream-5-0-pro-260628', 'Seedream 5.0 Pro'),
          ModelEntry('seededit-3-0-i2i-250628', 'SeedEdit 3.0'),
        ],
        defaultModel: 'seedream-4-5-251128',
        note: tr('Reference images cost nothing to send, so multi-reference '
            'product shots stay cheap.'),
      ),

      ProviderEntry(
        id: 'openai-image',
        category: 'image',
        label: 'OpenAI Images',
        credential: 'openai',
        // One entry, on purpose. GPT Image 1.5 and 1 mini were both older and
        // dearer than the model above them for the same job, and a menu of
        // three where two are never the right answer is a menu that has to be
        // read three times.
        models: const [ModelEntry('gpt-image-2', 'GPT Image 2')],
        defaultModel: 'gpt-image-2',
        note: tr('Edits your product photo directly. Billed per generated '
            'image, by quality.'),
      ),

      ProviderEntry(
        id: 'ideogram-image',
        category: 'image',
        label: 'Ideogram',
        credential: 'ideogram',
        models: const [
          // Ideogram bills by rendering speed rather than by model, and the
          // speed is a separate field on the request, so the two travel here as
          // one id and are split apart again in the task.
          ModelEntry('ideogram-v3:TURBO', 'Ideogram 3.0 Turbo'),
          ModelEntry('ideogram-v3:DEFAULT', 'Ideogram 3.0'),
          ModelEntry('ideogram-v3:QUALITY', 'Ideogram 3.0 Quality'),
          ModelEntry('ideogram-v4:TURBO', 'Ideogram 4.0 Turbo'),
          ModelEntry('ideogram-v4:DEFAULT', 'Ideogram 4.0'),
          ModelEntry('ideogram-v4:QUALITY', 'Ideogram 4.0 Quality'),
        ],
        defaultModel: 'ideogram-v3:TURBO',
        note: tr('The one that gets text on a label right. 3.0 also takes a '
            'character reference.'),
      ),

      ProviderEntry(
        id: 'bria-image',
        category: 'image',
        label: 'Bria',
        credential: 'bria',
        models: const [
          ModelEntry('fibo', 'FIBO'),
          ModelEntry('fibo-lite', 'FIBO Lite'),
        ],
        defaultModel: 'fibo',
        note: tr('Trained on licensed material and sold with IP indemnity.'),
      ),

      // Alibaba Qwen Image is missing on purpose, not by oversight. Its prices,
      // model ids and free quota are all published, but the request path for
      // image generation is not on any page reachable without a Model Studio
      // login -- and the host carries a workspace id, so there is no way to
      // pattern-match it from a neighbouring endpoint either. Adding it needs
      // one line from the console's own API reference: the path that follows
      // https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com. Everything
      // else for it is already in docs/audit-fournisseurs-api.md.

      ProviderEntry(
        id: 'xai-image',
        category: 'image',
        label: 'xAI (Grok Imagine)',
        credential: 'xai',
        models: const [
          ModelEntry('grok-imagine-image-quality', 'Grok Imagine Quality'),
          ModelEntry('grok-imagine-image', 'Grok Imagine'),
        ],
        defaultModel: 'grok-imagine-image-quality',
        note: tr('Two cents an image, and the same key runs Grok video.'),
      ),

      // ---- Enlarging -------------------------------------------------------
      // Its own category rather than another image model, because it is the one
      // generation with no prompt: you hand it a picture from the canvas and
      // get the same picture, bigger.
      ProviderEntry(
        id: 'bria-upscale',
        category: 'upscale',
        label: 'Bria',
        credential: 'bria',
        models: const [
          ModelEntry('increase_resolution', 'Increase Resolution'),
        ],
        defaultModel: 'increase_resolution',
        note: tr('Enlarges a picture from the canvas. No prompt needed.'),
      ),

      ProviderEntry(
        id: 'ideogram-upscale',
        category: 'upscale',
        label: 'Ideogram',
        credential: 'ideogram',
        models: const [ModelEntry('upscale', 'Ideogram Upscale')],
        defaultModel: 'upscale',
        note: tr('Takes an optional prompt to steer what it invents.'),
      ),

      // ---- Video -----------------------------------------------------------
      // Video is almost the whole bill, so the head of this list is the single
      // most expensive default in the app. LTX leads: three cents a second at
      // 720p, billed by the second with no minimum, which is both the cheapest
      // current-generation clip on the list and the only one whose price can be
      // quoted exactly before you press send.
      ProviderEntry(
        id: 'ltx-video',
        category: 'video',
        label: 'LTX (Lightricks)',
        credential: 'ltx',
        models: const [
          ModelEntry('ltx-2-3-fast', 'LTX-2.3 Fast'),
          ModelEntry('ltx-2-3-pro', 'LTX-2.3 Pro'),
          ModelEntry('ltx-2-5-fast', 'LTX-2.5 Fast'),
          ModelEntry('ltx-2-5-pro', 'LTX-2.5 Pro'),
        ],
        defaultModel: 'ltx-2-3-fast',
        note: tr('Per second, no minimum. Audio is generated with the picture.'),
      ),

      ProviderEntry(
        id: 'bytedance-video',
        category: 'video',
        label: 'BytePlus (Seedance)',
        credential: 'bytedance',
        models: const [
          // Seedance 2.5 is the reference model of the list: thirty images,
          // ten clips and ten recordings in one request, addressed from the
          // prompt by handle. Hand it a finished ad and a face and the cuts
          // come back with the face in them.
          ModelEntry('dreamina-seedance-2-0-mini-260615', 'Seedance 2.0 Mini'),
          ModelEntry('dreamina-seedance-2-0-fast-260128', 'Seedance 2.0 Fast'),
          ModelEntry('dreamina-seedance-2-5-260628', 'Seedance 2.5'),
          ModelEntry('dreamina-seedance-2-0-260128', 'Seedance 2.0'),
          ModelEntry('seedance-1-5-pro-251215', 'Seedance 1.5 Pro'),
        ],
        defaultModel: 'dreamina-seedance-2-0-mini-260615',
        note: tr('Billed by output tokens, so the estimate is a range. '
            'Seedance 2.x needs a funded BytePlus account to switch on.'),
      ),

      ProviderEntry(
        id: 'gemini-video',
        category: 'video',
        label: 'Google Veo',
        credential: 'gemini',
        models: const [
          ModelEntry('veo-3.1-fast-generate-preview', 'Veo 3.1 Fast'),
          ModelEntry('veo-3.1-generate-preview', 'Veo 3.1'),
        ],
        defaultModel: 'veo-3.1-fast-generate-preview',
        note: tr('Audio and picture in one pass. Clips are 4, 6 or 8 seconds; '
            '1080p and 4K are 8 seconds only.'),
      ),

      ProviderEntry(
        id: 'minimax-video',
        category: 'video',
        label: 'MiniMax (Hailuo)',
        credential: 'minimax',
        models: const [
          ModelEntry('MiniMax-Hailuo-2.3-Fast', 'Hailuo 2.3 Fast'),
          ModelEntry('MiniMax-Hailuo-2.3', 'Hailuo 2.3'),
          ModelEntry('MiniMax-H3', 'MiniMax H3'),
        ],
        defaultModel: 'MiniMax-Hailuo-2.3-Fast',
        note: tr('H3 takes reference images, clips and recordings together. '
            'The Hailuo models take one opening frame.'),
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

      ProviderEntry(
        id: 'xai-video',
        category: 'video',
        label: 'xAI (Grok Imagine)',
        credential: 'xai',
        models: const [
          ModelEntry('grok-imagine-video', 'Grok Imagine Video'),
          ModelEntry('grok-imagine-video-1.5', 'Grok Imagine Video 1.5'),
        ],
        defaultModel: 'grok-imagine-video',
        note: tr('Five cents a second, and the job tells you what it cost.'),
      ),

      ProviderEntry(
        id: 'luma-video',
        category: 'video',
        label: 'Luma',
        credential: 'luma',
        models: const [
          ModelEntry('ray-flash-2', 'Ray Flash 2'),
          ModelEntry('ray-2', 'Ray 2'),
        ],
        defaultModel: 'ray-flash-2',
        note: tr('Takes a closing frame as well as an opening one, and can '
            'carry on from a clip it made earlier.'),
      ),

      ProviderEntry(
        id: 'fal-video',
        category: 'video',
        label: 'Kling (via fal.ai)',
        credential: 'fal',
        models: const [
          ModelEntry(
              'fal-ai/kling-video/v3/standard/image-to-video', 'Kling 3.0 Standard'),
          ModelEntry(
              'fal-ai/kling-video/v3/pro/image-to-video', 'Kling 3.0 Pro'),
          ModelEntry(
              'fal-ai/kling-video/v3/4k/image-to-video', 'Kling 3.0 Native 4K'),
          ModelEntry(
              'fal-ai/kling-video/o3/standard/image-to-video', 'Kling O3 Standard'),
        ],
        defaultModel: 'fal-ai/kling-video/v3/standard/image-to-video',
        note: tr("Kling's own API is sold in packs of several hundred dollars "
            'with an expiry date, so this is the one model bought through a '
            'reseller, by the second.'),
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
          ModelEntry('eleven_flash_v2_5', 'Flash v2.5'),
        ],
        defaultModel: 'eleven_multilingual_v2',
        note: tr('Best UGC-sounding voices. Load your voice list below.'),
      ),

      ProviderEntry(
        id: 'minimax-tts',
        category: 'voice',
        label: 'MiniMax Speech',
        credential: 'minimax',
        models: const [
          ModelEntry('speech-2.8-hd', 'Speech 2.8 HD'),
          ModelEntry('speech-2.8-turbo', 'Speech 2.8 Turbo'),
        ],
        defaultModel: 'speech-2.8-hd',
        note: tr('Emotion and speed are per-request, not baked into the voice.'),
      ),

      ProviderEntry(
        id: 'gemini-tts',
        category: 'voice',
        label: 'Google Gemini TTS',
        credential: 'gemini',
        models: const [
          ModelEntry('gemini-2.5-flash-preview-tts', 'Gemini 2.5 Flash TTS'),
          ModelEntry('gemini-2.5-pro-preview-tts', 'Gemini 2.5 Pro TTS'),
        ],
        defaultModel: 'gemini-2.5-flash-preview-tts',
        note: tr('On the same key as the writer and the images.'),
      ),

      ProviderEntry(
        id: 'openai-tts',
        category: 'voice',
        label: 'OpenAI TTS',
        credential: 'openai',
        models: const [
          ModelEntry('gpt-4o-mini-tts', 'GPT-4o mini TTS'),
          ModelEntry('tts-1-hd', 'TTS-1 HD'),
        ],
        defaultModel: 'gpt-4o-mini-tts',
        note: tr('Cheap and fast, fixed set of voices.'),
      ),

      // ---- Captions --------------------------------------------------------
      // Groq serves the same Whisper weights as OpenAI for a fraction of the
      // price, which makes subtitles the cheapest step of a run.
      ProviderEntry(
        id: 'groq-whisper',
        category: 'captions',
        label: 'Groq Whisper',
        credential: 'groq',
        models: const [
          ModelEntry('whisper-large-v3-turbo', 'Whisper Large v3 Turbo'),
          ModelEntry('whisper-large-v3', 'Whisper Large v3'),
        ],
        defaultModel: 'whisper-large-v3-turbo',
        note: tr('Turbo is faster, v3 is a little more accurate.'),
      ),

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

  /// A saved preference left over from the builds that offered "Auto".
  ///
  /// It is no longer in any menu, but it is in plenty of settings.json files,
  /// and handing "auto" to a provider as a model id is a rejected request with
  /// no obvious cause. [resolveModel] is what turns it back into something
  /// real; this is only how that path recognises it.
  static bool isAuto(String modelId) => modelId == 'auto';

  /// The model id to actually send.
  ///
  /// Everything the menus offer is already concrete, so this is a pass-through
  /// for anything chosen today. The one thing it still does is rescue an
  /// install whose preferences say "auto": that becomes the head of the
  /// provider's list, which is what the old placeholder resolved to anyway.
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
        // Veo tops out at eight seconds and Sora at twelve; the rest of the
        // list runs to fifteen or beyond, so a long shot skips past Veo.
        if (!model.id.startsWith('veo-')) return model.id;
      }
      return firstConcrete;
    }
    return '';
  }

  List<ProviderEntry> providers(String category) =>
      [for (final entry in _entries) if (entry.category == category) entry];

  /// Everything on one shelf of the Models menu, categories in their declared
  /// order.
  List<ProviderEntry> providersForPanel(String panelId) {
    for (final panel in panels) {
      if (panel.id != panelId) continue;
      return [
        for (final category in panel.categories) ...providers(category),
      ];
    }
    return const [];
  }

  /// The keys a shelf needs, each listed once even when two providers on it
  /// share one account.
  List<CredentialEntry> credentialsForPanel(String panelId) {
    final wanted = <String>{
      for (final entry in providersForPanel(panelId))
        if (entry.credential.isNotEmpty) entry.credential,
    };
    return [
      for (final credential in credentials())
        if (wanted.contains(credential.id)) credential,
    ];
  }

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

  /// A saved provider choice, or the category's default when that choice is no
  /// longer in the catalogue.
  ///
  /// It has to be asked rather than assumed: an install that had Replicate
  /// picked for its stills still has `imageProvider = "replicate-image"` in its
  /// preferences, and handing that to the factory returns null -- which the
  /// pipeline can only report as a failure with no obvious cause. Falling back
  /// is the difference between "your old choice is gone, here is the new
  /// default" and an ad that will not render and will not say why.
  String providerOrDefault(String category, String savedId) {
    if (savedId.isNotEmpty) {
      for (final entry in _entries) {
        if (entry.id == savedId && entry.category == category) return savedId;
      }
    }
    return defaultProvider(category);
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
          note: tr('Scripts, images, Sora video, voice-over and subtitles. '
              'Credits from \$5.'),
        ),
        CredentialEntry(
          id: 'gemini',
          label: 'Google Gemini',
          envVar: 'GEMINI_API_KEY',
          signupUrl: 'https://aistudio.google.com/apikey',
          note: tr('Scripts, images, Veo video and voice-over.'),
        ),
        CredentialEntry(
          id: 'anthropic',
          label: 'Anthropic',
          envVar: 'ANTHROPIC_API_KEY',
          signupUrl: 'https://console.anthropic.com/settings/keys',
          note: tr('Scripts.'),
        ),
        CredentialEntry(
          id: 'xai',
          label: 'xAI',
          envVar: 'XAI_API_KEY',
          signupUrl: 'https://console.x.ai/',
          note: tr('Scripts, stills and clips on one prepaid balance.'),
        ),
        CredentialEntry(
          id: 'minimax',
          label: 'MiniMax',
          envVar: 'MINIMAX_API_KEY',
          signupUrl:
              'https://platform.minimax.io/user-center/basic-information/interface-key',
          note: tr('Video, voice-over and scripts. Pay as you go.'),
        ),
        CredentialEntry(
          id: 'ltx',
          label: 'LTX (Lightricks)',
          envVar: 'LTXV_API_KEY',
          signupUrl: 'https://console.ltx.io/',
          note: tr('Video, billed by the second with no minimum.'),
        ),
        CredentialEntry(
          id: 'bytedance',
          label: 'BytePlus ModelArk',
          envVar: 'ARK_API_KEY',
          signupUrl: 'https://console.byteplus.com/ark',
          note: tr('Seedance video and Seedream images. Seedance 2.x needs a '
              'funded balance before it can be switched on.'),
        ),
        CredentialEntry(
          id: 'bfl',
          label: 'Black Forest Labs',
          envVar: 'BFL_API_KEY',
          signupUrl: 'https://dashboard.bfl.ai/',
          note: tr('FLUX images. Top up any amount; one credit is one cent.'),
        ),
        CredentialEntry(
          id: 'heygen',
          label: 'HeyGen',
          envVar: 'HEYGEN_API_KEY',
          signupUrl: 'https://app.heygen.com/settings?nav=API',
          note: tr('Talking actors. Pay as you go from a USD balance.'),
        ),
        CredentialEntry(
          id: 'elevenlabs',
          label: 'ElevenLabs',
          envVar: 'ELEVENLABS_API_KEY',
          signupUrl: 'https://elevenlabs.io/app/settings/api-keys',
          note: tr('Voice-over.'),
        ),
        CredentialEntry(
          id: 'luma',
          label: 'Luma',
          envVar: 'LUMAAI_API_KEY',
          signupUrl: 'https://platform.lumalabs.ai/',
          note: tr('Video, with a closing frame and clip-to-clip continuation.'),
        ),
        // The account notes answer one question -- what does this key pay for,
        // and how is it billed -- and stop there. What a model is good at is
        // the model's own note, a few lines further down the same card, and
        // saying it twice is how a card ends up with two grey paragraphs that
        // disagree slightly.
        CredentialEntry(
          id: 'ideogram',
          label: 'Ideogram',
          envVar: 'IDEOGRAM_API_KEY',
          signupUrl: 'https://ideogram.ai/manage-api',
          note: tr('Images and the enlarger, billed per picture.'),
        ),
        CredentialEntry(
          id: 'bria',
          label: 'Bria',
          envVar: 'BRIA_API_TOKEN',
          signupUrl: 'https://platform.bria.ai/',
          note: tr('Images and the enlarger, billed per picture.'),
        ),
        CredentialEntry(
          id: 'groq',
          label: 'Groq',
          envVar: 'GROQ_API_KEY',
          signupUrl: 'https://console.groq.com/keys',
          note: tr('Subtitles, billed by the minute of audio.'),
        ),
        CredentialEntry(
          id: 'fal',
          // Named for what it buys rather than for who sells it. The account is
          // a fal one, but every model behind it is Kling, and a card headed
          // "fal.ai" in the middle of a page of first-party providers reads as
          // an aggregator that got left in.
          label: 'Kling (via fal.ai)',
          envVar: 'FAL_KEY',
          signupUrl: 'https://fal.ai/dashboard/keys',
          note: tr('Kling only. Everything else calls its provider directly; '
              "Kling's own API is sold in packs of several hundred dollars, so "
              'it is bought by the second here instead.'),
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
        // Both speak the OpenAI wire format on their own host, so the OpenAI
        // task drives them with nothing but a different base url.
        'xai-chat' =>
          OpenAiScriptTask(request, host: 'https://api.x.ai/v1', vendor: 'xAI'),
        'minimax-chat' => OpenAiScriptTask(request,
            host: 'https://api.minimax.io/v1', vendor: 'MiniMax'),
        _ => null,
      };

  /// The same five writers, asked one free-form question. Used by the prompt
  /// doctor; nothing here answers in the shot-list shape.
  static ProviderTask? text(String providerId, TextRequest request) =>
      switch (providerId) {
        'openai-chat' => OpenAiTextTask(request),
        'anthropic-messages' => AnthropicTextTask(request),
        'gemini-generate' => GeminiTextTask(request),
        'xai-chat' =>
          OpenAiTextTask(request, host: 'https://api.x.ai/v1', vendor: 'xAI'),
        'minimax-chat' => OpenAiTextTask(request,
            host: 'https://api.minimax.io/v1', vendor: 'MiniMax'),
        _ => null,
      };

  static ProviderTask? image(String providerId, ImageRequest request) =>
      switch (providerId) {
        'gemini-image' => GeminiImageTask(request),
        'openai-image' => OpenAiImageTask(request),
        'bfl-image' => BflImageTask(request),
        'bytedance-image' => SeedreamImageTask(request),
        'ideogram-image' => IdeogramImageTask(request),
        'bria-image' => BriaImageTask(request),
        'xai-image' => XaiImageTask(request),
        // The enlargers take the picture and hand one back the same way an
        // image model does, so they need no task of their own.
        'bria-upscale' => BriaImageTask(request),
        'ideogram-upscale' => IdeogramImageTask(request),
        _ => null,
      };

  static ProviderTask? video(String providerId, VideoRequest request) =>
      switch (providerId) {
        'ltx-video' => LtxVideoTask(request),
        'bytedance-video' => SeedanceVideoTask(request),
        'gemini-video' => VeoVideoTask(request),
        'minimax-video' => MiniMaxVideoTask(request),
        'openai-video' => SoraVideoTask(request),
        'xai-video' => XaiVideoTask(request),
        'luma-video' => LumaVideoTask(request),
        'fal-video' => FalVideoTask(request),
        _ => null,
      };

  static ProviderTask? avatar(String providerId, AvatarRequest request) =>
      switch (providerId) {
        'heygen-avatar' => HeyGenAvatarTask(request),
        'fal-avatar' => FalAvatarTask(request),
        _ => null,
      };

  static ProviderTask? voice(String providerId, VoiceRequest request) =>
      switch (providerId) {
        'elevenlabs' => ElevenLabsVoiceTask(request),
        'openai-tts' => OpenAiVoiceTask(request),
        'minimax-tts' => MiniMaxVoiceTask(request),
        'gemini-tts' => GeminiVoiceTask(request),
        _ => null,
      };

  static ProviderTask? transcribe(String providerId, TranscribeRequest request) =>
      switch (providerId) {
        'groq-whisper' => GroqCaptionTask(request),
        'openai-whisper' => WhisperCaptionTask(request),
        _ => null,
      };

  /// Lists the voices available on the user's account.
  static ProviderTask? voiceCatalog(String providerId, String apiKey) =>
      switch (providerId) {
        'elevenlabs' => ElevenLabsVoiceListTask(apiKey),
        'openai-tts' => OpenAiVoiceListTask(),
        'minimax-tts' => MiniMaxVoiceListTask(),
        'gemini-tts' => GeminiVoiceListTask(),
        _ => null,
      };
}
