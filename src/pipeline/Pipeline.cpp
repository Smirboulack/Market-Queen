#include "Pipeline.h"

#include "core/Http.h"
#include "core/LogModel.h"
#include "core/Paths.h"
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
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>

namespace {

enum StepIndex {
    StepScript = 0,
    StepFrame,
    StepVoice,
    StepVideo,
    StepCaptions,
    StepAssemble,
    StepCount,
};

constexpr const char *kFrameFile = "frame.png";
constexpr const char *kVoiceFile = "voice.mp3";
constexpr const char *kClipFile = "clip.mp4";
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

} // namespace

Pipeline::Pipeline(SettingsStore *settings, Registry *registry, LogModel *log, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_registry(registry)
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
    case StepFrame:
        return tr("Opening frame");
    case StepVoice:
        return tr("Voice-over");
    case StepVideo:
        return tr("Video");
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
    case StepFrame:
        stepFrame();
        break;
    case StepVoice:
        stepVoice();
        break;
    case StepVideo:
        stepVideo();
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
        if (stepIndex >= 0 && stepIndex < m_steps.size()) {
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
void Pipeline::stepScript()
{
    const QString ownScript = m_request.value(QStringLiteral("script")).toString().trimmed();
    if (!ownScript.isEmpty()) {
        m_run.script = ownScript;
        m_run.hook = ownScript.section(QRegularExpression(QStringLiteral("[.!?]")), 0, 0).trimmed();
        m_log->append(LogModel::Info, tr("Using the script you wrote."));
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
    request.referenceImageDataUri = m_run.productImageDataUri;

    attach(providers::script(providerId, request, this), [this](const QVariantMap &result) {
        m_run.script = result.value(QStringLiteral("script")).toString();
        m_run.hook = result.value(QStringLiteral("hook")).toString();
        m_run.caption = result.value(QStringLiteral("caption")).toString();
        m_run.imagePrompt = result.value(QStringLiteral("imagePrompt")).toString();
        m_run.videoPrompt = result.value(QStringLiteral("videoPrompt")).toString();

        QJsonObject json{
            {QStringLiteral("hook"), m_run.hook},
            {QStringLiteral("script"), m_run.script},
            {QStringLiteral("caption"), m_run.caption},
            {QStringLiteral("imagePrompt"), m_run.imagePrompt},
            {QStringLiteral("videoPrompt"), m_run.videoPrompt},
        };
        writeArtifact(QStringLiteral("script.json"),
                      QJsonDocument(json).toJson(QJsonDocument::Indented));

        m_log->append(LogModel::Success, tr("Script ready: \"%1\"").arg(m_run.hook));
        setStepState(StepScript, Done, m_run.hook);
        advance();
    });
}

// ---------------------------------------------------------------------------
// 2. Opening frame
// ---------------------------------------------------------------------------
void Pipeline::stepFrame()
{
    const bool useOwnPhoto = m_request.value(QStringLiteral("useProductPhotoAsFrame")).toBool();
    if (useOwnPhoto && !m_run.productImagePath.isEmpty()) {
        m_run.framePath = m_run.productImagePath;
        m_run.frameDataUri = m_run.productImageDataUri;
        m_log->append(LogModel::Info, tr("Using your photo as the opening frame."));
        setStepState(StepFrame, Skipped, tr("your photo"));
        advance();
        return;
    }

    const QString providerId = m_request.value(QStringLiteral("imageProvider")).toString();
    setStepState(StepFrame, Running);
    setStatus(tr("Generating the opening frame..."));

    prov::ImageRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = m_request.value(QStringLiteral("imageModel")).toString();
    request.aspectRatio = m_request.value(QStringLiteral("aspectRatio"), QStringLiteral("9:16")).toString();
    request.referenceImageDataUri = m_run.productImageDataUri;
    request.prompt = m_run.imagePrompt.isEmpty()
        ? tr("Vertical selfie-style photo of a real person holding %1, natural window light, "
             "shot on a phone camera, authentic user generated content look.")
              .arg(m_request.value(QStringLiteral("productName")).toString())
        : m_run.imagePrompt;

    attach(providers::image(providerId, request, this), [this](const QVariantMap &result) {
        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        const QString extension = result.value(QStringLiteral("extension"), QStringLiteral("png")).toString();
        const QString fileName = QStringLiteral("frame.%1").arg(extension);

        m_run.framePath = writeArtifact(fileName, data);
        if (m_run.framePath.isEmpty())
            return;

        m_run.frameDataUri = http::imageToDataUri(m_run.framePath);
        m_log->append(LogModel::Success, tr("Opening frame saved (%1 KB).").arg(data.size() / 1024));
        setStepState(StepFrame, Done, fileName);
        advance();
    });
}

// ---------------------------------------------------------------------------
// 3. Voice-over (+ duration probe)
// ---------------------------------------------------------------------------
void Pipeline::stepVoice()
{
    const QString providerId = m_request.value(QStringLiteral("voiceProvider")).toString();
    setStepState(StepVoice, Running);
    setStatus(tr("Recording the voice-over..."));

    prov::VoiceRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = m_request.value(QStringLiteral("voiceModel")).toString();
    request.voiceId = m_request.value(QStringLiteral("voiceId")).toString();
    request.text = m_run.script;

    attach(providers::voice(providerId, request, this), [this](const QVariantMap &result) {
        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        m_run.voicePath = writeArtifact(QString::fromLatin1(kVoiceFile), data);
        if (m_run.voicePath.isEmpty())
            return;

        m_log->append(LogModel::Success, tr("Voice-over saved (%1 KB).").arg(data.size() / 1024));
        probeVoiceDuration();
    });
}

void Pipeline::probeVoiceDuration()
{
    const QString exe = ffmpegExecutable();
    if (exe.isEmpty()) {
        m_run.voiceDuration = estimatedSpeechDuration();
        setStepState(StepVoice, Done, tr("%1s (estimated)").arg(m_run.voiceDuration, 0, 'f', 1));
        advance();
        return;
    }

    auto *probe = new FfmpegProbeTask(exe, m_run.voicePath, this);
    m_activeTask = probe;
    connect(probe, &ProviderTask::failed, this, [this](const QString &) {
        m_activeTask = nullptr;
        m_run.voiceDuration = estimatedSpeechDuration();
        setStepState(StepVoice, Done, tr("%1s (estimated)").arg(m_run.voiceDuration, 0, 'f', 1));
        advance();
    });
    connect(probe, &ProviderTask::succeeded, this, [this](const QVariantMap &result) {
        m_activeTask = nullptr;
        const double duration = result.value(QStringLiteral("duration"), -1.0).toDouble();
        m_run.voiceDuration = duration > 0 ? duration : estimatedSpeechDuration();
        setStepState(StepVoice, Done, tr("%1s").arg(m_run.voiceDuration, 0, 'f', 1));
        advance();
    });
}

// ---------------------------------------------------------------------------
// 4. Video
// ---------------------------------------------------------------------------
void Pipeline::stepVideo()
{
    const QString providerId = m_request.value(QStringLiteral("videoProvider")).toString();
    setStepState(StepVideo, Running);
    setStatus(tr("Animating the frame..."));

    prov::VideoRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = m_request.value(QStringLiteral("videoModel")).toString();
    request.aspectRatio = m_request.value(QStringLiteral("aspectRatio"), QStringLiteral("9:16")).toString();
    request.imageDataUri = m_run.frameDataUri;
    request.prompt = m_run.videoPrompt.isEmpty()
        ? tr("The person talks straight to the camera, subtle handheld movement, natural blinking "
             "and small hand gestures.")
        : m_run.videoPrompt;
    // Clips are billed per second: ask for the shortest one that we can loop.
    request.durationSeconds = m_run.voiceDuration > 7.0 ? 10 : 5;

    m_log->append(LogModel::Info, tr("Requesting a %1s clip.").arg(request.durationSeconds));

    attach(providers::video(providerId, request, this), [this](const QVariantMap &result) {
        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        const QString extension = result.value(QStringLiteral("extension"), QStringLiteral("mp4")).toString();
        m_run.clipPath = writeArtifact(QStringLiteral("clip.%1").arg(extension), data);
        if (m_run.clipPath.isEmpty())
            return;

        m_log->append(LogModel::Success, tr("Clip saved (%1 MB).").arg(data.size() / 1048576.0, 0, 'f', 1));
        probeClipDuration();
    });
}

void Pipeline::probeClipDuration()
{
    const QString exe = ffmpegExecutable();
    if (exe.isEmpty()) {
        setStepState(StepVideo, Done);
        advance();
        return;
    }

    auto *probe = new FfmpegProbeTask(exe, m_run.clipPath, this);
    m_activeTask = probe;
    const auto done = [this](double duration) {
        m_activeTask = nullptr;
        m_run.clipDuration = duration;
        setStepState(StepVideo, Done,
                     duration > 0 ? tr("%1s").arg(duration, 0, 'f', 1) : QString());
        advance();
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

    connect(task, &ProviderTask::succeeded, this, [this](const QVariantMap &result) {
        m_activeTask = nullptr;
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
void Pipeline::stepAssemble()
{
    setStepState(StepAssemble, Running);
    setStatus(tr("Assembling the final video..."));

    const QString exe = ffmpegExecutable();
    if (exe.isEmpty()) {
        m_log->append(LogModel::Error,
                      tr("FFmpeg is required to merge the clip, the voice-over and the subtitles. "
                         "Install it or set its path in Settings. Your generated files are in %1.")
                          .arg(QDir::toNativeSeparators(m_run.dir)));
        failRun(tr("FFmpeg not found."));
        return;
    }

    const QString clipName = QFileInfo(m_run.clipPath).fileName();
    const QString voiceName = QFileInfo(m_run.voicePath).fileName();
    const bool hasSubtitles = !m_run.srtPath.isEmpty();

    // The clip is almost always shorter than the voice-over. Stretching reads
    // better than a visible loop point, but only up to a point.
    double stretch = 1.0;
    bool loop = false;
    if (m_run.clipDuration > 0.5 && m_run.voiceDuration > 0.5) {
        const double ratio = m_run.voiceDuration / m_run.clipDuration;
        if (ratio > 1.02 && ratio <= 1.35)
            stretch = ratio;
        else if (ratio > 1.35)
            loop = true;
    } else {
        loop = true; // unknown durations: looping is the safe default
    }

    QStringList args{QStringLiteral("-y"), QStringLiteral("-hide_banner")};
    if (loop)
        args << QStringLiteral("-stream_loop") << QStringLiteral("-1");
    args << QStringLiteral("-i") << clipName;
    args << QStringLiteral("-i") << voiceName;

    QStringList filters;
    if (stretch > 1.0)
        filters << QStringLiteral("setpts=%1*PTS").arg(stretch, 0, 'f', 4);
    // libx264 + yuv420p needs even dimensions.
    filters << QStringLiteral("scale=trunc(iw/2)*2:trunc(ih/2)*2");
    if (hasSubtitles) {
        filters << QStringLiteral("subtitles=%1:force_style='%2'")
                       .arg(ffmpeg::escapeFilterPath(QString::fromLatin1(kCaptionsFile)),
                            QString::fromLatin1(kSubtitleStyle));
    }

    args << QStringLiteral("-vf") << filters.join(QLatin1Char(','));
    args << QStringLiteral("-map") << QStringLiteral("0:v:0");
    args << QStringLiteral("-map") << QStringLiteral("1:a:0");
    args << QStringLiteral("-c:v") << QStringLiteral("libx264");
    args << QStringLiteral("-preset") << QStringLiteral("medium");
    args << QStringLiteral("-crf") << QStringLiteral("20");
    args << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p");
    args << QStringLiteral("-c:a") << QStringLiteral("aac");
    args << QStringLiteral("-b:a") << QStringLiteral("192k");
    args << QStringLiteral("-shortest");
    args << QStringLiteral("-movflags") << QStringLiteral("+faststart");
    args << QString::fromLatin1(kFinalFile);

    if (loop)
        m_log->append(LogModel::Info, tr("Looping the clip to cover the voice-over."));
    else if (stretch > 1.0)
        m_log->append(LogModel::Info, tr("Slowing the clip by %1% to match the voice-over.")
                                          .arg((stretch - 1.0) * 100.0, 0, 'f', 0));

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

    const QJsonObject manifest{
        {QStringLiteral("app"), QStringLiteral("Super Infinity")},
        {QStringLiteral("version"), QStringLiteral(APP_VERSION)},
        {QStringLiteral("createdAt"), QDateTime::currentDateTime().toString(Qt::ISODate)},
        {QStringLiteral("success"), success},
        {QStringLiteral("productName"), m_request.value(QStringLiteral("productName")).toString()},
        {QStringLiteral("hook"), m_run.hook},
        {QStringLiteral("script"), m_run.script},
        {QStringLiteral("caption"), m_run.caption},
        {QStringLiteral("frame"), relative(m_run.framePath)},
        {QStringLiteral("voice"), relative(m_run.voicePath)},
        {QStringLiteral("clip"), relative(m_run.clipPath)},
        {QStringLiteral("captions"), relative(m_run.srtPath)},
        {QStringLiteral("final"), relative(m_run.finalPath)},
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
