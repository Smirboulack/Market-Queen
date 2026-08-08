#include "Registry.h"

#include "ImageProviders.h"
#include "ProviderTask.h"
#include "TextProviders.h"
#include "VideoProviders.h"
#include "VoiceProviders.h"

#include <QVariantMap>

namespace {

// Shorthand for the catalogue below.
Registry::Model M(const char *id, const char *label)
{
    return {QString::fromLatin1(id), QString::fromLatin1(label)};
}

QVariantList modelsToList(const QList<Registry::Model> &models)
{
    QVariantList list;
    for (const Registry::Model &model : models) {
        // {label, value} is what the QML pickers expect.
        list.append(QVariantMap{{QStringLiteral("value"), model.id},
                                {QStringLiteral("label"), model.label}});
    }
    return list;
}

QVariantMap toMap(const Registry::Entry &e)
{
    return {
        {QStringLiteral("id"), e.id},
        {QStringLiteral("category"), e.category},
        {QStringLiteral("label"), e.label},
        {QStringLiteral("credential"), e.credential},
        {QStringLiteral("models"), modelsToList(e.models)},
        {QStringLiteral("defaultModel"), e.defaultModel},
        {QStringLiteral("note"), e.note},
    };
}

} // namespace

Registry::Registry(QObject *parent)
    : QObject(parent)
{
    buildEntries();
}

void Registry::retranslate()
{
    buildEntries();
    emit retranslated();
}

