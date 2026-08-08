#include "VoiceProviders.h"

#include "core/Http.h"

#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QUrlQuery>

VoiceTask::VoiceTask(const prov::VoiceRequest &request, QObject *parent)
    : HttpTask(parent)
    , m_request(request)
{
}

// ---------------------------------------------------------------------------
// ElevenLabs
// ---------------------------------------------------------------------------
void ElevenLabsVoiceTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("ElevenLabs")))
        return;
    if (m_request.voiceId.isEmpty()) {
        fail(tr("Pick an ElevenLabs voice first."));
        return;
    }

    report(tr("Recording the voice-over..."));

    QUrl url(QStringLiteral("https://api.elevenlabs.io/v1/text-to-speech/%1")
                 .arg(m_request.voiceId));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("output_format"), QStringLiteral("mp3_44100_128"));
    url.setQuery(query);

    const QJsonObject body{
        {QStringLiteral("text"), m_request.text},
        {QStringLiteral("model_id"), m_request.model},
        {QStringLiteral("voice_settings"),
         QJsonObject{{QStringLiteral("stability"), 0.45},
                     {QStringLiteral("similarity_boost"), 0.8},
                     {QStringLiteral("style"), 0.35},
                     {QStringLiteral("use_speaker_boost"), true}}},
    };

    QNetworkRequest request =
        http::jsonRequest(url, {{QStringLiteral("xi-api-key"), m_request.apiKey}});
    request.setRawHeader("Accept", "audio/mpeg");
    request.setTransferTimeout(300'000);

    postJsonForBytes(request, body, [this](const QByteArray &data, const QString &) {
        if (data.isEmpty()) {
            fail(tr("ElevenLabs returned no audio."));
            return;
        }
        succeed({{QStringLiteral("data"), data}, {QStringLiteral("extension"), QStringLiteral("mp3")}});
    });
}

// ---------------------------------------------------------------------------
// OpenAI TTS
// ---------------------------------------------------------------------------
void OpenAiVoiceTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("OpenAI")))
        return;

    report(tr("Recording the voice-over..."));

    QJsonObject body{
        {QStringLiteral("model"), m_request.model},
        {QStringLiteral("input"), m_request.text},
        {QStringLiteral("voice"),
         m_request.voiceId.isEmpty() ? QStringLiteral("alloy") : m_request.voiceId},
        {QStringLiteral("response_format"), QStringLiteral("mp3")},
    };
    // `speed` only exists on the tts-1 family.
    if (m_request.model.startsWith(QLatin1String("tts-1")) && !qFuzzyCompare(m_request.speed, 1.0))
        body.insert(QStringLiteral("speed"), m_request.speed);
    else if (m_request.model.startsWith(QLatin1String("gpt-4o")))
        body.insert(QStringLiteral("instructions"),
                    QStringLiteral("Speak like a real person filming a casual selfie video: "
                                   "upbeat, natural, conversational, not like an announcer."));

    QNetworkRequest request = http::jsonRequest(
        QUrl(QStringLiteral("https://api.openai.com/v1/audio/speech")),
        {{QStringLiteral("Authorization"), QStringLiteral("Bearer ") + m_request.apiKey}});
    request.setTransferTimeout(300'000);

    postJsonForBytes(request, body, [this](const QByteArray &data, const QString &) {
        if (data.isEmpty()) {
            fail(tr("OpenAI returned no audio."));
            return;
        }
        succeed({{QStringLiteral("data"), data}, {QStringLiteral("extension"), QStringLiteral("mp3")}});
    });
}

