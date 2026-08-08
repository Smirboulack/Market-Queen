#include "AvatarProviders.h"

#include "core/Http.h"

#include <QJsonObject>
#include <QUrl>

AvatarTask::AvatarTask(const prov::AvatarRequest &request, QObject *parent)
    : HttpTask(parent)
    , m_request(request)
{
}

void AvatarTask::deliverFromUrl(const QString &url)
{
    if (url.isEmpty()) {
        fail(tr("The provider returned no video."));
        return;
    }
    report(tr("Downloading the clip..."));
    download(QUrl(url), [this, url](const QByteArray &data, const QString &contentType) {
        if (data.isEmpty()) {
            fail(tr("The downloaded clip was empty."));
            return;
        }
        succeed({{QStringLiteral("data"), data},
                 {QStringLiteral("extension"),
                  http::guessExtension(url, contentType, QStringLiteral("mp4"))}});
    });
}

// ---------------------------------------------------------------------------
// fal.ai
//
// Kling AI Avatar, VEED Fabric and InfiniTalk all take the same two inputs, so
// unlike the image-to-video models there is no per-family shaping to do. fal
// accepts a base64 data URI wherever it accepts a file url, and a few seconds of
// speech is small enough that uploading it separately would only add a failure
// mode.
// ---------------------------------------------------------------------------
void FalAvatarTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("fal.ai")))
        return;
    if (m_request.imageDataUri.isEmpty()) {
        fail(tr("No frame to animate."));
        return;
    }
    if (m_request.audioDataUri.isEmpty()) {
        fail(tr("No audio for this shot, so there is nothing to lip-sync to."));
        return;
    }

    QJsonObject input{
        {QStringLiteral("image_url"), m_request.imageDataUri},
        {QStringLiteral("audio_url"), m_request.audioDataUri},
    };
    if (!m_request.prompt.isEmpty())
        input.insert(QStringLiteral("prompt"), m_request.prompt);

    submitFal(m_request.apiKey, m_request.model, input, [this](const QJsonObject &result) {
        QString url = jsonPath(result, QStringLiteral("video.url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("videos.0.url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("url"));
        deliverFromUrl(url);
    });
}
