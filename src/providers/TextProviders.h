#pragma once

#include "ProviderTask.h"
#include "Types.h"

// Script writers.
//
// All of them return the same shape:
//   { hook, script, caption, shots, inputTokens, outputTokens }
// so the pipeline never has to know which LLM produced it. `shots` is a list of
// { line, imagePrompt, videoPrompt } -- one camera setup each, in order, and
// their lines joined back together are `script`. The token counts are what the
// provider billed and feed the run's cost report; they are 0 when the answer
// carried no usage block.
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
    void deliver(const QString &rawText, int inputTokens = 0, int outputTokens = 0);

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
