#include "Http.h"

#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonValue>
#include <QMimeDatabase>
#include <QNetworkReply>
#include <QUrl>

namespace http {

QNetworkAccessManager *manager()
{
    static QNetworkAccessManager *mgr = [] {
        auto *m = new QNetworkAccessManager;
        m->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
        return m;
    }();
    return mgr;
}

QNetworkRequest jsonRequest(const QUrl &url, const QVariantMap &headers)
{
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "SuperInfinity/" APP_VERSION);
    req.setTransferTimeout(120'000);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it)
        req.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());
    return req;
}

QString extractApiError(const QByteArray &body)
{
    const QJsonDocument doc = QJsonDocument::fromJson(body);
    if (!doc.isObject())
        return {};

    const QJsonObject obj = doc.object();

    // {"error": {"message": "..."}} - OpenAI, Anthropic, Google
    const QJsonValue error = obj.value(QStringLiteral("error"));
    if (error.isObject()) {
        const QJsonObject eo = error.toObject();
        for (const auto &key : {"message", "detail", "type"}) {
            const QString v = eo.value(QLatin1String(key)).toString();
            if (!v.isEmpty())
                return v;
        }
    }
    if (error.isString())
        return error.toString();

    // {"detail": "..."} or {"detail": [{"msg": "..."}]} - fal, Replicate
    const QJsonValue detail = obj.value(QStringLiteral("detail"));
    if (detail.isString())
        return detail.toString();
    if (detail.isArray() && !detail.toArray().isEmpty()) {
        const QJsonObject first = detail.toArray().first().toObject();
        const QString msg = first.value(QStringLiteral("msg")).toString();
        if (!msg.isEmpty())
            return msg;
    }

    for (const auto &key : {"message", "title"}) {
        const QString v = obj.value(QLatin1String(key)).toString();
        if (!v.isEmpty())
            return v;
    }
    return {};
}

QString describeError(QNetworkReply *reply, const QByteArray &body)
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QString apiMessage = extractApiError(body);

    QString base;
    if (status > 0)
        base = QStringLiteral("HTTP %1").arg(status);
    else
        base = reply->errorString();

    if (!apiMessage.isEmpty())
        return QStringLiteral("%1 - %2").arg(base, apiMessage.simplified());

    if (status > 0 && !body.isEmpty())
        return QStringLiteral("%1 - %2").arg(base, QString::fromUtf8(body.left(400)).simplified());

    return base;
}

QString imageToDataUri(const QString &path, int maxBytes)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};

    QByteArray data = file.readAll();
    file.close();

    QString mime = QMimeDatabase().mimeTypeForFile(path).name();
    if (!mime.startsWith(QLatin1String("image/")))
        mime = QStringLiteral("image/png");

    if (data.size() > maxBytes) {
        QImage image;
        if (image.loadFromData(data)) {
            if (image.width() > 2048 || image.height() > 2048)
                image = image.scaled(2048, 2048, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            QByteArray recompressed;
            QBuffer buffer(&recompressed);
            buffer.open(QIODevice::WriteOnly);
            if (image.save(&buffer, "JPEG", 88) && !recompressed.isEmpty()) {
                data = recompressed;
                mime = QStringLiteral("image/jpeg");
            }
        }
    }

    return QStringLiteral("data:%1;base64,%2").arg(mime, QString::fromLatin1(data.toBase64()));
}

QByteArray dataUriPayload(const QString &uri, QString *mimeType)
{
    if (!uri.startsWith(QLatin1String("data:")))
        return {};
    const int comma = uri.indexOf(QLatin1Char(','));
    if (comma < 0)
        return {};
    if (mimeType) {
        const int semicolon = uri.indexOf(QLatin1Char(';'));
        const int end = (semicolon > 0 && semicolon < comma) ? semicolon : comma;
        *mimeType = uri.mid(5, end - 5);
    }
    return QByteArray::fromBase64(uri.mid(comma + 1).toLatin1());
}

QString guessExtension(const QString &url, const QString &contentType, const QString &fallback)
{
    const QString suffix = QFileInfo(QUrl(url).path()).suffix().toLower();
    static const QStringList known = {"png",  "jpg", "jpeg", "webp", "gif",
                                      "mp4",  "mov", "webm", "mp3",  "wav",
                                      "m4a",  "ogg", "flac"};
    if (known.contains(suffix))
        return suffix;

    const QString ct = contentType.section(QLatin1Char(';'), 0, 0).trimmed().toLower();
    static const QHash<QString, QString> byMime = {
        {"image/png", "png"},        {"image/jpeg", "jpg"},  {"image/webp", "webp"},
        {"video/mp4", "mp4"},        {"video/webm", "webm"}, {"video/quicktime", "mov"},
        {"audio/mpeg", "mp3"},       {"audio/mp3", "mp3"},   {"audio/wav", "wav"},
        {"audio/x-wav", "wav"},      {"audio/mp4", "m4a"},   {"audio/ogg", "ogg"},
    };
    return byMime.value(ct, fallback);
}

} // namespace http
