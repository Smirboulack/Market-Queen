#include "Registry.h"

#include "ImageProviders.h"
#include "ProviderTask.h"
#include "TextProviders.h"
#include "VideoProviders.h"
#include "VoiceProviders.h"

#include <QVariantMap>

namespace {

QVariantMap toMap(const Registry::Entry &e)
{
    return {
        {QStringLiteral("id"), e.id},
        {QStringLiteral("category"), e.category},
        {QStringLiteral("label"), e.label},
        {QStringLiteral("credential"), e.credential},
        {QStringLiteral("models"), e.models},
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
    m_entries = {
        // ---- Script writers -------------------------------------------------
        {QStringLiteral("openai-chat"), QStringLiteral("text"), QStringLiteral("OpenAI"),
         QStringLiteral("openai"),
         {QStringLiteral("gpt-5"), QStringLiteral("gpt-4.1"), QStringLiteral("gpt-4o"),
          QStringLiteral("gpt-4o-mini")},
         QStringLiteral("gpt-4.1"),
         tr("Reads the product photo when the model supports vision.")},

        {QStringLiteral("anthropic-messages"), QStringLiteral("text"),
         QStringLiteral("Anthropic (Claude)"), QStringLiteral("anthropic"),
         {QStringLiteral("claude-opus-5"), QStringLiteral("claude-sonnet-5"),
          QStringLiteral("claude-haiku-4-5-20251001")},
         QStringLiteral("claude-sonnet-5"),
         tr("Strong at short, natural-sounding ad copy.")},

        {QStringLiteral("gemini-generate"), QStringLiteral("text"),
         QStringLiteral("Google Gemini"), QStringLiteral("gemini"),
         {QStringLiteral("gemini-2.5-pro"), QStringLiteral("gemini-2.5-flash"),
          QStringLiteral("gemini-2.0-flash")},
         QStringLiteral("gemini-2.5-flash"),
         tr("Free tier available in most regions.")},

        // ---- Image ----------------------------------------------------------
        {QStringLiteral("openai-image"), QStringLiteral("image"), QStringLiteral("OpenAI Images"),
         QStringLiteral("openai"),
         {QStringLiteral("gpt-image-1"), QStringLiteral("dall-e-3")},
         QStringLiteral("gpt-image-1"),
         tr("gpt-image-1 can edit your product photo directly.")},

        {QStringLiteral("fal-image"), QStringLiteral("image"), QStringLiteral("fal.ai"),
         QStringLiteral("fal"),
         {QStringLiteral("fal-ai/flux-pro/v1.1-ultra"), QStringLiteral("fal-ai/flux/dev"),
          QStringLiteral("fal-ai/flux/schnell"), QStringLiteral("fal-ai/recraft-v3")},
         QStringLiteral("fal-ai/flux/dev"),
         tr("Any fal model id works, paste one from fal.ai/models.")},

        {QStringLiteral("replicate-image"), QStringLiteral("image"), QStringLiteral("Replicate"),
         QStringLiteral("replicate"),
         {QStringLiteral("black-forest-labs/flux-1.1-pro"),
          QStringLiteral("black-forest-labs/flux-schnell"),
          QStringLiteral("stability-ai/stable-diffusion-3.5-large")},
         QStringLiteral("black-forest-labs/flux-schnell"),
         tr("Use owner/name, or owner/name:version to pin a version.")},

        // ---- Video (image to video) ----------------------------------------
        {QStringLiteral("fal-video"), QStringLiteral("video"), QStringLiteral("fal.ai"),
         QStringLiteral("fal"),
         {QStringLiteral("fal-ai/kling-video/v2/master/image-to-video"),
          QStringLiteral("fal-ai/minimax/hailuo-02/standard/image-to-video"),
          QStringLiteral("fal-ai/wan-i2v"),
          QStringLiteral("fal-ai/luma-dream-machine/image-to-video")},
         QStringLiteral("fal-ai/kling-video/v2/master/image-to-video"),
         tr("Kling, Hailuo, Wan, Luma - all behind one key.")},

        {QStringLiteral("replicate-video"), QStringLiteral("video"), QStringLiteral("Replicate"),
         QStringLiteral("replicate"),
         {QStringLiteral("kwaivgi/kling-v2.1"), QStringLiteral("wan-video/wan-2.2-i2v-fast"),
          QStringLiteral("minimax/video-01")},
         QStringLiteral("wan-video/wan-2.2-i2v-fast"),
         tr("Pay per second, no subscription.")},

        // ---- Voice ----------------------------------------------------------
        {QStringLiteral("elevenlabs"), QStringLiteral("voice"), QStringLiteral("ElevenLabs"),
         QStringLiteral("elevenlabs"),
         {QStringLiteral("eleven_multilingual_v2"), QStringLiteral("eleven_turbo_v2_5"),
          QStringLiteral("eleven_flash_v2_5")},
         QStringLiteral("eleven_multilingual_v2"),
         tr("Best UGC-sounding voices. Load your voice list below.")},

        {QStringLiteral("openai-tts"), QStringLiteral("voice"), QStringLiteral("OpenAI TTS"),
         QStringLiteral("openai"),
         {QStringLiteral("gpt-4o-mini-tts"), QStringLiteral("tts-1-hd"), QStringLiteral("tts-1")},
         QStringLiteral("gpt-4o-mini-tts"),
         tr("Cheap and fast, fixed set of voices.")},

        // ---- Captions -------------------------------------------------------
        {QStringLiteral("openai-whisper"), QStringLiteral("captions"),
         QStringLiteral("OpenAI Whisper"), QStringLiteral("openai"),
         {QStringLiteral("whisper-1")}, QStringLiteral("whisper-1"),
         tr("Transcribes the generated voice-over into timed subtitles.")},
    };
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
        {"openai", tr("Scripts, images, voice-over and subtitles.")},
        {"anthropic", tr("Scripts.")},
        {"gemini", tr("Scripts.")},
        {"fal", tr("Images and video (Kling, Wan, Hailuo, Flux).")},
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
    return nullptr;
}

ProviderTask *voice(const QString &providerId, const prov::VoiceRequest &request, QObject *parent)
{
    if (providerId == QLatin1String("elevenlabs"))
        return new ElevenLabsVoiceTask(request, parent);
    if (providerId == QLatin1String("openai-tts"))
        return new OpenAiVoiceTask(request, parent);
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
    return nullptr;
}

} // namespace providers
