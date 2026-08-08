#include "VideoProviders.h"

#include "core/Http.h"

#include <QBuffer>
#include <QHttpMultiPart>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrlQuery>

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

// ---------------------------------------------------------------------------
// OpenAI Sora - POST /v1/videos, poll, then download the rendered file.
// ---------------------------------------------------------------------------
namespace {

// Sora only renders a fixed set of resolutions, and the reference frame has to
// match the chosen one exactly.
QSize soraSize(const QString &aspectRatio)
{
    if (aspectRatio == QLatin1String("16:9"))
        return {1280, 720};
    return {720, 1280};
}

// 4, 8 or 12 seconds -- nothing in between.
QString soraSeconds(int requested)
{
    if (requested <= 4)
        return QStringLiteral("4");
    if (requested <= 8)
        return QStringLiteral("8");
    return QStringLiteral("12");
}

// Scale to cover, then centre-crop, so the frame fills the target exactly
// without distortion.
QByteArray fitToSize(const QByteArray &imageData, const QSize &target)
{
    QImage image;
    if (!image.loadFromData(imageData))
        return {};

    const QImage scaled = image.scaled(target, Qt::KeepAspectRatioByExpanding,
                                       Qt::SmoothTransformation);
    const QImage cropped = scaled.copy((scaled.width() - target.width()) / 2,
                                       (scaled.height() - target.height()) / 2,
                                       target.width(), target.height());

    QByteArray out;
    QBuffer buffer(&out);
    buffer.open(QIODevice::WriteOnly);
    if (!cropped.save(&buffer, "PNG"))
        return {};
    return out;
}

} // namespace

void SoraVideoTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("OpenAI")))
        return;
    if (m_request.imageDataUri.isEmpty()) {
        fail(tr("No opening frame to animate."));
        return;
    }

    m_outputSize = soraSize(m_request.aspectRatio);

    const QByteArray frame = fitToSize(http::dataUriPayload(m_request.imageDataUri), m_outputSize);
    if (frame.isEmpty()) {
        fail(tr("Could not prepare the opening frame for Sora."));
        return;
    }

    report(tr("Sending the shot to Sora (%1)...").arg(m_request.model));

    auto *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    const auto addField = [multiPart](const QString &name, const QString &value) {
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"%1\"").arg(name));
        part.setBody(value.toUtf8());
        multiPart->append(part);
    };

    addField(QStringLiteral("model"), m_request.model);
    addField(QStringLiteral("prompt"), m_request.prompt);
    addField(QStringLiteral("seconds"), soraSeconds(m_request.durationSeconds));
    addField(QStringLiteral("size"),
             QStringLiteral("%1x%2").arg(m_outputSize.width()).arg(m_outputSize.height()));

    QHttpPart framePart;
    framePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                        QStringLiteral("form-data; name=\"input_reference\"; "
                                       "filename=\"frame.png\""));
    framePart.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("image/png"));
    framePart.setBody(frame);
    multiPart->append(framePart);

    QNetworkRequest request(QUrl(QStringLiteral("https://api.openai.com/v1/videos")));
    request.setRawHeader("Authorization", ("Bearer " + m_request.apiKey).toUtf8());
    request.setRawHeader("User-Agent", "MarketQueen/" APP_VERSION);
    request.setTransferTimeout(300'000);

    postMultipartForText(request, multiPart, [this](const QByteArray &body, const QString &) {
        const QJsonObject response = QJsonDocument::fromJson(body).object();
        const QString videoId = response.value(QStringLiteral("id")).toString();
        if (videoId.isEmpty()) {
            const QString apiError = http::extractApiError(body);
            fail(apiError.isEmpty() ? tr("Sora did not return a job id.") : apiError);
            return;
        }
        pollJob(videoId);
    });
}

void SoraVideoTask::pollJob(const QString &videoId)
{
    const QVariantMap headers{
        {QStringLiteral("Authorization"), QStringLiteral("Bearer ") + m_request.apiKey}};

    pollUntil(
        QUrl(QStringLiteral("https://api.openai.com/v1/videos/%1").arg(videoId)), headers,
        [this](const QJsonObject &status, QString *error) {
            const QString state = status.value(QStringLiteral("status")).toString();
            if (state == QLatin1String("completed"))
                return PollState::Done;
            if (state == QLatin1String("queued") || state == QLatin1String("in_progress")) {
                const int progress = status.value(QStringLiteral("progress")).toInt(-1);
                report(progress >= 0 ? tr("Sora is rendering... %1%").arg(progress)
                                     : tr("Sora is rendering..."));
                return PollState::Pending;
            }
            *error = status.value(QStringLiteral("error")).toObject()
                         .value(QStringLiteral("message")).toString();
            if (error->isEmpty())
                *error = tr("Sora reported status \"%1\".").arg(state);
            return PollState::Failed;
        },
        [this, videoId](const QJsonObject &) { fetchContent(videoId); });
}

void SoraVideoTask::fetchContent(const QString &videoId)
{
    report(tr("Downloading the clip..."));

    QNetworkRequest request(
        QUrl(QStringLiteral("https://api.openai.com/v1/videos/%1/content").arg(videoId)));
    request.setRawHeader("Authorization", ("Bearer " + m_request.apiKey).toUtf8());
    request.setRawHeader("User-Agent", "MarketQueen/" APP_VERSION);

    getBytes(request, [this](const QByteArray &data, const QString &) {
        if (data.isEmpty()) {
            fail(tr("The downloaded clip was empty."));
            return;
        }
        succeed({{QStringLiteral("data"), data},
                 {QStringLiteral("extension"), QStringLiteral("mp4")}});
    });
}
