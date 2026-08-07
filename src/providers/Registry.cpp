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
         {M("gpt-5", "GPT-5"), M("gpt-5-mini", "GPT-5 mini"), M("gpt-4.1", "GPT-4.1"),
          M("gpt-4o", "GPT-4o"), M("gpt-4o-mini", "GPT-4o mini")},
         QStringLiteral("gpt-4.1"),
         tr("Reads the product photo when the model supports vision.")},

        {QStringLiteral("anthropic-messages"), QStringLiteral("text"),
         QStringLiteral("Anthropic (Claude)"), QStringLiteral("anthropic"),
         {M("claude-opus-5", "Claude Opus 5"), M("claude-sonnet-5", "Claude Sonnet 5"),
          M("claude-haiku-4-5-20251001", "Claude Haiku 4.5")},
         QStringLiteral("claude-sonnet-5"),
         tr("Strong at short, natural-sounding ad copy.")},

        {QStringLiteral("gemini-generate"), QStringLiteral("text"),
         QStringLiteral("Google Gemini"), QStringLiteral("gemini"),
         {M("gemini-2.5-pro", "Gemini 2.5 Pro"), M("gemini-2.5-flash", "Gemini 2.5 Flash"),
          M("gemini-2.0-flash", "Gemini 2.0 Flash")},
         QStringLiteral("gemini-2.5-flash"),
         tr("Free tier available in most regions.")},

        // ---- Image ----------------------------------------------------------
        {QStringLiteral("fal-image"), QStringLiteral("image"), QStringLiteral("fal.ai"),
         QStringLiteral("fal"),
         {autoModel,
          M("fal-ai/nano-banana/edit", "Nano Banana (edit)"),
          M("fal-ai/nano-banana", "Nano Banana"),
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
         {autoModel, M("gpt-image-1", "GPT Image 1"), M("gpt-image-1-mini", "GPT Image 1 mini"),
          M("dall-e-3", "DALL-E 3")},
         QStringLiteral("auto"),
         tr("gpt-image-1 can edit your product photo directly.")},

        {QStringLiteral("replicate-image"), QStringLiteral("image"), QStringLiteral("Replicate"),
         QStringLiteral("replicate"),
         {autoModel,
          M("google/nano-banana", "Nano Banana"),
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
        {QStringLiteral("fal-video"), QStringLiteral("video"), QStringLiteral("fal.ai"),
         QStringLiteral("fal"),
         {autoModel,
          M("fal-ai/kling-video/v2.1/master/image-to-video", "Kling 2.1 Master"),
          M("fal-ai/kling-video/v2/master/image-to-video", "Kling 2.0 Master"),
          M("fal-ai/veo3/image-to-video", "Google Veo 3"),
          M("fal-ai/veo2/image-to-video", "Google Veo 2"),
          M("fal-ai/bytedance/seedance/v1/pro/image-to-video", "Seedance 1.0 Pro"),
          M("fal-ai/bytedance/seedance/v1/lite/image-to-video", "Seedance 1.0 Lite"),
          M("fal-ai/minimax/hailuo-02/pro/image-to-video", "Hailuo 02 Pro"),
          M("fal-ai/minimax/hailuo-02/standard/image-to-video", "Hailuo 02 Standard"),
          M("fal-ai/runway-gen3/turbo/image-to-video", "Runway Gen-3 Turbo"),
          M("fal-ai/luma-dream-machine/ray-2/image-to-video", "Luma Ray 2"),
          M("fal-ai/luma-dream-machine/image-to-video", "Luma Dream Machine"),
          M("fal-ai/wan/v2.2-a14b/image-to-video", "Wan 2.2 A14B"),
          M("fal-ai/wan-i2v", "Wan 2.1 I2V"),
          M("fal-ai/pika/v2.2/image-to-video", "Pika 2.2"),
          M("fal-ai/pixverse/v4.5/image-to-video", "PixVerse 4.5")},
         QStringLiteral("auto"),
         tr("Kling, Veo, Seedance, Hailuo, Runway, Luma, Wan, Pika - one key for all.")},

        {QStringLiteral("replicate-video"), QStringLiteral("video"), QStringLiteral("Replicate"),
         QStringLiteral("replicate"),
         {autoModel,
          M("kwaivgi/kling-v2.1", "Kling 2.1"),
          M("kwaivgi/kling-v1.6-pro", "Kling 1.6 Pro"),
          M("google/veo-3", "Google Veo 3"),
          M("google/veo-3-fast", "Google Veo 3 Fast"),
          M("bytedance/seedance-1-pro", "Seedance 1 Pro"),
          M("bytedance/seedance-1-lite", "Seedance 1 Lite"),
          M("minimax/hailuo-02", "Hailuo 02"),
          M("minimax/video-01", "Hailuo Video 01"),
          M("luma/ray", "Luma Ray"),
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
         {M("fal-ai/minimax/speech-02-hd", "MiniMax Speech 02 HD"),
          M("fal-ai/minimax/speech-02-turbo", "MiniMax Speech 02 Turbo"),
          M("fal-ai/elevenlabs/tts/multilingual-v2", "ElevenLabs Multilingual v2"),
          M("fal-ai/elevenlabs/tts/turbo-v2.5", "ElevenLabs Turbo v2.5"),
          M("fal-ai/kokoro/american-english", "Kokoro (American English)"),
          M("fal-ai/chatterbox/text-to-speech", "Chatterbox")},
         QStringLiteral("fal-ai/minimax/speech-02-hd"),
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