void Registry::buildEntries()
{
    // Only the "Auto" entry is translated: model names are product names.
    const Model autoModel{QStringLiteral("auto"), tr("Auto - best model for this shot")};

    m_entries = {
        // ---- Script writers -------------------------------------------------
        {QStringLiteral("openai-chat"), QStringLiteral("text"), QStringLiteral("OpenAI"),
         QStringLiteral("openai"),
         {M("gpt-5.6-terra", "GPT-5.6 Terra"), M("gpt-5.6-sol", "GPT-5.6 Sol"),
          M("gpt-5.6-luna", "GPT-5.6 Luna"), M("gpt-5.5", "GPT-5.5"), M("gpt-5.4", "GPT-5.4"),
          M("gpt-5.2", "GPT-5.2"), M("gpt-5.1", "GPT-5.1"), M("gpt-5", "GPT-5"),
          M("gpt-5-mini", "GPT-5 mini"), M("gpt-5-nano", "GPT-5 nano"),
          M("gpt-4.1", "GPT-4.1"), M("gpt-4o", "GPT-4o"), M("gpt-4o-mini", "GPT-4o mini")},
         QStringLiteral("gpt-5.6-terra"),
         tr("Reads the product photo when the model supports vision.")},

        {QStringLiteral("anthropic-messages"), QStringLiteral("text"),
         QStringLiteral("Anthropic (Claude)"), QStringLiteral("anthropic"),
         {M("claude-sonnet-5", "Claude Sonnet 5"), M("claude-opus-5", "Claude Opus 5"),
          M("claude-fable-5", "Claude Fable 5"), M("claude-opus-4-8", "Claude Opus 4.8"),
          M("claude-haiku-4-5-20251001", "Claude Haiku 4.5")},
         QStringLiteral("claude-sonnet-5"),
         tr("Strong at short, natural-sounding ad copy.")},

        {QStringLiteral("gemini-generate"), QStringLiteral("text"),
         QStringLiteral("Google Gemini"), QStringLiteral("gemini"),
         {M("gemini-3.5-flash", "Gemini 3.5 Flash"), M("gemini-3.6-flash", "Gemini 3.6 Flash"),
          M("gemini-3.5-flash-lite", "Gemini 3.5 Flash Lite"),
          M("gemini-3.1-pro-preview", "Gemini 3.1 Pro"),
          M("gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite"),
          M("gemini-2.5-pro", "Gemini 2.5 Pro"), M("gemini-2.5-flash", "Gemini 2.5 Flash"),
          M("gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite"),
          M("gemini-2.0-flash", "Gemini 2.0 Flash")},
         QStringLiteral("gemini-3.5-flash"),
         tr("Free tier available in most regions.")},

        // ---- Image ----------------------------------------------------------
        // Ordered best-first: "Auto" takes the first concrete entry, so the head
        // of this list is what most runs will actually use.
        {QStringLiteral("fal-image"), QStringLiteral("image"), QStringLiteral("fal.ai"),
         QStringLiteral("fal"),
         {autoModel,
          M("fal-ai/nano-banana/edit", "Nano Banana (edit)"),
          M("fal-ai/nano-banana-2/edit", "Nano Banana 2 (edit)"),
          M("fal-ai/nano-banana-pro/edit", "Nano Banana Pro (edit)"),
          M("fal-ai/nano-banana", "Nano Banana"),
          M("fal-ai/flux-2-pro/edit", "FLUX.2 Pro (edit)"),
          M("fal-ai/flux-2-flex/edit", "FLUX.2 Flex (edit)"),
          M("fal-ai/bytedance/seedream/v5/lite/edit", "Seedream 5.0 Lite (edit)"),
          M("openai/gpt-image-2/edit", "GPT Image 2 (edit)"),
          M("xai/grok-imagine-image/quality/edit", "Grok Imagine (edit)"),
          M("fal-ai/flux-pro/v1.1-ultra", "FLUX 1.1 Pro Ultra"),
          M("fal-ai/flux-pro/kontext", "FLUX.1 Kontext Pro"),
          M("fal-ai/flux/dev", "FLUX.1 dev"),
          M("fal-ai/flux/schnell", "FLUX.1 schnell"),
          M("fal-ai/bytedance/seedream/v4/text-to-image", "Seedream 4.0"),
          M("fal-ai/imagen4/preview", "Imagen 4"),
          M("fal-ai/ideogram/v3", "Ideogram 3.0"),
          M("fal-ai/recraft-v3", "Recraft V3"),
          M("fal-ai/qwen-image", "Qwen Image")},
         QStringLiteral("auto"),
         tr("The widest catalogue. Any model id from fal.ai/models also works.")},

        {QStringLiteral("openai-image"), QStringLiteral("image"), QStringLiteral("OpenAI Images"),
         QStringLiteral("openai"),
         {autoModel, M("gpt-image-2", "GPT Image 2"), M("gpt-image-1.5", "GPT Image 1.5"),
          M("gpt-image-1", "GPT Image 1"), M("gpt-image-1-mini", "GPT Image 1 mini"),
          M("dall-e-3", "DALL-E 3")},
         QStringLiteral("auto"),
         tr("gpt-image models can edit your product photo directly.")},

        {QStringLiteral("replicate-image"), QStringLiteral("image"), QStringLiteral("Replicate"),
         QStringLiteral("replicate"),
         {autoModel,
          M("google/nano-banana-2", "Nano Banana 2"),
          M("google/nano-banana-pro", "Nano Banana Pro"),
          M("google/nano-banana", "Nano Banana"),
          M("openai/gpt-image-2", "GPT Image 2"),
          M("openai/gpt-image-1.5", "GPT Image 1.5"),
          M("black-forest-labs/flux-2-pro", "FLUX.2 Pro"),
          M("black-forest-labs/flux-2-flex", "FLUX.2 Flex"),
          M("black-forest-labs/flux-2-max", "FLUX.2 Max"),
          M("bytedance/seedream-4.5", "Seedream 4.5"),
          M("bytedance/seedream-5-lite", "Seedream 5 Lite"),
          M("xai/grok-imagine-image", "Grok Imagine"),
          M("google/imagen-4-ultra", "Imagen 4 Ultra"),
          M("google/imagen-4-fast", "Imagen 4 Fast"),
          M("recraft-ai/recraft-v4", "Recraft V4"),
          M("wan-video/wan-2.7-image", "Wan 2.7 Image"),
          M("black-forest-labs/flux-1.1-pro-ultra", "FLUX 1.1 Pro Ultra"),
          M("black-forest-labs/flux-kontext-pro", "FLUX.1 Kontext Pro"),
          M("black-forest-labs/flux-schnell", "FLUX.1 schnell"),
          M("bytedance/seedream-4", "Seedream 4.0"),
          M("google/imagen-4", "Imagen 4"),
          M("ideogram-ai/ideogram-v3-turbo", "Ideogram 3.0 Turbo"),
          M("recraft-ai/recraft-v3", "Recraft V3"),
          M("stability-ai/stable-diffusion-3.5-large", "Stable Diffusion 3.5 Large")},
         QStringLiteral("auto"),
         tr("Use owner/name, or owner/name:version to pin a version.")},

        // ---- Video (image to video) ----------------------------------------
        // Video is almost the whole bill, so the head of this list is the single
        // most expensive default in the app. Kling v3 Standard leads: current
        // generation, and a third of the price of the 2.x Master tier it
        // replaces.
        {QStringLiteral("fal-video"), QStringLiteral("video"), QStringLiteral("fal.ai"),
         QStringLiteral("fal"),
         {autoModel,
          M("fal-ai/kling-video/v3/standard/image-to-video", "Kling 3.0 Standard"),
          M("fal-ai/kling-video/v3/pro/image-to-video", "Kling 3.0 Pro"),
          M("fal-ai/kling-video/v3/turbo/pro/image-to-video", "Kling 3.0 Turbo Pro"),
          M("fal-ai/kling-video/v3/4k/image-to-video", "Kling 3.0 Native 4K"),
          M("fal-ai/kling-video/o3/standard/image-to-video", "Kling O3 Standard"),
          M("fal-ai/veo3.1/lite/image-to-video", "Google Veo 3.1 Lite"),
          M("fal-ai/veo3.1/fast/image-to-video", "Google Veo 3.1 Fast"),
          M("fal-ai/veo3.1/image-to-video", "Google Veo 3.1"),
          M("wan/v2.6/image-to-video", "Wan 2.6"),
          M("wan/v2.6/image-to-video/flash", "Wan 2.6 Flash"),
          M("fal-ai/wan/v2.7/image-to-video", "Wan 2.7"),
          M("bytedance/seedance-2.0/image-to-video", "Seedance 2.0"),
          M("fal-ai/minimax/hailuo-2.3-fast/standard/image-to-video", "Hailuo 2.3 Fast"),
          M("fal-ai/minimax/hailuo-2.3/standard/image-to-video", "Hailuo 2.3 Standard"),
          M("fal-ai/minimax/hailuo-2.3/pro/image-to-video", "Hailuo 2.3 Pro"),
          M("fal-ai/decart/lucy-5b/image-to-video", "Decart Lucy 5B"),
          M("fal-ai/kling-video/v2.1/master/image-to-video", "Kling 2.1 Master"),
          M("fal-ai/veo3/image-to-video", "Google Veo 3"),
          M("fal-ai/bytedance/seedance/v1/pro/image-to-video", "Seedance 1.0 Pro"),
          M("fal-ai/bytedance/seedance/v1/lite/image-to-video", "Seedance 1.0 Lite"),
          M("fal-ai/minimax/hailuo-02/pro/image-to-video", "Hailuo 02 Pro"),
          M("fal-ai/minimax/hailuo-02/standard/image-to-video", "Hailuo 02 Standard"),
          M("fal-ai/runway-gen3/turbo/image-to-video", "Runway Gen-3 Turbo"),
          M("fal-ai/luma-dream-machine/ray-2/image-to-video", "Luma Ray 2"),
          M("fal-ai/wan/v2.2-a14b/image-to-video", "Wan 2.2 A14B"),
          M("fal-ai/pika/v2.2/image-to-video", "Pika 2.2"),
          M("fal-ai/pixverse/v4.5/image-to-video", "PixVerse 4.5")},
         QStringLiteral("auto"),
         tr("Kling, Veo, Seedance, Hailuo, Wan, Runway, Luma - one key for all.")},

        {QStringLiteral("replicate-video"), QStringLiteral("video"), QStringLiteral("Replicate"),
         QStringLiteral("replicate"),
         {autoModel,
          M("kwaivgi/kling-v3-video", "Kling 3.0"),
          M("kwaivgi/kling-v3-omni-video", "Kling 3.0 Omni"),
          M("google/veo-3.1-fast", "Google Veo 3.1 Fast"),
          M("bytedance/seedance-2.0", "Seedance 2.0"),
          M("wan-video/wan-2.7-i2v", "Wan 2.7"),
          M("minimax/hailuo-2.3-fast", "Hailuo 2.3 Fast"),
          M("alibaba/happyhorse-1.1", "HappyHorse 1.1"),
          M("alibaba/happyhorse-1.0", "HappyHorse 1.0"),
          M("xai/grok-imagine-video", "Grok Imagine Video"),
          M("luma/ray-3.2", "Luma Ray 3.2"),
          M("vidu/q3-pro", "Vidu Q3 Pro"),
          M("prunaai/p-video", "Pruna P-Video"),
          M("kwaivgi/kling-v2.1", "Kling 2.1"),
          M("google/veo-3", "Google Veo 3"),
          M("bytedance/seedance-1-pro", "Seedance 1 Pro"),
          M("bytedance/seedance-1-lite", "Seedance 1 Lite"),
          M("minimax/hailuo-02", "Hailuo 02"),
          M("wan-video/wan-2.2-i2v-fast", "Wan 2.2 I2V Fast"),
          M("pixverse/pixverse-v4.5", "PixVerse 4.5")},
         QStringLiteral("auto"),
         tr("Pay per second, no subscription.")},

        {QStringLiteral("openai-video"), QStringLiteral("video"), QStringLiteral("OpenAI (Sora)"),
         QStringLiteral("openai"),
         {M("sora-2", "Sora 2"), M("sora-2-pro", "Sora 2 Pro")},
         QStringLiteral("sora-2"),
         tr("The opening frame is resized to Sora's format automatically.")},

        // ---- Voice ----------------------------------------------------------
        {QStringLiteral("elevenlabs"), QStringLiteral("voice"), QStringLiteral("ElevenLabs"),
         QStringLiteral("elevenlabs"),
         {M("eleven_v3", "Eleven v3"), M("eleven_multilingual_v2", "Multilingual v2"),
          M("eleven_turbo_v2_5", "Turbo v2.5"), M("eleven_flash_v2_5", "Flash v2.5")},
         QStringLiteral("eleven_multilingual_v2"),
         tr("Best UGC-sounding voices. Load your voice list below.")},

        {QStringLiteral("openai-tts"), QStringLiteral("voice"), QStringLiteral("OpenAI TTS"),
         QStringLiteral("openai"),
         {M("gpt-4o-mini-tts", "GPT-4o mini TTS"), M("tts-1-hd", "TTS-1 HD"), M("tts-1", "TTS-1")},
         QStringLiteral("gpt-4o-mini-tts"),
         tr("Cheap and fast, fixed set of voices.")},

        {QStringLiteral("fal-voice"), QStringLiteral("voice"), QStringLiteral("fal.ai voices"),
         QStringLiteral("fal"),
         {M("fal-ai/elevenlabs/tts/eleven-v3", "ElevenLabs v3"),
          M("fal-ai/minimax/speech-02-hd", "MiniMax Speech 02 HD"),
          M("fal-ai/minimax/speech-02-turbo", "MiniMax Speech 02 Turbo"),
          M("fal-ai/elevenlabs/tts/multilingual-v2", "ElevenLabs Multilingual v2"),
          M("fal-ai/elevenlabs/tts/turbo-v2.5", "ElevenLabs Turbo v2.5"),
          M("fal-ai/kokoro/american-english", "Kokoro (American English)"),
          M("fal-ai/chatterbox/text-to-speech", "Chatterbox")},
         QStringLiteral("fal-ai/elevenlabs/tts/eleven-v3"),
         tr("Several voice engines behind the fal key you already have.")},

        // ---- Captions -------------------------------------------------------
        {QStringLiteral("openai-whisper"), QStringLiteral("captions"),
         QStringLiteral("OpenAI Whisper"), QStringLiteral("openai"),
         {M("whisper-1", "Whisper")}, QStringLiteral("whisper-1"),
         tr("Transcribes the generated voice-over into timed subtitles.")},
    };
}

