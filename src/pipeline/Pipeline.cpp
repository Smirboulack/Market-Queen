#include "Pipeline.h"

#include "core/Http.h"
#include "core/LogModel.h"
#include "core/Paths.h"
#include "core/Pricing.h"
#include "core/SettingsStore.h"
#include "media/Ffmpeg.h"
#include "providers/ProviderTask.h"
#include "providers/Registry.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSize>
#include <QUrl>

namespace {

// The voice-over is recorded before anything is drawn, because how long each
// shot is on screen is what decides the clip we have to buy for it.
enum StepIndex {
    StepScript = 0,
    StepVoice,
    StepFrames,
    StepVideos,
    StepCaptions,
    StepAssemble,
    StepCount,
};

constexpr const char *kCaptionsFile = "captions.srt";
constexpr const char *kFinalFile = "final.mp4";

// Burned-in captions, UGC style: bold white with a hard outline, sitting above
// the bottom UI of the social apps.
constexpr const char *kSubtitleStyle =
    "FontName=Arial,FontSize=22,Bold=1,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,"
    "BorderStyle=1,Outline=3,Shadow=0,Alignment=2,MarginV=90";

QString localPathFromUrlOrPath(const QString &value)
{
    if (value.startsWith(QLatin1String("file:")))
        return QUrl(value).toLocalFile();
    return value;
}

// One canvas for the whole ad. Shots come back from different models at
// different sizes, and concat will not join streams whose dimensions differ, so
// they all get padded onto this before being cut together.
QSize outputSize(const QString &aspectRatio)
{
    if (aspectRatio == QLatin1String("16:9"))
        return {1920, 1080};
    if (aspectRatio == QLatin1String("1:1"))
        return {1080, 1080};
    return {1080, 1920};
}

} // namespace

Pipeline::Pipeline(SettingsStore *settings, Registry *registry, Pricing *pricing, LogModel *log,
                   QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_registry(registry)
    , m_pricing(pricing)
    , m_log(log)
{
    // Show the plan before anything runs.
    resetSteps();
}

QString Pipeline::stepLabel(int index)
{
    switch (index) {
    case StepScript:
        return tr("Script");
    case StepVoice:
        return tr("Voice-over");
    case StepFrames:
        return tr("Frames");
    case StepVideos:
        return tr("Shots");
    case StepCaptions:
        return tr("Subtitles");
    case StepAssemble:
        return tr("Final cut");
    default:
        return {};
    }
}

void Pipeline::resetSteps()
{
    m_steps.clear();
    for (int i = 0; i < StepCount; ++i)
        m_steps.append({stepLabel(i), Pending, {}});
    emit stepsChanged();
    emit statusChanged();
}

void Pipeline::retranslate()
{
    for (int i = 0; i < m_steps.size(); ++i)
        m_steps[i].label = stepLabel(i);
    emit stepsChanged();
}

QVariantList Pipeline::steps() const
{
    QVariantList list;
    for (const Step &step : m_steps) {
        list.append(QVariantMap{
            {QStringLiteral("label"), step.label},
            {QStringLiteral("state"), int(step.state)},
            {QStringLiteral("detail"), step.detail},
        });
    }
    return list;
}

double Pipeline::progress() const
{
    if (m_steps.isEmpty())
        return 0.0;
    int settled = 0;
    for (const Step &step : m_steps) {
        if (step.state == Done || step.state == Skipped)
            ++settled;
    }
    return double(settled) / double(m_steps.size());
}

void Pipeline::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void Pipeline::setStepState(int index, StepState state, const QString &detail)
{
    if (index < 0 || index >= m_steps.size())
        return;
    m_steps[index].state = state;
    if (!detail.isEmpty())
        m_steps[index].detail = detail;
    emit stepsChanged();
    emit statusChanged(); // progress() depends on the step states
}

void Pipeline::start(const QVariantMap &request)
{
    if (m_running)
        return;

    m_request = request;
    m_run = RunState{};
    m_shotLabel.clear();

    resetSteps();
    setStatus({});

    // One folder per run, so every intermediate file stays inspectable.
    const QString label = request.value(QStringLiteral("productName")).toString();
    const QString folder = QStringLiteral("%1-%2")
                               .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")),
                                    paths::slugify(label));
    m_run.dir = paths::ensureDir(QDir(m_settings->projectsDir()).filePath(folder));
    if (m_run.dir.isEmpty()) {
        m_log->append(LogModel::Error,
                      tr("Could not create the project folder in %1.").arg(m_settings->projectsDir()));
        emit finished(false, {});
        return;
    }

    m_running = true;
    emit runningChanged();
    emit finishedChanged();
    emit costChanged();

    m_log->append(LogModel::Info, tr("Project folder: %1").arg(QDir::toNativeSeparators(m_run.dir)));

    // The product photo is used both as a reference for the writer and,
    // optionally, as the opening frame itself.
    const QString productImage =
        localPathFromUrlOrPath(request.value(QStringLiteral("productImagePath")).toString());
    if (!productImage.isEmpty() && QFileInfo::exists(productImage)) {
        m_run.productImagePath = productImage;
        m_run.productImageDataUri = http::imageToDataUri(productImage);
        if (m_run.productImageDataUri.isEmpty())
            m_log->append(LogModel::Warning, tr("Could not read the product photo."));
    }

    m_current = -1;
    advance();
}

