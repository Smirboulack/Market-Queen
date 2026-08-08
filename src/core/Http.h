#pragma once

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QString>

namespace http {

// One manager for the whole app: keeps connections alive between API calls.
QNetworkAccessManager *manager();

QNetworkRequest jsonRequest(const QUrl &url, const QVariantMap &headers = {});

// Human-readable error out of a finished reply, including the provider's own
// error body when there is one -- that message is usually what the user needs
// ("insufficient quota", "invalid api key", ...).
QString describeError(class QNetworkReply *reply, const QByteArray &body);

// Pulls the most common error shapes out of an API response body.
QString extractApiError(const QByteArray &body);

// Encodes a local image as a data: URI, re-compressing to JPEG when the file is
// large. Providers accept these in place of a hosted URL, which lets the app
// stay storage-free.
QString imageToDataUri(const QString &path, int maxBytes = 2 * 1024 * 1024);

// Encodes any local file as a data: URI, verbatim. Used for the few seconds of
// speech a talking shot is lip-synced to -- small enough that uploading it
// separately would only add a failure mode.
QString fileToDataUri(const QString &path, int maxBytes = 12 * 1024 * 1024);

QString guessExtension(const QString &url, const QString &contentType, const QString &fallback);

// Decodes "data:<mime>;base64,<payload>" back into raw bytes.
QByteArray dataUriPayload(const QString &uri, QString *mimeType = nullptr);

} // namespace http
