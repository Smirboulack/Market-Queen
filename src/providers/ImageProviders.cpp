#include "ImageProviders.h"

#include "core/Http.h"

#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {

// gpt-image-1 and dall-e-3 accept different size strings.
QString openAiSize(const QString &model, const QString &aspect)
{
    const bool dalle = model.startsWith(QLatin1String("dall-e"));
    if (aspect == QLatin1String("16:9"))
        return dalle ? QStringLiteral("1792x1024") : QStringLiteral("1536x1024");
    if (aspect == QLatin1String("1:1"))
        return QStringLiteral("1024x1024");
    return dalle ? QStringLiteral("1024x1792") : QStringLiteral("1024x1536");
}

QString falImageSize(const QString &aspect)
{
    if (aspect == QLatin1String("16:9"))
        return QStringLiteral("landscape_16_9");
    if (aspect == QLatin1String("1:1"))
        return QStringLiteral("square_hd");
    return QStringLiteral("portrait_16_9");
}

} // namespace

ImageTask::ImageTask(const prov::ImageRequest &request, QObject *parent)
    : HttpTask(parent)
    , m_request(request)
{
}

void ImageTask::deliver(const QByteArray &data, const QString &extension)
{
    if (data.isEmpty()) {
        fail(tr("The provider returned an empty image."));
        return;
    }
    succeed({{QStringLiteral("data"), data}, {QStringLiteral("extension"), extension}});
}

// ---------------------------------------------------------------------------
// OpenAI Images
// ---------------------------------------------------------------------------
void OpenAiImageTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("OpenAI")))
        return;

    // With a product photo in hand, editing keeps the real product in frame.
    const bool canEdit = m_request.model.startsWith(QLatin1String("gpt-image"))
        && !m_request.referenceImageDataUri.isEmpty();
    if (canEdit)
        edit();
    else
        generate();
}

void OpenAiImageTask::generate()
{
    report(tr("Generating the opening frame with %1...").arg(m_request.model));

    QJsonObject body{
        {QStringLiteral("model"), m_request.model},
        {QStringLiteral("prompt"), m_request.prompt},
        {QStringLiteral("size"), openAiSize(m_request.model, m_request.aspectRatio)},
        {QStringLiteral("n"), 1},
    };
    // gpt-image-1 always answers with base64 and rejects response_format.
    if (m_request.model.startsWith(QLatin1String("dall-e")))
        body.insert(QStringLiteral("response_format"), QStringLiteral("b64_json"));

    const QNetworkRequest request = http::jsonRequest(
        QUrl(QStringLiteral("https://api.openai.com/v1/images/generations")),
        {{QStringLiteral("Authorization"), QStringLiteral("Bearer ") + m_request.apiKey}});

    postJson(request, body, [this](const QJsonObject &response) {
        const QJsonObject first =
            response.value(QStringLiteral("data")).toArray().first().toObject();

        const QString b64 = first.value(QStringLiteral("b64_json")).toString();
        if (!b64.isEmpty()) {
            deliver(QByteArray::fromBase64(b64.toLatin1()), QStringLiteral("png"));
            return;
        }

        const QString url = first.value(QStringLiteral("url")).toString();
        if (url.isEmpty()) {
            fail(tr("OpenAI returned no image."));
            return;
        }
        download(QUrl(url), [this, url](const QByteArray &data, const QString &contentType) {
            deliver(data, http::guessExtension(url, contentType, QStringLiteral("png")));
        });
    });
}