QString Registry::resolveModel(const QString &providerId, const QString &modelId,
                               int durationSeconds) const
{
    if (!isAuto(modelId))
        return modelId;

    for (const Entry &entry : m_entries) {
        if (entry.id != providerId)
            continue;

        // Models are listed best-first, so the first concrete one is the pick.
        // For a long shot we skip ahead to a family that can do 10 seconds in
        // one go, rather than leaving the pipeline to loop a 5s clip.
        const bool needsLongClip = entry.category == QLatin1String("video")
            && durationSeconds > 7;

        QString firstConcrete;
        for (const Model &model : entry.models) {
            if (isAuto(model.id))
                continue;
            if (firstConcrete.isEmpty())
                firstConcrete = model.id;
            if (!needsLongClip)
                return model.id;
            if (model.id.contains(QLatin1String("kling"))
                || model.id.contains(QLatin1String("hailuo"))
                || model.id.contains(QLatin1String("seedance"))) {
                return model.id;
            }
        }
        return firstConcrete;
    }
    return {};
}

QVariantList Registry::providers(const QString &category) const
{
    QVariantList list;
    for (const Entry &e : m_entries) {
        if (e.category == category)
            list.append(toMap(e));
    }
    return list;
}

QVariantMap Registry::provider(const QString &id) const
{
    for (const Entry &e : m_entries) {
        if (e.id == id)
            return toMap(e);
    }
    return {};
}

