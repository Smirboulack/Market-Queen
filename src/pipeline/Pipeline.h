#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class LogModel;
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

public:
    Pipeline(SettingsStore *settings, Registry *registry, LogModel *log,
             QObject *parent = nullptr);

    bool running() const { return m_running; }
    QVariantList steps() const;
    QString status() const { return m_status; }
    double progress() const;
    QString outputFile() const { return m_run.finalPath; }
    QString projectDir() const { return m_run.dir; }

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
    void finished(bool success, const QString &outputFile);

private:
    enum StepState { Pending, Running, Done, Skipped, Failed };

    struct Step {
        QString label;
        StepState state = Pending;
        QString detail;
    };

    struct RunState {
        QString dir;
        QString productImagePath;
        QString productImageDataUri;
        QString hook;
        QString script;
        QString caption;
        QString imagePrompt;
        QString videoPrompt;
        QString framePath;
        QString frameDataUri;
        QString voicePath;
        QString clipPath;
        QString srtPath;
        QString finalPath;
        double voiceDuration = -1.0;
        double clipDuration = -1.0;
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
    void stepFrame();
    void stepVoice();
    void stepVideo();
    void stepCaptions();
    void stepAssemble();

    void probeVoiceDuration();
    void probeClipDuration();
    QString writeArtifact(const QString &fileName, const QByteArray &data);
    void writeProjectManifest(bool success);
    QString ffmpegExecutable() const;
    double estimatedSpeechDuration() const;

    SettingsStore *m_settings;
    Registry *m_registry;
    LogModel *m_log;

    QVariantMap m_request;
    RunState m_run;
    QList<Step> m_steps;
    int m_current = -1;
    bool m_running = false;
    QString m_status;
    QPointer<ProviderTask> m_activeTask;
};