// ---------------------------------------------------------------------------
// fal.ai voices
// ---------------------------------------------------------------------------
void FalVoiceTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("fal.ai")))
        return;

    report(tr("Recording the voice-over..."));

    const QString model = m_request.model;
    QJsonObject input;

    if (model.contains(QLatin1String("minimax"))) {
        input.insert(QStringLiteral("text"), m_request.text);
        if (!m_request.voiceId.isEmpty()) {
            input.insert(QStringLiteral("voice_setting"),
                         QJsonObject{{QStringLiteral("voice_id"), m_request.voiceId}});
        }
    } else if (model.contains(QLatin1String("elevenlabs"))) {
        input.insert(QStringLiteral("text"), m_request.text);
        if (!m_request.voiceId.isEmpty())
            input.insert(QStringLiteral("voice"), m_request.voiceId);
    } else if (model.contains(QLatin1String("kokoro"))) {
        input.insert(QStringLiteral("prompt"), m_request.text);
        if (!m_request.voiceId.isEmpty())
            input.insert(QStringLiteral("voice"), m_request.voiceId);
    } else {
        input.insert(QStringLiteral("text"), m_request.text);
    }

    submitFal(m_request.apiKey, model, input, [this](const QJsonObject &result) {
        QString url = jsonPath(result, QStringLiteral("audio.url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("audio_url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("url"));
        if (url.isEmpty()) {
            fail(tr("fal.ai returned no audio."));
            return;
        }

        download(QUrl(url), [this, url](const QByteArray &data, const QString &contentType) {
            if (data.isEmpty()) {
                fail(tr("fal.ai returned no audio."));
                return;
            }
            succeed({{QStringLiteral("data"), data},
                     {QStringLiteral("extension"),
                      http::guessExtension(url, contentType, QStringLiteral("mp3"))}});
        });
    });
}

// ---------------------------------------------------------------------------
// Whisper subtitles
// ---------------------------------------------------------------------------
WhisperCaptionTask::WhisperCaptionTask(const prov::TranscribeRequest &request, QObject *parent)
    : HttpTask(parent)
    , m_request(request)
{
}

void WhisperCaptionTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("OpenAI")))
        return;

    QFile audio(m_request.audioPath);
    if (!audio.open(QIODevice::ReadOnly)) {
        fail(tr("Could not read the voice-over file."));
        return;
    }
    const QByteArray audioData = audio.readAll();
    audio.close();

    report(tr("Timing the subtitles..."));

    auto *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    const auto addField = [multiPart](const QString &name, const QString &value) {
        if (value.isEmpty())
            return;
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"%1\"").arg(name));
        part.setBody(value.toUtf8());
        multiPart->append(part);
    };

    addField(QStringLiteral("model"), m_request.model);
    addField(QStringLiteral("response_format"), QStringLiteral("srt"));
    addField(QStringLiteral("language"), m_request.language);

    QHttpPart filePart;
    const QString fileName = QFileInfo(m_request.audioPath).fileName();
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"file\"; filename=\"%1\"").arg(fileName));
    filePart.setHeader(QNetworkRequest::ContentTypeHeader,
                       QMimeDatabase().mimeTypeForFile(m_request.audioPath).name());
    filePart.setBody(audioData);
    multiPart->append(filePart);

    QNetworkRequest request(QUrl(QStringLiteral("https://api.openai.com/v1/audio/transcriptions")));
    request.setRawHeader("Authorization", ("Bearer " + m_request.apiKey).toUtf8());
    request.setRawHeader("User-Agent", "MarketQueen/" APP_VERSION);
    request.setTransferTimeout(300'000);

    postMultipartForText(request, multiPart, [this](const QByteArray &body, const QString &) {
        const QString srt = QString::fromUtf8(body).trimmed();
        if (srt.isEmpty()) {
            fail(tr("Whisper returned an empty transcript."));
            return;
        }
        succeed({{QStringLiteral("srt"), srt}});
    });
}

// ---------------------------------------------------------------------------
// Voice catalogues
// ---------------------------------------------------------------------------
ElevenLabsVoiceListTask::ElevenLabsVoiceListTask(const QString &apiKey, QObject *parent)
    : HttpTask(parent)
    , m_apiKey(apiKey)
{
}

