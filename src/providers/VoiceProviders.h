#pragma once

#include "ProviderTask.h"
#include "Types.h"

// Voice-over. Result: { data: QByteArray, extension: "mp3" }.
class VoiceTask : public HttpTask
{
    Q_OBJECT

public:
    explicit VoiceTask(const prov::VoiceRequest &request, QObject *parent = nullptr);

protected:
    prov::VoiceRequest m_request;
};

class ElevenLabsVoiceTask : public VoiceTask
{
    Q_OBJECT
public:
    using VoiceTask::VoiceTask;

protected:
    void start() override;
};

class OpenAiVoiceTask : public VoiceTask
{
    Q_OBJECT
public:
    using VoiceTask::VoiceTask;

protected:
    void start() override;
};

// Subtitles. Result: { srt: QString }.
class WhisperCaptionTask : public HttpTask
{
    Q_OBJECT

public:
    explicit WhisperCaptionTask(const prov::TranscribeRequest &request, QObject *parent = nullptr);

protected:
    void start() override;

private:
    prov::TranscribeRequest m_request;
};

// Voice pickers. Result: { voices: [ {id, label, description} ] }.
class ElevenLabsVoiceListTask : public HttpTask
{
    Q_OBJECT

public:
    explicit ElevenLabsVoiceListTask(const QString &apiKey, QObject *parent = nullptr);

protected:
    void start() override;

private:
    QString m_apiKey;
};

class OpenAiVoiceListTask : public ProviderTask
{
    Q_OBJECT

public:
    explicit OpenAiVoiceListTask(QObject *parent = nullptr);

protected:
    void start() override;
};
