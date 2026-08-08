#include "ProviderTask.h"

#include "core/Http.h"

#include <QDateTime>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QNetworkReply>
#include <QTimer>
#include <QUrl>

ProviderTask::ProviderTask(QObject *parent)
    : QObject(parent)
{
    QMetaObject::invokeMethod(
        this,
        [this]() {
            if (!m_finished && !m_cancelled)
                start();
        },
        Qt::QueuedConnection);
}

bool ProviderTask::requireKey(const QString &apiKey, const QString &providerLabel)
{
    if (!apiKey.isEmpty())
        return true;
    fail(tr("No API key for %1. Add it in Settings.").arg(providerLabel));
    return false;
}

void ProviderTask::cancel()
{
    if (m_finished)
        return;
    m_cancelled = true;
    m_finished = true;
    emit failed(tr("Cancelled."));
    deleteLater();
}

void ProviderTask::report(const QString &message)
{
    if (!m_finished && !message.isEmpty())
        emit progress(message);
}

void ProviderTask::succeed(const QVariantMap &result)
{
    if (m_finished)
        return;
    m_finished = true;
    emit succeeded(result);
    deleteLater();
}

void ProviderTask::fail(const QString &error)
{
    if (m_finished)
        return;
    m_finished = true;
    emit failed(error);
    deleteLater();
}

HttpTask::HttpTask(QObject *parent)
    : ProviderTask(parent)
{
}

void HttpTask::cancel()
{
    for (const QPointer<QNetworkReply> &reply : std::as_const(m_replies)) {
        if (reply)
            reply->abort();
    }
    m_replies.clear();
    ProviderTask::cancel();
}

void HttpTask::track(QNetworkReply *reply)
{
    m_replies.append(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        m_replies.removeAll(reply);
    });
}

void HttpTask::handleReply(QNetworkReply *reply, bool wantJson, JsonHandler onJson,
                           BytesHandler onBytes)
{
    track(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, wantJson, onJson, onBytes]() {
        reply->deleteLater();
        if (isCancelled() || isFinished())
            return;

        const QByteArray body = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        if (reply->error() != QNetworkReply::NoError || status >= 400) {
            fail(http::describeError(reply, body));
            return;
        }

        if (wantJson) {
            QJsonParseError parseError;
            const QJsonDocument doc = QJsonDocument::fromJson(body, &parseError);
            if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
                fail(tr("Unexpected response from the API: %1")
                         .arg(QString::fromUtf8(body.left(200)).simplified()));
                return;
            }
            if (onJson)
                onJson(doc.object());
        } else if (onBytes) {
            onBytes(body, reply->header(QNetworkRequest::ContentTypeHeader).toString());
        }
    });
}

void HttpTask::postJson(const QNetworkRequest &request, const QJsonObject &body,
                        JsonHandler onSuccess)
{
    QNetworkReply *reply = http::manager()->post(
        request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply, true, std::move(onSuccess), nullptr);
}

void HttpTask::getJson(const QNetworkRequest &request, JsonHandler onSuccess)
{
    handleReply(http::manager()->get(request), true, std::move(onSuccess), nullptr);
}

void HttpTask::postJsonForBytes(const QNetworkRequest &request, const QJsonObject &body,
                                BytesHandler onSuccess)
{
    QNetworkReply *reply = http::manager()->post(
        request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply, false, nullptr, std::move(onSuccess));
}

void HttpTask::postMultipartForText(const QNetworkRequest &request, QHttpMultiPart *parts,
                                    BytesHandler onSuccess)
{
    QNetworkReply *reply = http::manager()->post(request, parts);
    parts->setParent(reply);
    handleReply(reply, false, nullptr, std::move(onSuccess));
}

