#pragma once

#include "ProviderTask.h"
#include "Types.h"

// Talking shots: a still plus its audio in, a lip-synced clip out.
// Result: { data: QByteArray, extension: "mp4" }.
//
// Every other video provider in this app animates a picture and knows nothing
// about the words. These take the audio as an input, which is why the mouth
// matches -- and why the clip that comes back is exactly as long as the line,
// with no duration to ask for and no stretching to do afterwards.
class AvatarTask : public HttpTask
{
    Q_OBJECT

public:
    explicit AvatarTask(const prov::AvatarRequest &request, QObject *parent = nullptr);

protected:
    // Downloads the finished clip and completes the task.
    void deliverFromUrl(const QString &url);

    prov::AvatarRequest m_request;
};

class FalAvatarTask : public AvatarTask
{
    Q_OBJECT
public:
    using AvatarTask::AvatarTask;

protected:
    void start() override;
};
