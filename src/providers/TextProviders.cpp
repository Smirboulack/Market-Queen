#include "TextProviders.h"

#include "core/Http.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

namespace {

// Roughly 2.6 spoken words per second for an energetic UGC read.
int targetWordCount(int seconds)
{
    return qBound(20, int(seconds * 2.6), 400);
}

QString sectionIfSet(const QString &label, const QString &value)
{
    return value.trimmed().isEmpty() ? QString()
                                     : QStringLiteral("%1: %2\n").arg(label, value.trimmed());
}

// Models like to answer with ```json ... ``` or with a sentence before the
// object. Pull out the first balanced JSON object instead of failing.
QJsonObject extractJsonObject(const QString &text)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8(), &error);
    if (doc.isObject())
        return doc.object();

    const int start = text.indexOf(QLatin1Char('{'));
    if (start < 0)
        return {};

    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < text.size(); ++i) {
        const QChar c = text.at(i);
        if (inString) {
            if (escaped)
                escaped = false;
            else if (c == QLatin1Char('\\'))
                escaped = true;
            else if (c == QLatin1Char('"'))
                inString = false;
            continue;
        }
        if (c == QLatin1Char('"'))
            inString = true;
        else if (c == QLatin1Char('{'))
            ++depth;
        else if (c == QLatin1Char('}')) {
            if (--depth == 0) {
                doc = QJsonDocument::fromJson(text.mid(start, i - start + 1).toUtf8(), &error);
                return doc.object();
            }
        }
    }
    return {};
}

} // namespace

ScriptTask::ScriptTask(const prov::ScriptRequest &request, QObject *parent)
    : HttpTask(parent)
    , m_request(request)
{
}

QString ScriptTask::systemPrompt() const
{
    return QStringLiteral(
        "You are a senior UGC (user generated content) ad writer. You write short "
        "vertical video ads that look like a real person filmed themselves, not like "
        "a brand commercial.\n"
        "\n"
        "Rules for the spoken script:\n"
        "- Open with a scroll-stopping hook in the first 3 seconds.\n"
        "- Sound like a real person talking to a friend: contractions, short sentences, "
        "one idea per sentence.\n"
        "- No stage directions, no emojis, no hashtags, no markdown, no quotation marks.\n"
        "- Only words that will be spoken out loud.\n"
        "- End with one clear, casual call to action.\n"
        "\n"
        "The ad is cut into shots. Each shot is one camera setup that stays on screen "
        "for about five seconds while its line is spoken. Consecutive shots must look "
        "clearly different -- change the angle, the framing or what is in the frame -- "
        "but keep the same person, the same product and the same place throughout.\n"
        "\n"
        "Answer with a single JSON object and nothing else, using exactly these keys:\n"
        "{\n"
        "  \"hook\": \"the first spoken line, under 15 words\",\n"
        "  \"caption\": \"a short on-screen title, under 8 words\",\n"
        "  \"shots\": [\n"
        "    {\n"
        "      \"line\": \"the words spoken while this shot is on screen\",\n"
        "      \"imagePrompt\": \"a photographic prompt for this shot: the person, their "
        "expression, how they hold the product, the framing, the room, the lighting and "
        "the phone-camera look\",\n"
        "      \"videoPrompt\": \"how this shot should move over its few seconds: subtle "
        "handheld camera, small natural gestures\"\n"
        "    }\n"
        "  ]\n"
        "}");
}

QString ScriptTask::userPrompt() const
{
    const int words = targetWordCount(m_request.durationSeconds);

    QString prompt;
    prompt += sectionIfSet(QStringLiteral("Product"), m_request.productName);
    prompt += sectionIfSet(QStringLiteral("What it is"), m_request.productDescription);
    prompt += sectionIfSet(QStringLiteral("Target audience"), m_request.audience);
    prompt += sectionIfSet(QStringLiteral("Tone"), m_request.tone);
    prompt += sectionIfSet(QStringLiteral("Person on camera"), m_request.avatarBrief);
    prompt += sectionIfSet(QStringLiteral("Extra instructions"), m_request.extraInstructions);

    prompt += QStringLiteral("Language: %1\n")
                  .arg(m_request.language.isEmpty() ? QStringLiteral("English")
                                                    : m_request.language);
    prompt += QStringLiteral("Target length: about %1 seconds, so roughly %2 spoken words.\n")
                  .arg(m_request.durationSeconds)
                  .arg(words);
    prompt += QStringLiteral("Write it as exactly %1 shots, so about %2 words per shot. "
                             "Split the script where the thought changes, not mid-sentence.\n")
                  .arg(m_request.shotCount)
                  .arg(qMax(1, words / qMax(1, m_request.shotCount)));

    if (!m_request.referenceImageDataUri.isEmpty()) {
        prompt += QStringLiteral(
            "\nA photo of the product is attached. Describe the real product accurately in "
            "imagePrompt: same shape, same colours, same label.\n");
    }

    prompt += QStringLiteral("\nWrite the ad now. JSON only.");
    return prompt;
}

