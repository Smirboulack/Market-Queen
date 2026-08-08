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

    // Everything the form collected. See CreatePage.qml for the keys.
    Q_INVOKABLE void start(const QVariantMap &request);
    Q_INVOKABLE void cancel();

    // Re-labels the steps after a language switch.
    void retranslate();

signals:
    void runningChanged();
    void stepsChanged();
    void statusChanged();
    void finishedChanged();
    void costChanged();
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
        QString imagePrompt;
        QString videoPrompt;
        QString framePath;
        QString frameDataUri;
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

    // The frame and video steps walk the shot list one at a time; these run the
    // shot at m_run.currentShot and move on to the next when it lands.
    void runFrame();
    void runVideo();

    void probeVoiceDuration();
    void probeClipDurations();
    void probeNextClip();

    // Splits the script into shots when the writer was skipped, and hands each
    // shot its slice of the measured voice-over.
    void splitOwnScript(int shotCount);
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
    QList<Step> m_steps;
    int m_current = -1;
    bool m_running = false;
    QString m_status;
    QPointer<ProviderTask> m_activeTask;
};