void Pipeline::cancel()
{
    if (!m_running)
        return;
    m_log->append(LogModel::Warning, tr("Cancelling..."));
    if (m_activeTask)
        m_activeTask->cancel();
    else
        failRun(tr("Cancelled."));
}

void Pipeline::advance()
{
    ++m_current;
    runStep(m_current);
}

void Pipeline::runStep(int index)
{
    switch (index) {
    case StepScript:
        stepScript();
        break;
    case StepVoice:
        stepVoice();
        break;
    case StepFrames:
        stepFrames();
        break;
    case StepVideos:
        stepVideos();
        break;
    case StepCaptions:
        stepCaptions();
        break;
    case StepAssemble:
        stepAssemble();
        break;
    default:
        completeRun();
        break;
    }
}

void Pipeline::attach(ProviderTask *task, const std::function<void(const QVariantMap &)> &onSuccess)
{
    if (!task) {
        failRun(tr("That provider is not available."));
        return;
    }

    m_activeTask = task;
    const int stepIndex = m_current;

    connect(task, &ProviderTask::progress, this, [this, stepIndex](const QString &message) {
        setStatus(message);
        if (m_shotLabel.isEmpty() && stepIndex >= 0 && stepIndex < m_steps.size()) {
            m_steps[stepIndex].detail = message;
            emit stepsChanged();
        }
    });

    connect(task, &ProviderTask::failed, this, [this](const QString &error) {
        m_activeTask = nullptr;
        failRun(error);
    });

    connect(task, &ProviderTask::succeeded, this, [this, onSuccess](const QVariantMap &result) {
        m_activeTask = nullptr;
        onSuccess(result);
    });
}

QString Pipeline::pickModel(const QString &providerId, const QString &requestedModel,
                            int durationSeconds)
{
    const QString resolved = m_registry->resolveModel(providerId, requestedModel, durationSeconds);
    if (Registry::isAuto(requestedModel) && !resolved.isEmpty())
        m_log->append(LogModel::Info, tr("Auto picked %1.").arg(resolved));
    return resolved;
}

void Pipeline::recordUsage(const QString &step, const QString &providerId, const QString &modelId,
                           double units, double unitsOut)
{
    m_run.consumed.append(QVariantMap{
        {QStringLiteral("step"), step},
        {QStringLiteral("provider"), providerId},
        {QStringLiteral("model"), modelId},
        {QStringLiteral("units"), units},
        {QStringLiteral("unitsOut"), unitsOut},
    });
    emit costChanged();
}

QVariantMap Pipeline::cost() const
{
    return m_pricing ? m_pricing->actual(m_run.consumed) : QVariantMap{};
}

QString Pipeline::writeArtifact(const QString &fileName, const QByteArray &data)
{
    const QString path = QDir(m_run.dir).filePath(fileName);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
        failRun(tr("Could not write %1.").arg(fileName));
        return {};
    }
    return path;
}

QString Pipeline::ffmpegExecutable() const
{
    return ffmpeg::resolve(m_settings->ffmpegPath());
}

double Pipeline::estimatedSpeechDuration() const
{
    const int words = m_run.script.split(QRegularExpression(QStringLiteral("\\s+")),
                                         Qt::SkipEmptyParts)
                          .size();
    return qMax(3.0, words / 2.6);
}