QString Registry::credentialFor(const QString &providerId) const
{
    for (const Entry &e : m_entries) {
        if (e.id == providerId)
            return e.credential;
    }
    return {};
}

QString Registry::modelLabel(const QString &providerId, const QString &modelId) const
{
    for (const Entry &e : m_entries) {
        if (e.id != providerId)
            continue;
        for (const Model &model : e.models) {
            if (model.id == modelId)
                return model.label;
        }
        break;
    }
    return modelId;
}

QString Registry::defaultProvider(const QString &category) const
{
    for (const Entry &e : m_entries) {
        if (e.category == category)
            return e.id;
    }
    return {};
}

QVariantList Registry::credentials() const
{
    struct Credential {
        const char *id;
        const char *label;
        const char *envVar;
        const char *signupUrl;
    };

    static const Credential list[] = {
        {"openai", "OpenAI", "OPENAI_API_KEY", "https://platform.openai.com/api-keys"},
        {"anthropic", "Anthropic", "ANTHROPIC_API_KEY",
         "https://console.anthropic.com/settings/keys"},
        {"gemini", "Google Gemini", "GEMINI_API_KEY", "https://aistudio.google.com/apikey"},
        {"fal", "fal.ai", "FAL_KEY", "https://fal.ai/dashboard/keys"},
        {"replicate", "Replicate", "REPLICATE_API_TOKEN",
         "https://replicate.com/account/api-tokens"},
        {"elevenlabs", "ElevenLabs", "ELEVENLABS_API_KEY",
         "https://elevenlabs.io/app/settings/api-keys"},
    };

    // Rebuilt on every call, not static: a language switch has to change these.
    const QHash<QByteArray, QString> notes = {
        {"openai", tr("Scripts, images, Sora video, voice-over and subtitles.")},
        {"anthropic", tr("Scripts.")},
        {"gemini", tr("Scripts.")},
        {"fal", tr("Images, video and voices (Kling, Veo, Seedance, FLUX, MiniMax...).")},
        {"replicate", tr("Images and video.")},
        {"elevenlabs", tr("Voice-over.")},
    };

    QVariantList out;
    for (const Credential &c : list) {
        out.append(QVariantMap{
            {QStringLiteral("id"), QString::fromLatin1(c.id)},
            {QStringLiteral("label"), QString::fromLatin1(c.label)},
            {QStringLiteral("envVar"), QString::fromLatin1(c.envVar)},
            {QStringLiteral("signupUrl"), QString::fromLatin1(c.signupUrl)},
            {QStringLiteral("note"), notes.value(c.id)},
        });
    }
    return out;
}