void ScriptTask::deliver(const QString &rawText, int inputTokens, int outputTokens)
{
    if (rawText.trimmed().isEmpty()) {
        fail(tr("The model returned an empty answer."));
        return;
    }

    const QJsonObject obj = extractJsonObject(rawText);

    QVariantList shots;
    QStringList lines;
    for (const QJsonValue &value : obj.value(QStringLiteral("shots")).toArray()) {
        const QJsonObject shot = value.toObject();
        const QString line = shot.value(QStringLiteral("line")).toString().trimmed();
        if (line.isEmpty())
            continue;
        lines << line;
        shots.append(QVariantMap{
            {QStringLiteral("line"), line},
            {QStringLiteral("imagePrompt"),
             shot.value(QStringLiteral("imagePrompt")).toString().trimmed()},
            {QStringLiteral("videoPrompt"),
             shot.value(QStringLiteral("videoPrompt")).toString().trimmed()},
        });
    }

    QString script = lines.join(QLatin1Char(' '));

    // Some models answer in the shape we asked for before shots existed, and a
    // model that ignored the JSON instruction altogether still gave us usable
    // copy. Both become a single shot rather than a failed run; the pipeline
    // splits it up afterwards.
    if (shots.isEmpty()) {
        script = obj.value(QStringLiteral("script")).toString().trimmed();
        if (script.isEmpty() && obj.isEmpty())
            script = rawText.trimmed();
        if (!script.isEmpty()) {
            shots.append(QVariantMap{
                {QStringLiteral("line"), script},
                {QStringLiteral("imagePrompt"),
                 obj.value(QStringLiteral("imagePrompt")).toString().trimmed()},
                {QStringLiteral("videoPrompt"),
                 obj.value(QStringLiteral("videoPrompt")).toString().trimmed()},
            });
        }
    }

    if (script.isEmpty()) {
        fail(tr("The model answer did not contain a script."));
        return;
    }

    QString hook = obj.value(QStringLiteral("hook")).toString().trimmed();
    if (hook.isEmpty())
        hook = script.section(QRegularExpression(QStringLiteral("[.!?]")), 0, 0).trimmed();

    succeed({
        {QStringLiteral("hook"), hook},
        {QStringLiteral("script"), script},
        {QStringLiteral("shots"), shots},
        {QStringLiteral("caption"), obj.value(QStringLiteral("caption")).toString().trimmed()},
        {QStringLiteral("inputTokens"), inputTokens},
        {QStringLiteral("outputTokens"), outputTokens},
    });
}

// ---------------------------------------------------------------------------
// OpenAI - POST /v1/chat/completions
// ---------------------------------------------------------------------------
void OpenAiScriptTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("OpenAI")))
        return;

    report(tr("Writing the script with %1...").arg(m_request.model));

    const QString base = m_request.baseUrl.isEmpty()
        ? QStringLiteral("https://api.openai.com/v1")
        : m_request.baseUrl;

    QJsonArray userContent;
    userContent.append(QJsonObject{{QStringLiteral("type"), QStringLiteral("text")},
                                   {QStringLiteral("text"), userPrompt()}});
    if (!m_request.referenceImageDataUri.isEmpty()) {
        userContent.append(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("image_url")},
            {QStringLiteral("image_url"),
             QJsonObject{{QStringLiteral("url"), m_request.referenceImageDataUri}}}});
    }

    const QJsonArray messages{
        QJsonObject{{QStringLiteral("role"), QStringLiteral("system")},
                    {QStringLiteral("content"), systemPrompt()}},
        QJsonObject{{QStringLiteral("role"), QStringLiteral("user")},
                    {QStringLiteral("content"), userContent}},
    };

    const QJsonObject body{
        {QStringLiteral("model"), m_request.model},
        {QStringLiteral("messages"), messages},
        {QStringLiteral("response_format"),
         QJsonObject{{QStringLiteral("type"), QStringLiteral("json_object")}}},
    };

    const QNetworkRequest request = http::jsonRequest(
        QUrl(base + QStringLiteral("/chat/completions")),
        {{QStringLiteral("Authorization"), QStringLiteral("Bearer ") + m_request.apiKey}});

    postJson(request, body, [this](const QJsonObject &response) {
        const QJsonObject usage = response.value(QStringLiteral("usage")).toObject();
        deliver(jsonPath(response, QStringLiteral("choices.0.message.content")),
                usage.value(QStringLiteral("prompt_tokens")).toInt(),
                usage.value(QStringLiteral("completion_tokens")).toInt());
    });
}