// ---------------------------------------------------------------------------
// 1. Script
// ---------------------------------------------------------------------------
void Pipeline::splitOwnScript(int shotCount)
{
    // Cut on sentence boundaries, then pack sentences into shots so the shots
    // come out as even as the punctuation allows. Splitting mid-sentence would
    // put a cut in the middle of a thought.
    static const QRegularExpression boundary(QStringLiteral("(?<=[.!?])\\s+"));
    QStringList sentences = m_run.script.split(boundary, Qt::SkipEmptyParts);
    if (sentences.isEmpty())
        sentences << m_run.script;

    const int shots = qBound(1, qMin(shotCount, sentences.size()), sentences.size());
    const double perShot = double(m_run.script.size()) / shots;

    const auto append = [this](const QString &line) {
        Shot shot;
        shot.line = line;
        m_run.shots.append(shot);
    };

    m_run.shots.clear();
    QString current;
    for (int i = 0; i < sentences.size(); ++i) {
        current += (current.isEmpty() ? QString() : QStringLiteral(" ")) + sentences.at(i);
        const int remaining = sentences.size() - i - 1;
        const bool full = current.size() >= perShot && m_run.shots.size() < shots - 1;
        // Never leave a later shot without a sentence to put in it.
        const bool mustClose = remaining == shots - m_run.shots.size() - 1;
        if (full || mustClose) {
            append(current);
            current.clear();
        }
    }
    if (!current.isEmpty())
        append(current);
}

void Pipeline::stepScript()
{
    const int shotCount = Pricing::shotCount(
        m_request.value(QStringLiteral("durationSeconds"), 20).toInt());

    const QString ownScript = m_request.value(QStringLiteral("script")).toString().trimmed();
    if (!ownScript.isEmpty()) {
        m_run.script = ownScript;
        m_run.hook = ownScript.section(QRegularExpression(QStringLiteral("[.!?]")), 0, 0).trimmed();
        splitOwnScript(shotCount);
        m_log->append(LogModel::Info,
                      tr("Using the script you wrote, cut into %1 shot(s).")
                          .arg(m_run.shots.size()));
        setStepState(StepScript, Skipped, tr("your own script"));
        advance();
        return;
    }

    const QString providerId = m_request.value(QStringLiteral("textProvider")).toString();
    setStepState(StepScript, Running);
    setStatus(tr("Writing the script..."));

    prov::ScriptRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = m_request.value(QStringLiteral("textModel")).toString();
    request.productName = m_request.value(QStringLiteral("productName")).toString();
    request.productDescription = m_request.value(QStringLiteral("productDescription")).toString();
    request.audience = m_request.value(QStringLiteral("audience")).toString();
    request.tone = m_request.value(QStringLiteral("tone")).toString();
    request.language = m_request.value(QStringLiteral("language")).toString();
    request.avatarBrief = m_request.value(QStringLiteral("avatarBrief")).toString();
    request.extraInstructions = m_request.value(QStringLiteral("extraInstructions")).toString();
    request.durationSeconds = m_request.value(QStringLiteral("durationSeconds"), 20).toInt();
    request.shotCount = shotCount;
    request.referenceImageDataUri = m_run.productImageDataUri;

    attach(providers::script(providerId, request, this),
           [this, providerId, model = request.model](const QVariantMap &result) {
        recordUsage(QStringLiteral("script"), providerId, model,
                    result.value(QStringLiteral("inputTokens")).toDouble(),
                    result.value(QStringLiteral("outputTokens")).toDouble());

        m_run.script = result.value(QStringLiteral("script")).toString();
        m_run.hook = result.value(QStringLiteral("hook")).toString();
        m_run.caption = result.value(QStringLiteral("caption")).toString();

        QJsonArray shotsJson;
        for (const QVariant &entry : result.value(QStringLiteral("shots")).toList()) {
            const QVariantMap map = entry.toMap();
            Shot shot;
            shot.line = map.value(QStringLiteral("line")).toString();
            shot.imagePrompt = map.value(QStringLiteral("imagePrompt")).toString();
            shot.videoPrompt = map.value(QStringLiteral("videoPrompt")).toString();
            m_run.shots.append(shot);
            shotsJson.append(QJsonObject{
                {QStringLiteral("line"), shot.line},
                {QStringLiteral("imagePrompt"), shot.imagePrompt},
                {QStringLiteral("videoPrompt"), shot.videoPrompt},
            });
        }

        if (m_run.shots.isEmpty()) {
            failRun(tr("The model answer did not contain a script."));
            return;
        }

        const QJsonObject json{
            {QStringLiteral("hook"), m_run.hook},
            {QStringLiteral("script"), m_run.script},
            {QStringLiteral("caption"), m_run.caption},
            {QStringLiteral("shots"), shotsJson},
        };
        writeArtifact(QStringLiteral("script.json"),
                      QJsonDocument(json).toJson(QJsonDocument::Indented));

        m_log->append(LogModel::Success,
                      tr("Script ready in %1 shot(s): \"%2\"")
                          .arg(m_run.shots.size())
                          .arg(m_run.hook));
        setStepState(StepScript, Done, m_run.hook);
        advance();
    });
}

