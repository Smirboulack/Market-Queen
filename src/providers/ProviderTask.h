#pragma once

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QVariantMap>

#include <functional>

class QNetworkReply;
class QNetworkRequest;
class QHttpMultiPart;
class QUrl;

// One in-flight provider operation.
//
// Every provider call returns a task instead of a value: the API calls are slow
// (a video generation is minutes) and must never block the UI thread. The task
// emits exactly one of succeeded()/failed(), then deletes itself.
class ProviderTask : public QObject
{
    Q_OBJECT

public:
    explicit ProviderTask(QObject *parent = nullptr);

    bool isFinished() const { return m_finished; }
    bool isCancelled() const { return m_cancelled; }

    // Subclasses must call the base implementation.
    virtual void cancel();

protected:
    // Called on the next event loop turn, so the caller has time to connect to
    // the signals before anything can be emitted.
    virtual void start() = 0;

signals:
    void progress(const QString &message);
    void succeeded(const QVariantMap &result);
    void failed(const QString &error);

protected:
    void report(const QString &message);
    // Guard for providers that need a key: fails the task with a clear message.
    bool requireKey(const QString &apiKey, const QString &providerLabel);
    void succeed(const QVariantMap &result);
    void fail(const QString &error);

    bool m_cancelled = false;
    bool m_finished = false;
};

// Base class for the HTTP-backed providers: request helpers, uniform error
// reporting, cancellation, and long-poll support for queue-based APIs.
class HttpTask : public ProviderTask
{
    Q_OBJECT

public:
    explicit HttpTask(QObject *parent = nullptr);

    void cancel() override;

protected:
    using JsonHandler = std::function<void(const QJsonObject &)>;
    using BytesHandler = std::function<void(const QByteArray &, const QString &contentType)>;

    enum class PollState { Pending, Done, Failed };
    using PollCheck = std::function<PollState(const QJsonObject &, QString *error)>;

    void postJson(const QNetworkRequest &request, const QJsonObject &body, JsonHandler onSuccess);
    void getJson(const QNetworkRequest &request, JsonHandler onSuccess);
    void postJsonForBytes(const QNetworkRequest &request, const QJsonObject &body,
                          BytesHandler onSuccess);
    void postMultipartForText(const QNetworkRequest &request, QHttpMultiPart *parts,
                              BytesHandler onSuccess);
    void download(const QUrl &url, BytesHandler onSuccess);

    // Polls `url` until `check` reports Done or Failed, or the deadline passes.
    void pollUntil(const QUrl &url, const QVariantMap &headers, PollCheck check,
                   JsonHandler onDone, int intervalMs = 3000, int timeoutMs = 900'000);

    // ---- Queue-based platforms ------------------------------------------
    // fal.ai and Replicate both work the same way: submit a job, poll a status
    // url, then read the payload. Images and video share this code.

    // Calls back with the completed fal payload, e.g. {"images":[{"url":...}]}.
    void submitFal(const QString &apiKey, const QString &modelId, const QJsonObject &input,
                   JsonHandler onResult);

    // Accepts "owner/name" or "owner/name:version"; calls back with the
    // succeeded prediction object.
    void submitReplicate(const QString &apiToken, const QString &model, const QJsonObject &input,
                         JsonHandler onResult);

    // First http(s) url in a Replicate `output` (string, array or object).
    static QString replicateOutputUrl(const QJsonObject &prediction);

    static QString jsonPath(const QJsonObject &root, const QString &dottedPath);

private:
    void track(QNetworkReply *reply);
    void handleReply(QNetworkReply *reply, bool wantJson, JsonHandler onJson,
                     BytesHandler onBytes);

    QList<QPointer<QNetworkReply>> m_replies;
};
