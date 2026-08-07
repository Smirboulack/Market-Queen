#pragma once

#include "ProviderTask.h"
#include "Types.h"

#include <QSize>

// Image-to-video providers: they animate the opening frame.
// Result: { data: QByteArray, extension: "mp4" }.
class VideoTask : public HttpTask
{
    Q_OBJECT

public:
    explicit VideoTask(const prov::VideoRequest &request, QObject *parent = nullptr);

protected:
    void deliverFromUrl(const QString &url);

    prov::VideoRequest m_request;
};

class FalVideoTask : public VideoTask
{
    Q_OBJECT
public:
    using VideoTask::VideoTask;

protected:
    void start() override;
};

class ReplicateVideoTask : public VideoTask
{
    Q_OBJECT
public:
    using VideoTask::VideoTask;

protected:
    void start() override;
};

// OpenAI Sora, through the /v1/videos endpoint. Unlike the queue platforms it
// wants the reference frame at exactly the output resolution, so the opening
// frame is rescaled before upload.
class SoraVideoTask : public VideoTask
{
    Q_OBJECT
public:
    using VideoTask::VideoTask;

protected:
    void start() override;

private:
    void pollJob(const QString &videoId);
    void fetchContent(const QString &videoId);

    QSize m_outputSize;
};