// ---------------------------------------------------------------------------
// 2. Voice-over (+ duration probe, then the cut plan)
// ---------------------------------------------------------------------------
// The whole script is read in one take. Recording it shot by shot would cost
// the same and sound worse: every join resets the delivery, and the pauses a
// speaker leaves between sentences land in the wrong places. One take also
// means the audio is never cut, so the shot boundaries below only ever move
// the picture.
void Pipeline::stepVoice()
{
    const QString providerId = m_request.value(QStringLiteral("voiceProvider")).toString();
    setStepState(StepVoice, Running);
    setStatus(tr("Recording the voice-over..."));

    prov::VoiceRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = pickModel(providerId, m_request.value(QStringLiteral("voiceModel")).toString());
    request.voiceId = m_request.value(QStringLiteral("voiceId")).toString();
    request.text = m_run.script;

    attach(providers::voice(providerId, request, this),
           [this, providerId, model = request.model, chars = request.text.size()](
               const QVariantMap &result) {
        // TTS is billed on the text we sent, not on the audio that came back.
        recordUsage(QStringLiteral("voice"), providerId, model, chars / 1000.0);

        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        // Not every engine returns mp3; keep the real extension so ffmpeg and
        // Whisper can tell what they are looking at.
        const QString extension =
            result.value(QStringLiteral("extension"), QStringLiteral("mp3")).toString();
        m_run.voicePath = writeArtifact(QStringLiteral("voice.%1").arg(extension), data);
        if (m_run.voicePath.isEmpty())
            return;

        m_log->append(LogModel::Success, tr("Voice-over saved (%1 KB).").arg(data.size() / 1024));
        probeVoiceDuration();
    });
}

void Pipeline::probeVoiceDuration()
{
    const auto settle = [this](double duration, bool measured) {
        m_run.voiceDuration = duration > 0 ? duration : estimatedSpeechDuration();
        planShotTimings();
        setStepState(StepVoice, Done,
                     measured ? tr("%1s").arg(m_run.voiceDuration, 0, 'f', 1)
                              : tr("%1s (estimated)").arg(m_run.voiceDuration, 0, 'f', 1));
        advance();
    };

    const QString exe = ffmpegExecutable();
    if (exe.isEmpty()) {
        settle(-1.0, false);
        return;
    }

    auto *probe = new FfmpegProbeTask(exe, m_run.voicePath, this);
    m_activeTask = probe;
    connect(probe, &ProviderTask::failed, this, [this, settle](const QString &) {
        m_activeTask = nullptr;
        settle(-1.0, false);
    });
    connect(probe, &ProviderTask::succeeded, this, [this, settle](const QVariantMap &result) {
        m_activeTask = nullptr;
        settle(result.value(QStringLiteral("duration"), -1.0).toDouble(), true);
    });
}

// Hands each shot its slice of the voice-over, in proportion to how much of the
// script it speaks.
//
// One voice reading one take keeps a near-constant pace, so characters are a
// good stand-in for seconds. And because the audio plays through uncut, a shot
// boundary landing a fraction of a second early or late only changes the
// picture slightly sooner or later; nothing can drift out of sync.
void Pipeline::planShotTimings()
{
    if (m_run.shots.isEmpty())
        return;

    int totalChars = 0;
    for (const Shot &shot : m_run.shots)
        totalChars += qMax(1, int(shot.line.size()));

    double cursor = 0.0;
    for (int i = 0; i < m_run.shots.size(); ++i) {
        Shot &shot = m_run.shots[i];
        const double share = double(qMax(1, int(shot.line.size()))) / totalChars;
        shot.start = cursor;
        // The last shot takes whatever is left, so rounding can never leave a
        // gap at the end of the ad.
        shot.duration = (i == m_run.shots.size() - 1)
            ? qMax(0.5, m_run.voiceDuration - cursor)
            : m_run.voiceDuration * share;
        cursor += shot.duration;
    }

    m_log->append(LogModel::Info,
                  tr("%1 shot(s) over %2s, about %3s each.")
                      .arg(m_run.shots.size())
                      .arg(m_run.voiceDuration, 0, 'f', 1)
                      .arg(m_run.voiceDuration / m_run.shots.size(), 0, 'f', 1));
}

// ---------------------------------------------------------------------------
// 3. Frames -- one still per shot
// ---------------------------------------------------------------------------
void Pipeline::stepFrames()
{
    m_run.currentShot = 0;
    setStepState(StepFrames, Running);
    runFrame();
}