void HttpTask::getBytes(const QNetworkRequest &request, BytesHandler onSuccess)
{
    QNetworkRequest copy = request;
    copy.setTransferTimeout(300'000);

    QNetworkReply *reply = http::manager()->get(copy);
    connect(reply, &QNetworkReply::downloadProgress, this,
            [this](qint64 received, qint64 total) {
                if (total > 0)
                    report(tr("Downloading... %1%").arg(received * 100 / total));
            });
    handleReply(reply, false, nullptr, std::move(onSuccess));
}

void HttpTask::download(const QUrl &url, BytesHandler onSuccess)
{
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "MarketQueen/" APP_VERSION);
    request.setTransferTimeout(300'000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *reply = http::manager()->get(request);
    connect(reply, &QNetworkReply::downloadProgress, this,
            [this](qint64 received, qint64 total) {
                if (total > 0)
                    report(tr("Downloading... %1%").arg(received * 100 / total));
            });
    handleReply(reply, false, nullptr, std::move(onSuccess));
}

void HttpTask::pollUntil(const QUrl &url, const QVariantMap &headers, PollCheck check,
                         JsonHandler onDone, int intervalMs, int timeoutMs)
{
    const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + timeoutMs;

    // Recursive lambda through a shared_ptr so each tick can schedule the next.
    auto tick = std::make_shared<std::function<void()>>();
    *tick = [this, url, headers, check, onDone, intervalMs, deadline, tick]() {
        if (isCancelled() || isFinished())
            return;

        if (QDateTime::currentMSecsSinceEpoch() > deadline) {
            fail(tr("The provider did not return a result in time."));
            return;
        }

        getJson(http::jsonRequest(url, headers), [this, check, onDone, intervalMs, tick](
                                                     const QJsonObject &obj) {
            QString error;
            switch (check(obj, &error)) {
            case PollState::Done:
                if (onDone)
                    onDone(obj);
                return;
            case PollState::Failed:
                fail(error.isEmpty() ? tr("The generation failed.") : error);
                return;
            case PollState::Pending:
                QTimer::singleShot(intervalMs, this, [tick]() { (*tick)(); });
                return;
            }
        });
    };

    (*tick)();
}

void HttpTask::submitFal(const QString &apiKey, const QString &modelId, const QJsonObject &input,
                         JsonHandler onResult)
{
    const QVariantMap headers{
        {QStringLiteral("Authorization"), QStringLiteral("Key ") + apiKey}};
    const QUrl submitUrl(QStringLiteral("https://queue.fal.run/") + modelId);

    report(tr("Queued on fal.ai (%1)...").arg(modelId));

    postJson(http::jsonRequest(submitUrl, headers), input,
             [this, headers, onResult](const QJsonObject &queued) {
                 const QString statusUrl = queued.value(QStringLiteral("status_url")).toString();
                 const QString responseUrl =
                     queued.value(QStringLiteral("response_url")).toString();
                 if (statusUrl.isEmpty() || responseUrl.isEmpty()) {
                     fail(tr("fal.ai did not return a job handle."));
                     return;
                 }

                 pollUntil(
                     QUrl(statusUrl), headers,
                     [this](const QJsonObject &status, QString *error) {
                         const QString state = status.value(QStringLiteral("status")).toString();
                         if (state == QLatin1String("COMPLETED"))
                             return PollState::Done;
                         if (state == QLatin1String("IN_QUEUE")) {
                             const int position =
                                 status.value(QStringLiteral("queue_position")).toInt(-1);
                             report(position >= 0 ? tr("Waiting in queue (position %1)...")
                                                        .arg(position)
                                                  : tr("Waiting in queue..."));
                             return PollState::Pending;
                         }
                         if (state == QLatin1String("IN_PROGRESS")) {
                             report(tr("Generating..."));
                             return PollState::Pending;
                         }
                         *error = tr("fal.ai reported status \"%1\".").arg(state);
                         return PollState::Failed;
                     },
                     [this, headers, responseUrl, onResult](const QJsonObject &) {
                         getJson(http::jsonRequest(QUrl(responseUrl), headers),
                                 [onResult](const QJsonObject &result) {
                                     if (onResult)
                                         onResult(result);
                                 });
                     });
             });
}

void HttpTask::submitReplicate(const QString &apiToken, const QString &model,
                               const QJsonObject &input, JsonHandler onResult)
{
    const QVariantMap headers{
        {QStringLiteral("Authorization"), QStringLiteral("Bearer ") + apiToken}};

    QUrl submitUrl;
    QJsonObject body{{QStringLiteral("input"), input}};

    const int colon = model.indexOf(QLatin1Char(':'));
    if (colon > 0) {
        submitUrl = QUrl(QStringLiteral("https://api.replicate.com/v1/predictions"));
        body.insert(QStringLiteral("version"), model.mid(colon + 1));
    } else {
        submitUrl = QUrl(QStringLiteral("https://api.replicate.com/v1/models/%1/predictions")
                             .arg(model));
    }

    report(tr("Submitting to Replicate (%1)...").arg(model));

    postJson(http::jsonRequest(submitUrl, headers), body,
             [this, headers, onResult](const QJsonObject &prediction) {
                 const QString statusUrl =
                     prediction.value(QStringLiteral("urls")).toObject()
                         .value(QStringLiteral("get")).toString();
                 if (statusUrl.isEmpty()) {
                     fail(tr("Replicate did not return a prediction url."));
                     return;
                 }

                 pollUntil(
                     QUrl(statusUrl), headers,
                     [this](const QJsonObject &status, QString *error) {
                         const QString state = status.value(QStringLiteral("status")).toString();
                         if (state == QLatin1String("succeeded"))
                             return PollState::Done;
                         if (state == QLatin1String("starting")
                             || state == QLatin1String("processing")) {
                             report(state == QLatin1String("starting") ? tr("Starting up...")
                                                                       : tr("Generating..."));
                             return PollState::Pending;
                         }
                         *error = status.value(QStringLiteral("error")).toString();
                         if (error->isEmpty())
                             *error = tr("Replicate reported status \"%1\".").arg(state);
                         return PollState::Failed;
                     },
                     [onResult](const QJsonObject &prediction) {
                         if (onResult)
                             onResult(prediction);
                     });
             });
}

QString HttpTask::replicateOutputUrl(const QJsonObject &prediction)
{
    const QJsonValue output = prediction.value(QStringLiteral("output"));

    const auto asUrl = [](const QJsonValue &value) -> QString {
        const QString s = value.toString();
        return s.startsWith(QLatin1String("http")) ? s : QString();
    };

    if (output.isString())
        return asUrl(output);

    if (output.isArray()) {
        // Last frame first: models that stream partial results append the
        // final asset at the end.
        const QJsonArray array = output.toArray();
        for (int i = array.size() - 1; i >= 0; --i) {
            const QString url = asUrl(array.at(i));
            if (!url.isEmpty())
                return url;
        }
    }

    if (output.isObject()) {
        const QJsonObject obj = output.toObject();
        for (const auto &key : {"video", "url", "image", "output", "audio"}) {
            const QString url = asUrl(obj.value(QLatin1String(key)));
            if (!url.isEmpty())
                return url;
        }
    }
    return {};
}

QString HttpTask::jsonPath(const QJsonObject &root, const QString &dottedPath)
{
    QJsonValue value = root;
    const QStringList parts = dottedPath.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        bool isIndex = false;
        const int index = part.toInt(&isIndex);
        if (isIndex && value.isArray()) {
            const QJsonArray array = value.toArray();
            if (index < 0 || index >= array.size())
                return {};
            value = array.at(index);
        } else if (value.isObject()) {
            value = value.toObject().value(part);
        } else {
            return {};
        }
    }
    return value.isString() ? value.toString() : QString();
}
