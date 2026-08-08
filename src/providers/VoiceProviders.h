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

// MiniMax, ElevenLabs, Kokoro and friends behind the fal key. Each engine names
// its inputs differently, so the request is shaped per family.
class FalVoiceTask : public VoiceTask
{
    Q_OBJECT
public:
    using VoiceTask::VoiceTask;

protected:
    void start() override;
};

// Instant voice cloning. Result: { voiceId: QString, name: QString }.
//
// This adds a permanent voice to the user's ElevenLabs account, which is why
// nothing in the pipeline ever calls it: only an explicit click does.
class ElevenLabsVoiceCloneTask : public HttpTask
{
    Q_OBJECT

public:
    explicit ElevenLabsVoiceCloneTask(const prov::VoiceCloneRequest &request,
                                      QObject *parent = nullptr);

protected:
    void start() override;

private:
    prov::VoiceCloneRequest m_request;
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

class FalVoiceListTask : public ProviderTask
{
    Q_OBJECT

public:
    explicit FalVoiceListTask(QObject *parent = nullptr);

protected:
    void start() override;
};