// ---------------------------------------------------------------------------
// Anthropic - POST /v1/messages
// ---------------------------------------------------------------------------
void AnthropicScriptTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("Anthropic")))
        return;

    report(tr("Writing the script with %1...").arg(m_request.model));

    QJsonArray content;
    if (!m_request.referenceImageDataUri.isEmpty()) {
        // data:image/png;base64,AAAA -> media type + payload
        const QString uri = m_request.referenceImageDataUri;
        const int comma = uri.indexOf(QLatin1Char(','));
        const QString mediaType = uri.mid(5, uri.indexOf(QLatin1Char(';')) - 5);
        if (comma > 0 && !mediaType.isEmpty()) {
            content.append(QJsonObject{
                {QStringLiteral("type"), QStringLiteral("image")},
                {QStringLiteral("source"),
                 QJsonObject{{QStringLiteral("type"), QStringLiteral("base64")},
                             {QStringLiteral("media_type"), mediaType},
                             {QStringLiteral("data"), uri.mid(comma + 1)}}}});
        }
    }
    content.append(QJsonObject{{QStringLiteral("type"), QStringLiteral("text")},
                               {QStringLiteral("text"), userPrompt()}});

    const QJsonObject body{
        {QStringLiteral("model"), m_request.model},
        {QStringLiteral("max_tokens"), 2000},
        {QStringLiteral("system"), systemPrompt()},
        {QStringLiteral("messages"),
         QJsonArray{QJsonObject{{QStringLiteral("role"), QStringLiteral("user")},
                                {QStringLiteral("content"), content}}}},
    };

    const QNetworkRequest request = http::jsonRequest(
        QUrl(QStringLiteral("https://api.anthropic.com/v1/messages")),
        {{QStringLiteral("x-api-key"), m_request.apiKey},
         {QStringLiteral("anthropic-version"), QStringLiteral("2023-06-01")}});

    postJson(request, body, [this](const QJsonObject &response) {
        const QJsonObject usage = response.value(QStringLiteral("usage")).toObject();
        const int in = usage.value(QStringLiteral("input_tokens")).toInt();
        const int out = usage.value(QStringLiteral("output_tokens")).toInt();

        // Skip any leading thinking blocks and take the first text block.
        const QJsonArray blocks = response.value(QStringLiteral("content")).toArray();
        for (const QJsonValue &block : blocks) {
            const QJsonObject o = block.toObject();
            if (o.value(QStringLiteral("type")).toString() == QLatin1String("text")) {
                deliver(o.value(QStringLiteral("text")).toString(), in, out);
                return;
            }
        }
        deliver({}, in, out);
    });
}

// ---------------------------------------------------------------------------
// Google Gemini - POST /v1beta/models/{model}:generateContent
// ---------------------------------------------------------------------------
void GeminiScriptTask::start()
{
    if (!requireKey(m_request.apiKey, QStringLiteral("Google Gemini")))
        return;

    report(tr("Writing the script with %1...").arg(m_request.model));

    QJsonArray parts;
    parts.append(QJsonObject{{QStringLiteral("text"), userPrompt()}});
    if (!m_request.referenceImageDataUri.isEmpty()) {
        const QString uri = m_request.referenceImageDataUri;
        const int comma = uri.indexOf(QLatin1Char(','));
        const QString mimeType = uri.mid(5, uri.indexOf(QLatin1Char(';')) - 5);
        if (comma > 0 && !mimeType.isEmpty()) {
            parts.append(QJsonObject{
                {QStringLiteral("inline_data"),
                 QJsonObject{{QStringLiteral("mime_type"), mimeType},
                             {QStringLiteral("data"), uri.mid(comma + 1)}}}});
        }
    }

    const QJsonObject body{
        {QStringLiteral("contents"),
         QJsonArray{QJsonObject{{QStringLiteral("role"), QStringLiteral("user")},
                                {QStringLiteral("parts"), parts}}}},
        {QStringLiteral("systemInstruction"),
         QJsonObject{{QStringLiteral("parts"),
                      QJsonArray{QJsonObject{{QStringLiteral("text"), systemPrompt()}}}}}},
        {QStringLiteral("generationConfig"),
         QJsonObject{{QStringLiteral("responseMimeType"), QStringLiteral("application/json")}}},
    };

    const QUrl url(QStringLiteral("https://generativelanguage.googleapis.com/v1beta/models/%1:"
                                  "generateContent")
                       .arg(m_request.model));
    const QNetworkRequest request =
        http::jsonRequest(url, {{QStringLiteral("x-goog-api-key"), m_request.apiKey}});

    postJson(request, body, [this](const QJsonObject &response) {
        const QJsonObject usage = response.value(QStringLiteral("usageMetadata")).toObject();
        deliver(jsonPath(response, QStringLiteral("candidates.0.content.parts.0.text")),
                usage.value(QStringLiteral("promptTokenCount")).toInt(),
                usage.value(QStringLiteral("candidatesTokenCount")).toInt());
    });
}
