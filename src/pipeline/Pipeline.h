#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class LogModel;
class Pricing;
class ProviderTask;
class Registry;
class SettingsStore;

// Turns one form submission into a finished MP4.
//
// The steps run one after another, each one feeding the next through m_run.
// Nothing blocks: every step starts a task and returns, and the state machine
// advances from the task's signals.
class Pipeline : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QVariantList steps READ steps NOTIFY stepsChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(double progress READ progress NOTIFY statusChanged)
    Q_PROPERTY(QString outputFile READ outputFile NOTIFY finishedChanged)
    Q_PROPERTY(QString projectDir READ projectDir NOTIFY finishedChanged)
    // What the run has cost so far, in the shape Pricing::actual returns.
    Q_PROPERTY(QVariantMap cost READ cost NOTIFY costChanged)
    // The finished cut, shot by shot: what the storyboard is drawn from.
    Q_PROPERTY(QVariantList shots READ shotsInfo NOTIFY shotsChanged)

public:
    Pipeline(SettingsStore *settings, Registry *registry, Pricing *pricing, LogModel *log,
             QObject *parent = nullptr);

    bool running() const { return m_running; }
    QVariantList steps() const;
    QString status() const { return m_status; }
    double progress() const;
    QString outputFile() const { return m_run.finalPath; }
    QString projectDir() const { return m_run.dir; }
    QVariantMap cost() const;
    QVariantList shotsInfo() const;

    // The whole ad, as AdProject::toRequest() builds it.
    Q_INVOKABLE void start(const QVariantMap &request);
    Q_INVOKABLE void cancel();

    // Re-shoots one scene and cuts the ad again. Repairing a bad shot costs a
    // fraction of relaunching the whole ad, which is the whole reason the shots
    // are kept as separate files.
    Q_INVOKABLE void regenerateShot(int index);
    // What that would cost: { amount, known }.
    Q_INVOKABLE QVariantMap regenerateEstimate(int index) const;

    // Re-labels the steps after a language switch.
    void retranslate();

signals:
    void runningChanged();
    void stepsChanged();
    void statusChanged();
    void finishedChanged();
    void costChanged();
    void shotsChanged();
    void finished(bool success, const QString &outputFile);

private:
    enum StepState { Pending, Running, Done, Skipped, Failed };

    struct Step {
        QString label;
        StepState state = Pending;
        QString detail;
    };

    // One camera setup: the words spoken over it, the still it starts from and
    // the clip that still was animated into.
    struct Shot {
        QString line;
        QString kind = QStringLiteral("talking");   // talking | broll
        QString imagePrompt;
        QString videoPrompt;
        QString framePath;
        QString frameDataUri;
        // This shot's own slice of the read. It is what the avatar model is
        // lip-synced to, and its length is what the shot lasts -- measured,
        // not apportioned.
        QString voicePath;
        QString voiceDataUri;
        QString clipPath;
        // Where this shot sits in the finished cut, in seconds. `duration` is
        // its share of the voice-over; `clipDuration` is what the provider
        // actually returned, which can be shorter.
        double start = 0.0;
        double duration = 0.0;
        double clipDuration = -1.0;
    };

    struct RunState {
        QString dir;
        QString productImagePath;
        QString productImageDataUri;
        // The cast actor. Where both exist the portrait wins for the frames --
        // a face that changes between shots is more visible than a product
        // rendered from its description rather than its photo.
        QString actorPortraitDataUri;
        QString hook;
        QString script;
        QString caption;
        QString voicePath;
        QString srtPath;
        QString finalPath;
        double voiceDuration = -1.0;
        QList<Shot> shots;
        // Which shot the frame or video step is currently on.
        int currentShot = 0;
        // One entry per billable call: {step, provider, model, units, unitsOut}.
        QVariantList consumed;
    };

    static QString stepLabel(int index);
    void resetSteps();
    void runStep(int index);
    void advance();
    void setStepState(int index, StepState state, const QString &detail = {});
    void setStatus(const QString &status);
    void failRun(const QString &error);
    void completeRun();

    // Wires a task's signals into the log and the state machine. The task owns
    // itself and disappears after it reports.
    void attach(ProviderTask *task, const std::function<void(const QVariantMap &)> &onSuccess);

    void stepScript();
    void stepVoice();
    void stepFrames();
    void stepVideos();
    void stepCaptions();
    void stepAssemble();

    // The voice step walks the shots too: one take per line, each one told what
    // was said before and after it so the delivery carries across the cuts.
    void runVoiceLine();
    void probeShotAudio();
    void joinVoice();

    // The frame and video steps walk the shot list one at a time; these run the
    // shot at m_run.currentShot and move on to the next when it lands.
    void runFrame();
    void runVideo();

    void probeClipDurations();
    void probeNextClip();

    // Splits the script into shots when the writer was skipped.
    void splitOwnScript(int shotCount);
    // Lays the measured per-shot durations end to end.
    void planShotTimings();
    // Turns an "auto" pick into a concrete model id and says so in the log.
    QString pickModel(const QString &providerId, const QString &requestedModel,
                      int durationSeconds = 0);

    // Records what a step actually bought, so the run can report a real cost
    // instead of repeating the estimate.
    void recordUsage(const QString &step, const QString &providerId, const QString &modelId,
                     double units, double unitsOut = 0.0);

    QString writeArtifact(const QString &fileName, const QByteArray &data);
    void writeProjectManifest(bool success);
    QString ffmpegExecutable() const;
    double estimatedSpeechDuration() const;

    SettingsStore *m_settings;
    Registry *m_registry;
    Pricing *m_pricing;
    LogModel *m_log;

    QVariantMap m_request;
    RunState m_run;
    // "2/4" while a step is walking the shot list. Set, it pins the step's
    // detail column so a provider's progress chatter cannot bury the count --
    // which, on a six-shot run, is the one thing worth seeing at a glance.
    QString m_shotLabel;
    // When >= 0, the frame and video steps do this shot only and then go
    // straight to the cut: re-shooting one scene must not re-buy the others.
    int m_onlyShot = -1;
    QList<Step> m_steps;
    int m_current = -1;
    bool m_running = false;
    QString m_status;
    QPointer<ProviderTask> m_activeTask;
};