void Pipeline::runFrame()
{
    const int index = m_run.currentShot;
    if (index >= m_run.shots.size()) {
        m_shotLabel.clear();
        setStepState(StepFrames, Done, tr("%1 frame(s)").arg(m_run.shots.size()));
        advance();
        return;
    }

    // The photo the user dropped in stands in for the first shot's still: that
    // is the one that has to show the real product.
    const bool useOwnPhoto = m_request.value(QStringLiteral("useProductPhotoAsFrame")).toBool();
    if (index == 0 && useOwnPhoto && !m_run.productImagePath.isEmpty()) {
        m_run.shots[index].framePath = m_run.productImagePath;
        m_run.shots[index].frameDataUri = m_run.productImageDataUri;
        m_log->append(LogModel::Info, tr("Using your photo for shot 1."));
        ++m_run.currentShot;
        runFrame();
        return;
    }

    const QString providerId = m_request.value(QStringLiteral("imageProvider")).toString();
    m_shotLabel = tr("%1/%2").arg(index + 1).arg(m_run.shots.size());
    setStepState(StepFrames, Running, m_shotLabel);
    setStatus(tr("Drawing shot %1 of %2...").arg(index + 1).arg(m_run.shots.size()));

    prov::ImageRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = pickModel(providerId, m_request.value(QStringLiteral("imageModel")).toString());
    request.aspectRatio = m_request.value(QStringLiteral("aspectRatio"), QStringLiteral("9:16")).toString();
    request.referenceImageDataUri = m_run.productImageDataUri;
    request.prompt = m_run.shots[index].imagePrompt.isEmpty()
        ? tr("Vertical selfie-style photo of a real person holding %1, natural window light, "
             "shot on a phone camera, authentic user generated content look.")
              .arg(m_request.value(QStringLiteral("productName")).toString())
        : m_run.shots[index].imagePrompt;

    attach(providers::image(providerId, request, this),
           [this, providerId, model = request.model, index](const QVariantMap &result) {
        recordUsage(QStringLiteral("frames"), providerId, model, 1.0);

        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        const QString extension =
            result.value(QStringLiteral("extension"), QStringLiteral("png")).toString();
        const QString path =
            writeArtifact(QStringLiteral("shot%1-frame.%2").arg(index + 1).arg(extension), data);
        if (path.isEmpty())
            return;

        m_run.shots[index].framePath = path;
        m_run.shots[index].frameDataUri = http::imageToDataUri(path);
        m_log->append(LogModel::Success,
                      tr("Frame %1 saved (%2 KB).").arg(index + 1).arg(data.size() / 1024));

        ++m_run.currentShot;
        runFrame();
    });
}

// ---------------------------------------------------------------------------
// 4. Shots -- one clip each, only as long as it is on screen
// ---------------------------------------------------------------------------
void Pipeline::stepVideos()
{
    m_run.currentShot = 0;
    setStepState(StepVideos, Running);
    runVideo();
}

void Pipeline::runVideo()
{
    const int index = m_run.currentShot;
    if (index >= m_run.shots.size()) {
        probeClipDurations();
        return;
    }

    const QString providerId = m_request.value(QStringLiteral("videoProvider")).toString();
    m_shotLabel = tr("%1/%2").arg(index + 1).arg(m_run.shots.size());
    setStepState(StepVideos, Running, m_shotLabel);
    setStatus(tr("Filming shot %1 of %2...").arg(index + 1).arg(m_run.shots.size()));

    // Clips are billed by the second and this one only has to cover its own
    // slice. Short shots are what let every clip be bought at the five-second
    // floor instead of a ten-second one that mostly goes unused.
    const int clipSeconds = Pricing::clipSeconds(m_run.shots[index].duration);

    prov::VideoRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = pickModel(providerId, m_request.value(QStringLiteral("videoModel")).toString(),
                              clipSeconds);
    request.aspectRatio = m_request.value(QStringLiteral("aspectRatio"), QStringLiteral("9:16")).toString();
    request.imageDataUri = m_run.shots[index].frameDataUri;
    request.prompt = m_run.shots[index].videoPrompt.isEmpty()
        ? tr("The person talks straight to the camera, subtle handheld movement, natural blinking "
             "and small hand gestures.")
        : m_run.shots[index].videoPrompt;
    request.durationSeconds = clipSeconds;

    attach(providers::video(providerId, request, this),
           [this, providerId, model = request.model, seconds = clipSeconds, index](
               const QVariantMap &result) {
        // One clip, `seconds` long -- models bill by whichever of the two they
        // price on.
        recordUsage(QStringLiteral("video"), providerId, model, seconds, 1);

        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        const QString extension =
            result.value(QStringLiteral("extension"), QStringLiteral("mp4")).toString();
        const QString path =
            writeArtifact(QStringLiteral("shot%1-clip.%2").arg(index + 1).arg(extension), data);
        if (path.isEmpty())
            return;

        m_run.shots[index].clipPath = path;
        m_log->append(LogModel::Success,
                      tr("Shot %1 saved (%2 MB).")
                          .arg(index + 1)
                          .arg(data.size() / 1048576.0, 0, 'f', 1));

        ++m_run.currentShot;
        runVideo();
    });
}