namespace providers {

ProviderTask *script(const QString &providerId, const prov::ScriptRequest &request,
                     QObject *parent)
{
    if (providerId == QLatin1String("openai-chat"))
        return new OpenAiScriptTask(request, parent);
    if (providerId == QLatin1String("anthropic-messages"))
        return new AnthropicScriptTask(request, parent);
    if (providerId == QLatin1String("gemini-generate"))
        return new GeminiScriptTask(request, parent);
    return nullptr;
}

ProviderTask *image(const QString &providerId, const prov::ImageRequest &request, QObject *parent)
{
    if (providerId == QLatin1String("openai-image"))
        return new OpenAiImageTask(request, parent);
    if (providerId == QLatin1String("fal-image"))
        return new FalImageTask(request, parent);
    if (providerId == QLatin1String("replicate-image"))
        return new ReplicateImageTask(request, parent);
    return nullptr;
}

ProviderTask *video(const QString &providerId, const prov::VideoRequest &request, QObject *parent)
{
    if (providerId == QLatin1String("fal-video"))
        return new FalVideoTask(request, parent);
    if (providerId == QLatin1String("replicate-video"))
        return new ReplicateVideoTask(request, parent);
    if (providerId == QLatin1String("openai-video"))
        return new SoraVideoTask(request, parent);
    return nullptr;
}

ProviderTask *voice(const QString &providerId, const prov::VoiceRequest &request, QObject *parent)
{
    if (providerId == QLatin1String("elevenlabs"))
        return new ElevenLabsVoiceTask(request, parent);
    if (providerId == QLatin1String("openai-tts"))
        return new OpenAiVoiceTask(request, parent);
    if (providerId == QLatin1String("fal-voice"))
        return new FalVoiceTask(request, parent);
    return nullptr;
}

ProviderTask *transcribe(const QString &providerId, const prov::TranscribeRequest &request,
                         QObject *parent)
{
    if (providerId == QLatin1String("openai-whisper"))
        return new WhisperCaptionTask(request, parent);
    return nullptr;
}

ProviderTask *voiceCatalog(const QString &providerId, const QString &apiKey, QObject *parent)
{
    if (providerId == QLatin1String("elevenlabs"))
        return new ElevenLabsVoiceListTask(apiKey, parent);
    if (providerId == QLatin1String("openai-tts"))
        return new OpenAiVoiceListTask(parent);
    if (providerId == QLatin1String("fal-voice"))
        return new FalVoiceListTask(parent);
    return nullptr;
}

} // namespace providers
