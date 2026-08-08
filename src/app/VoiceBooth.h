#pragma once

#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class LogModel;
class Pricing;
class ProviderTask;
class Registry;
class SettingsStore;

// The audition booth.
//
// A voice-over is the cheapest part of an ad to get wrong and the most obvious
// once it is: an announcer read sinks a UGC ad as surely as a model's face. So
// this exists to make hearing the actor cost a fraction of a cent, before any
// video is bought.
//
// Cloning is deliberately separate and never implicit. It uploads the user's
// recordings and creates a permanent voice on their provider account, so it
// only ever happens on an explicit click.
class VoiceBooth : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(bool auditioning READ auditioning NOTIFY auditioningChanged)
    Q_PROPERTY(bool cloning READ cloning NOTIFY cloningChanged)
    // Local file of the last audition, empty until one lands.
    Q_PROPERTY(QString samplePath READ samplePath NOTIFY samplePathChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QStringList cloneSamples READ cloneSamples NOTIFY cloneSamplesChanged)

public:
    VoiceBooth(SettingsStore *settings, Registry *registry, Pricing *pricing, LogModel *log,
               QObject *parent = nullptr);

    bool auditioning() const { return m_auditioning; }
    bool cloning() const { return m_cloning; }
    QString samplePath() const { return m_samplePath; }
    QString error() const { return m_error; }
    QStringList cloneSamples() const { return m_cloneSamples; }

    // Speaks `text` as the actor would. `actor` is AdProject's actor map:
    // voiceId plus the four settings.
    Q_INVOKABLE void audition(const QVariantMap &actor, const QString &text);
    Q_INVOKABLE void cancel();

    // What one audition of `text` costs: { amount, known }.
    Q_INVOKABLE QVariantMap estimate(const QString &text) const;

    // Recordings to clone from. Kept here rather than in the project: they are
    // an input to one operation, not part of the ad.
    Q_INVOKABLE void addCloneSamples(const QList<QUrl> &urls);
    Q_INVOKABLE void removeCloneSample(int index);

    // Uploads the samples and creates a voice on the user's account.
    Q_INVOKABLE void cloneVoice(const QString &name);

signals:
    void auditioningChanged();
    void cloningChanged();
    void samplePathChanged();
    void errorChanged();
    void cloneSamplesChanged();
    // The new voice is on the account; the caller decides whether to adopt it.
    void cloned(const QString &voiceId, const QString &name);

private:
    QString scratchDir() const;
    void setError(const QString &error);
    void setAuditioning(bool on);
    void setCloning(bool on);

    SettingsStore *m_settings;
    Registry *m_registry;
    Pricing *m_pricing;
    LogModel *m_log;

    QPointer<ProviderTask> m_task;
    QString m_samplePath;
    QString m_error;
    QStringList m_cloneSamples;
    bool m_auditioning = false;
    bool m_cloning = false;
};