// Measures every clip so the cut can trim each one to its slot. A clip that
// came back shorter than we asked for would otherwise leave a gap.
void Pipeline::probeClipDurations()
{
    if (ffmpegExecutable().isEmpty()) {
        m_shotLabel.clear();
        setStepState(StepVideos, Done, tr("%1 shot(s)").arg(m_run.shots.size()));
        advance();
        return;
    }

    m_run.currentShot = 0;
    probeNextClip();
}

void Pipeline::probeNextClip()
{
    const int index = m_run.currentShot;
    if (index >= m_run.shots.size()) {
        m_shotLabel.clear();
        setStepState(StepVideos, Done, tr("%1 shot(s)").arg(m_run.shots.size()));
        advance();
        return;
    }

    auto *probe = new FfmpegProbeTask(ffmpegExecutable(), m_run.shots[index].clipPath, this);
    m_activeTask = probe;
    const auto done = [this, index](double duration) {
        m_activeTask = nullptr;
        m_run.shots[index].clipDuration = duration;
        ++m_run.currentShot;
        probeNextClip();
    };
    connect(probe, &ProviderTask::failed, this, [done](const QString &) { done(-1.0); });
    connect(probe, &ProviderTask::succeeded, this, [done](const QVariantMap &result) {
        done(result.value(QStringLiteral("duration"), -1.0).toDouble());
    });
}

// ---------------------------------------------------------------------------
// 5. Subtitles
// ---------------------------------------------------------------------------
void Pipeline::stepCaptions()
{
    if (!m_request.value(QStringLiteral("captionsEnabled"), true).toBool()) {
        setStepState(StepCaptions, Skipped, tr("off"));
        advance();
        return;
    }

    const QString providerId = m_request.value(QStringLiteral("captionsProvider")).toString();
    setStepState(StepCaptions, Running);
    setStatus(tr("Timing the subtitles..."));

    prov::TranscribeRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = m_request.value(QStringLiteral("captionsModel"), QStringLiteral("whisper-1")).toString();
    request.audioPath = m_run.voicePath;

    ProviderTask *task = providers::transcribe(providerId, request, this);
    if (!task) {
        m_log->append(LogModel::Warning, tr("No subtitle provider selected, skipping."));
        setStepState(StepCaptions, Skipped);
        advance();
        return;
    }

    m_activeTask = task;
    connect(task, &ProviderTask::progress, this, [this](const QString &message) { setStatus(message); });

    // Subtitles are a nice-to-have: a failure here must not lose the video.
    connect(task, &ProviderTask::failed, this, [this](const QString &error) {
        m_activeTask = nullptr;
        m_log->append(LogModel::Warning, tr("Subtitles unavailable (%1). Continuing without them.").arg(error));
        setStepState(StepCaptions, Skipped, tr("failed"));
        advance();
    });

    connect(task, &ProviderTask::succeeded, this,
            [this, providerId, model = request.model](const QVariantMap &result) {
        m_activeTask = nullptr;
        // Whisper bills the length of the audio it listened to.
        recordUsage(QStringLiteral("captions"), providerId, model,
                    qMax(0.0, m_run.voiceDuration) / 60.0);

        const QString srt = result.value(QStringLiteral("srt")).toString();
        m_run.srtPath = writeArtifact(QString::fromLatin1(kCaptionsFile), srt.toUtf8());
        if (m_run.srtPath.isEmpty())
            return;
        m_log->append(LogModel::Success, tr("Subtitles ready."));
        setStepState(StepCaptions, Done);
        advance();
    });
}