void ElevenLabsVoiceListTask::start()
{
    if (!requireKey(m_apiKey, QStringLiteral("ElevenLabs")))
        return;

    const QNetworkRequest request =
        http::jsonRequest(QUrl(QStringLiteral("https://api.elevenlabs.io/v1/voices")),
                          {{QStringLiteral("xi-api-key"), m_apiKey}});

    getJson(request, [this](const QJsonObject &response) {
        QVariantList voices;
        const QJsonArray array = response.value(QStringLiteral("voices")).toArray();
        for (const QJsonValue &value : array) {
            const QJsonObject voice = value.toObject();
            const QJsonObject labels = voice.value(QStringLiteral("labels")).toObject();

            QStringList descriptors;
            for (const auto &key : {"accent", "gender", "age", "use_case", "description"}) {
                const QString v = labels.value(QLatin1String(key)).toString();
                if (!v.isEmpty())
                    descriptors << v;
            }

            voices.append(QVariantMap{
                {QStringLiteral("id"), voice.value(QStringLiteral("voice_id")).toString()},
                {QStringLiteral("label"), voice.value(QStringLiteral("name")).toString()},
                {QStringLiteral("description"), descriptors.join(QStringLiteral(" - "))},
            });
        }

        if (voices.isEmpty()) {
            fail(tr("No voices on this ElevenLabs account."));
            return;
        }
        succeed({{QStringLiteral("voices"), voices}});
    });
}

OpenAiVoiceListTask::OpenAiVoiceListTask(QObject *parent)
    : ProviderTask(parent)
{
}

void OpenAiVoiceListTask::start()
{
    // OpenAI has no voices endpoint: the set is fixed and documented.
    static const QList<QPair<QString, QString>> kVoices = {
        {QStringLiteral("alloy"), QStringLiteral("neutral, balanced")},
        {QStringLiteral("ash"), QStringLiteral("warm, grounded")},
        {QStringLiteral("ballad"), QStringLiteral("soft, expressive")},
        {QStringLiteral("coral"), QStringLiteral("bright, friendly")},
        {QStringLiteral("echo"), QStringLiteral("calm, even")},
        {QStringLiteral("fable"), QStringLiteral("storytelling")},
        {QStringLiteral("nova"), QStringLiteral("energetic, young")},
        {QStringLiteral("onyx"), QStringLiteral("deep, male")},
        {QStringLiteral("sage"), QStringLiteral("measured")},
        {QStringLiteral("shimmer"), QStringLiteral("light, upbeat")},
        {QStringLiteral("verse"), QStringLiteral("conversational")},
    };

    QVariantList voices;
    for (const auto &[id, description] : kVoices) {
        voices.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("label"), id},
            {QStringLiteral("description"), description},
        });
    }
    succeed({{QStringLiteral("voices"), voices}});
}

FalVoiceListTask::FalVoiceListTask(QObject *parent)
    : ProviderTask(parent)
{
}

void FalVoiceListTask::start()
{
    // fal has no voices endpoint: each engine ships its own named set. These
    // are the MiniMax and ElevenLabs presets; any other id can be typed in.
    static const QList<QPair<QString, QString>> kVoices = {
        {QStringLiteral("Wise_Woman"), QStringLiteral("MiniMax - warm, mature")},
        {QStringLiteral("Friendly_Person"), QStringLiteral("MiniMax - upbeat, casual")},
        {QStringLiteral("Inspirational_girl"), QStringLiteral("MiniMax - young, energetic")},
        {QStringLiteral("Deep_Voice_Man"), QStringLiteral("MiniMax - deep, male")},
        {QStringLiteral("Calm_Woman"), QStringLiteral("MiniMax - calm, female")},
        {QStringLiteral("Casual_Guy"), QStringLiteral("MiniMax - relaxed, male")},
        {QStringLiteral("Lively_Girl"), QStringLiteral("MiniMax - lively, female")},
        {QStringLiteral("Rachel"), QStringLiteral("ElevenLabs - natural, female")},
        {QStringLiteral("Aria"), QStringLiteral("ElevenLabs - expressive, female")},
        {QStringLiteral("Josh"), QStringLiteral("ElevenLabs - young, male")},
        {QStringLiteral("af_heart"), QStringLiteral("Kokoro - American female")},
        {QStringLiteral("am_adam"), QStringLiteral("Kokoro - American male")},
    };

    QVariantList voices;
    for (const auto &[id, description] : kVoices) {
        voices.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("label"), id},
            {QStringLiteral("description"), description},
        });
    }
    succeed({{QStringLiteral("voices"), voices}});
}
