#pragma once

#include "ProviderTask.h"
#include "Types.h"

// Image providers produce the opening frame of the ad.
// Result: { data: QByteArray, extension: "png" }.
class ImageTask : public HttpTask
{
    Q_OBJECT

public:
    explicit ImageTask(const prov::ImageRequest &request, QObject *parent = nullptr);

protected:
    void deliver(const QByteArray &data, const QString &extension);

    prov::ImageRequest m_request;
};

class OpenAiImageTask : public ImageTask
{
    Q_OBJECT
public:
    using ImageTask::ImageTask;

protected:
    void start() override;

private:
    void generate();
    void edit(); // gpt-image-1 with the user's product photo as reference
};

class FalImageTask : public ImageTask
{
    Q_OBJECT
public:
    using ImageTask::ImageTask;

protected:
    void start() override;
};

class ReplicateImageTask : public ImageTask
{
    Q_OBJECT
public:
    using ImageTask::ImageTask;

protected:
    void start() override;
};