// ---------------------------------------------------------------------------
// 6. Final cut
// ---------------------------------------------------------------------------
// Every shot is trimmed to its slot and the slots are laid end to end, so the
// picture keeps moving for the whole ad without a single frame being stretched
// or looped. One ffmpeg pass does the lot: trim, normalise, concatenate, burn
// in the subtitles and mux the voice-over.
void Pipeline::stepAssemble()
{
    setStepState(StepAssemble, Running);
    setStatus(tr("Assembling the final video..."));

    const QString exe = ffmpegExecutable();
    if (exe.isEmpty()) {
        m_log->append(LogModel::Error,
                      tr("FFmpeg is required to cut the shots together with the voice-over and "
                         "the subtitles. Install it or set its path in Settings. Your generated "
                         "files are in %1.")
                          .arg(QDir::toNativeSeparators(m_run.dir)));
        failRun(tr("FFmpeg not found."));
        return;
    }

    QList<Shot> usable;
    for (const Shot &shot : m_run.shots) {
        if (!shot.clipPath.isEmpty())
            usable.append(shot);
    }
    if (usable.isEmpty()) {
        failRun(tr("No shot was rendered, so there is nothing to cut together."));
        return;
    }

    const QSize frame = outputSize(
        m_request.value(QStringLiteral("aspectRatio"), QStringLiteral("9:16")).toString());
    const bool hasSubtitles = !m_run.srtPath.isEmpty();

    QStringList args{QStringLiteral("-y"), QStringLiteral("-hide_banner")};
    for (const Shot &shot : usable)
        args << QStringLiteral("-i") << QFileInfo(shot.clipPath).fileName();
    args << QStringLiteral("-i") << QFileInfo(m_run.voicePath).fileName();

    // Clips come from different models at different sizes and frame rates.
    // concat refuses to join streams that do not match, so each one is padded
    // to the same canvas and resampled to the same rate first.
    // A clip can come back shorter than the slot it has to fill. Work out how
    // much picture we will actually have before writing the graph, so the last
    // shot can hold its final frame over any shortfall -- otherwise -shortest
    // below would trim the voice-over to match the video and cut the ad off
    // mid-sentence.
    QList<double> onScreen;
    double picture = 0.0;
    for (const Shot &shot : usable) {
        const double available =
            shot.clipDuration > 0 ? qMin(shot.duration, shot.clipDuration) : shot.duration;
        onScreen.append(available);
        picture += available;
    }
    const double shortfall = qMax(0.0, m_run.voiceDuration - picture);
    if (shortfall > 0.5) {
        m_log->append(LogModel::Warning,
                      tr("The clips are %1s short of the voice-over; the last shot holds.")
                          .arg(shortfall, 0, 'f', 1));
    }

    QStringList chains;
    QString concatInputs;
    for (int i = 0; i < usable.size(); ++i) {
        QString chain = QStringLiteral("[%1:v]trim=0:%2,setpts=PTS-STARTPTS,"
                                       "scale=%3:%4:force_original_aspect_ratio=decrease,"
                                       "pad=%3:%4:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30")
                            .arg(i)
                            .arg(onScreen.at(i), 0, 'f', 3)
                            .arg(frame.width())
                            .arg(frame.height());

        // Half a second of slack on top, so rounding can never leave the last
        // frames of the voice-over without a picture. -shortest trims it back.
        if (i == usable.size() - 1) {
            chain += QStringLiteral(",tpad=stop_mode=clone:stop_duration=%1")
                         .arg(shortfall + 0.5, 0, 'f', 3);
        }

        chains << chain + QStringLiteral("[v%1]").arg(i);
        concatInputs += QStringLiteral("[v%1]").arg(i);
    }

    QString lastLabel = QStringLiteral("vc");
    chains << QStringLiteral("%1concat=n=%2:v=1:a=0[vc]").arg(concatInputs).arg(usable.size());
    if (hasSubtitles) {
        chains << QStringLiteral("[vc]subtitles=%1:force_style='%2'[vs]")
                      .arg(ffmpeg::escapeFilterPath(QString::fromLatin1(kCaptionsFile)),
                           QString::fromLatin1(kSubtitleStyle));
        lastLabel = QStringLiteral("vs");
    }

    args << QStringLiteral("-filter_complex") << chains.join(QLatin1Char(';'));
    args << QStringLiteral("-map") << QStringLiteral("[%1]").arg(lastLabel);
    args << QStringLiteral("-map") << QStringLiteral("%1:a:0").arg(usable.size());
    args << QStringLiteral("-c:v") << QStringLiteral("libx264");
    args << QStringLiteral("-preset") << QStringLiteral("medium");
    args << QStringLiteral("-crf") << QStringLiteral("20");
    args << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p");
    args << QStringLiteral("-c:a") << QStringLiteral("aac");
    args << QStringLiteral("-b:a") << QStringLiteral("192k");
    args << QStringLiteral("-shortest");
    args << QStringLiteral("-movflags") << QStringLiteral("+faststart");
    args << QString::fromLatin1(kFinalFile);

    m_log->append(LogModel::Info,
                  tr("Cutting %1 shot(s) into %2x%3.")
                      .arg(usable.size())
                      .arg(frame.width())
                      .arg(frame.height()));

    auto *task = new FfmpegTask(exe, args, m_run.dir, this);
    attach(task, [this](const QVariantMap &) {
        m_run.finalPath = QDir(m_run.dir).filePath(QString::fromLatin1(kFinalFile));
        if (!QFileInfo::exists(m_run.finalPath)) {
            failRun(tr("FFmpeg finished but produced no file."));
            return;
        }
        setStepState(StepAssemble, Done, QString::fromLatin1(kFinalFile));
        advance();
    });
}

