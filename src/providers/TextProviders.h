#pragma once

#include "ProviderTask.h"
#include "Types.h"

// Script writers.
//
// All of them return the same shape:
//   { hook, script, imagePrompt, videoPrompt, caption }
// so the pipeline never has to know which LLM produced it.
class ScriptTask : public HttpTask
{
    Q_OBJECT

public:
    explicit ScriptTask(const prov::ScriptRequest &request, QObject *parent = nullptr);

protected:
    QString systemPrompt() const;
    QString userPrompt() const;

    // Parses the model's answer (tolerating markdown fences and stray prose)
    // and completes the task.
    void deliver(const QString &rawText);

    prov::ScriptRequest m_request;
};

class OpenAiScriptTask : public ScriptTask
{
    Q_OBJECT
public:
    using ScriptTask::ScriptTask;

protected:
    void start() override;
};

class AnthropicScriptTask : public ScriptTask
{
    Q_OBJECT
public:
    using ScriptTask::ScriptTask;

protected:
    void start() override;
};

class GeminiScriptTask : public ScriptTask
{
    Q_OBJECT
public:
    using ScriptTask::ScriptTask;

protected:
    void start() override;
};