void OpenAiImageTask::edit()
{
    report(tr("Building the opening frame from your product photo..."));

    QString mimeType;
    const QByteArray imageBytes = http::dataUriPayload(m_request.referenceImageDataUri, &mimeType);
    if (imageBytes.isEmpty()) {
        generate();
        return;
    }

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
    addField(QStringLiteral("size"), openAiSize(m_request.model, m_request.aspectRatio));
    addField(QStringLiteral("n"), QStringLiteral("1"));

    QHttpPart imagePart;
    const QString extension = mimeType.section(QLatin1Char('/'), 1, 1);
    imagePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                        QStringLiteral("form-data; name=\"image[]\"; filename=\"product.%1\"")
                            .arg(extension.isEmpty() ? QStringLiteral("png") : extension));
    imagePart.setHeader(QNetworkRequest::ContentTypeHeader,
                        mimeType.isEmpty() ? QStringLiteral("image/png") : mimeType);
    imagePart.setBody(imageBytes);
    multiPart->append(imagePart);

    QNetworkRequest request(QUrl(QStringLiteral("https://api.openai.com/v1/images/edits")));
    request.setRawHeader("Authorization", ("Bearer " + m_request.apiKey).toUtf8());
    request.setRawHeader("User-Agent", "MarketQueen/" APP_VERSION);
    request.setTransferTimeout(300'000);

    postMultipartForText(request, multiPart, [this](const QByteArray &body, const QString &) {
        const QJsonObject response = QJsonDocument::fromJson(body).object();
        const QString b64 = jsonPath(response, QStringLiteral("data.0.b64_json"));
        if (!b64.isEmpty()) {
            deliver(QByteArray::fromBase64(b64.toLatin1()), QStringLiteral("png"));
            return;
        }
        const QString url = jsonPath(response, QStringLiteral("data.0.url"));
        if (url.isEmpty()) {
            const QString apiError = http::extractApiError(body);
            fail(apiError.isEmpty() ? tr("OpenAI returned no image.") : apiError);
            return;
        }
        download(QUrl(url), [this, url](const QByteArray &data, const QString &contentType) {
            deliver(data, http::guessExtension(url, contentType, QStringLiteral("png")));
        });
    });
}

// ---------------------------------------------------------------------------
// fal.ai
// ---------------------------------------------------------------------------
void FalImageTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("fal.ai")))
        return;

    QJsonObject input{
        {QStringLiteral("prompt"), m_request.prompt},
        {QStringLiteral("image_size"), falImageSize(m_request.aspectRatio)},
        {QStringLiteral("num_images"), 1},
    };
    if (!m_request.referenceImageDataUri.isEmpty()) {
        // Image-to-image models read this; text-to-image models ignore it.
        input.insert(QStringLiteral("image_url"), m_request.referenceImageDataUri);
    }

    submitFal(m_request.apiKey, m_request.model, input, [this](const QJsonObject &result) {
        QString url = jsonPath(result, QStringLiteral("images.0.url"));
        if (url.isEmpty())
            url = jsonPath(result, QStringLiteral("image.url"));
        if (url.isEmpty()) {
            fail(tr("fal.ai returned no image."));
            return;
        }
        download(QUrl(url), [this, url](const QByteArray &data, const QString &contentType) {
            deliver(data, http::guessExtension(url, contentType, QStringLiteral("png")));
        });
    });
}

// ---------------------------------------------------------------------------
// Replicate
// ---------------------------------------------------------------------------
void ReplicateImageTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("Replicate")))
        return;

    QJsonObject input{
        {QStringLiteral("prompt"), m_request.prompt},
        {QStringLiteral("aspect_ratio"),
         m_request.aspectRatio.isEmpty() ? QStringLiteral("9:16") : m_request.aspectRatio},
        {QStringLiteral("output_format"), QStringLiteral("png")},
    };
    if (!m_request.referenceImageDataUri.isEmpty())
        input.insert(QStringLiteral("image_prompt"), m_request.referenceImageDataUri);

    submitReplicate(m_request.apiKey, m_request.model, input,
                    [this](const QJsonObject &prediction) {
                        const QString url = replicateOutputUrl(prediction);
                        if (url.isEmpty()) {
                            fail(tr("Replicate returned no image."));
                            return;
                        }
                        download(QUrl(url),
                                 [this, url](const QByteArray &data, const QString &contentType) {
                                     deliver(data, http::guessExtension(url, contentType,
                                                                        QStringLiteral("png")));
                                 });
                    });
}