// ---------------------------------------------------------------------------
// Wrap-up
// ---------------------------------------------------------------------------
void Pipeline::writeProjectManifest(bool success)
{
    if (m_run.dir.isEmpty())
        return;

    const auto relative = [this](const QString &path) {
        return path.isEmpty() ? QString() : QDir(m_run.dir).relativeFilePath(path);
    };

    QJsonArray shots;
    for (const Shot &shot : m_run.shots) {
        shots.append(QJsonObject{
            {QStringLiteral("line"), shot.line},
            {QStringLiteral("imagePrompt"), shot.imagePrompt},
            {QStringLiteral("videoPrompt"), shot.videoPrompt},
            {QStringLiteral("frame"), relative(shot.framePath)},
            {QStringLiteral("clip"), relative(shot.clipPath)},
            {QStringLiteral("start"), shot.start},
            {QStringLiteral("duration"), shot.duration},
        });
    }

    const QJsonObject manifest{
        {QStringLiteral("app"), QStringLiteral("Market Queen")},
        {QStringLiteral("version"), QStringLiteral(APP_VERSION)},
        // Bumped whenever the shape below changes; LibraryModel reads older ones.
        // 2 replaced the single frame/clip pair with the shots array.
        {QStringLiteral("schemaVersion"), 2},
        {QStringLiteral("createdAt"), QDateTime::currentDateTime().toString(Qt::ISODate)},
        {QStringLiteral("success"), success},
        {QStringLiteral("productName"), m_request.value(QStringLiteral("productName")).toString()},
        {QStringLiteral("hook"), m_run.hook},
        {QStringLiteral("script"), m_run.script},
        {QStringLiteral("caption"), m_run.caption},
        {QStringLiteral("shots"), shots},
        // The first shot's still doubles as the project thumbnail.
        {QStringLiteral("frame"),
         m_run.shots.isEmpty() ? QString() : relative(m_run.shots.first().framePath)},
        {QStringLiteral("voice"), relative(m_run.voicePath)},
        {QStringLiteral("captions"), relative(m_run.srtPath)},
        {QStringLiteral("final"), relative(m_run.finalPath)},
        // What the providers billed, estimated from their published prices.
        {QStringLiteral("cost"), QJsonObject::fromVariantMap(cost())},
        {QStringLiteral("providers"),
         QJsonObject{
             {QStringLiteral("text"), m_request.value(QStringLiteral("textProvider")).toString()},
             {QStringLiteral("textModel"), m_request.value(QStringLiteral("textModel")).toString()},
             {QStringLiteral("image"), m_request.value(QStringLiteral("imageProvider")).toString()},
             {QStringLiteral("imageModel"), m_request.value(QStringLiteral("imageModel")).toString()},
             {QStringLiteral("video"), m_request.value(QStringLiteral("videoProvider")).toString()},
             {QStringLiteral("videoModel"), m_request.value(QStringLiteral("videoModel")).toString()},
             {QStringLiteral("voice"), m_request.value(QStringLiteral("voiceProvider")).toString()},
             {QStringLiteral("voiceModel"), m_request.value(QStringLiteral("voiceModel")).toString()},
         }},
    };

    QSaveFile file(QDir(m_run.dir).filePath(QStringLiteral("project.json")));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(manifest).toJson(QJsonDocument::Indented));
        file.commit();
    }
}

void Pipeline::failRun(const QString &error)
{
    if (!m_running)
        return;

    if (m_current >= 0 && m_current < m_steps.size() && m_steps[m_current].state == Running)
        setStepState(m_current, Failed, error);

    m_log->append(LogModel::Error, error);
    setStatus(error);

    writeProjectManifest(false);

    m_running = false;
    m_activeTask = nullptr;
    emit runningChanged();
    emit finishedChanged();
    emit finished(false, {});
}

void Pipeline::completeRun()
{
    writeProjectManifest(true);

    m_running = false;
    emit runningChanged();
    emit finishedChanged();

    m_log->append(LogModel::Success,
                  tr("Done: %1").arg(QDir::toNativeSeparators(m_run.finalPath)));
    setStatus(tr("Your ad is ready."));
    emit finished(true, m_run.finalPath);
}
