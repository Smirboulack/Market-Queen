#include "VideoProviders.h"

#include "core/Http.h"

#include <QJsonArray>
#include <QJsonObject>

VideoTask::VideoTask(const prov::VideoRequest &request, QObject *parent)
    : HttpTask(parent)
    , m_request(request)
{
}

void VideoTask::deliverFromUrl(const QString &url)
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
// Every model on fal has its own input schema and rejects unknown fields, so we
// only send the options a model family is known to accept. prompt + image_url
// is the common denominator for image-to-video.
// ---------------------------------------------------------------------------
void FalVideoTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("fal.ai")))
        return;
    if (m_request.imageDataUri.isEmpty()) {
        fail(tr("No opening frame to animate."));
        return;
    }

    QJsonObject input{
        {QStringLiteral("prompt"), m_request.prompt},
        {QStringLiteral("image_url"), m_request.imageDataUri},
    };

    const QString model = m_request.model;
    if (model.contains(QLatin1String("kling"))) {
        input.insert(QStringLiteral("duration"),
                     m_request.durationSeconds > 7 ? QStringLiteral("10") : QStringLiteral("5"));
        input.insert(QStringLiteral("aspect_ratio"), m_request.aspectRatio);
    } else if (model.contains(QLatin1String("hailuo"))) {
        input.insert(QStringLiteral("duration"),
                     m_request.durationSeconds > 7 ? QStringLiteral("10") : QStringLiteral("6"));
    } else if (model.contains(QLatin1String("luma"))) {
        input.insert(QStringLiteral("aspect_ratio"), m_request.aspectRatio);
    }

    submitFal(m_request.apiKey, model, input, [this](const QJsonObject &result) {
        QString url = jsonPath(result, QStringLiteral("video.url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("videos.0.url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("url"));
        deliverFromUrl(url);
    });
}

// ---------------------------------------------------------------------------
// Replicate
//
// Same story: the first-frame parameter is called `start_image` on Kling and
// `image` almost everywhere else.
// ---------------------------------------------------------------------------
void ReplicateVideoTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("Replicate")))
        return;
    if (m_request.imageDataUri.isEmpty()) {
        fail(tr("No opening frame to animate."));
        return;
    }

    QJsonObject input{{QStringLiteral("prompt"), m_request.prompt}};

    if (m_request.model.contains(QLatin1String("kling"))) {
        input.insert(QStringLiteral("start_image"), m_request.imageDataUri);
        input.insert(QStringLiteral("duration"), m_request.durationSeconds > 7 ? 10 : 5);
        input.insert(QStringLiteral("aspect_ratio"), m_request.aspectRatio);
    } else {
        input.insert(QStringLiteral("image"), m_request.imageDataUri);
    }

    submitReplicate(m_request.apiKey, m_request.model, input,
                    [this](const QJsonObject &prediction) {
                        deliverFromUrl(replicateOutputUrl(prediction));
                    });
}
