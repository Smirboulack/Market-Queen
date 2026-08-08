#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Casting;
class LogModel;
class Pricing;
class ProviderTask;
class Registry;
class SettingsStore;

// Turns the user's lines into shots.
//
// This is the only LLM call left in the studio, and it deliberately never
// touches a spoken word: the user writes what is said, the model only says what
// the camera sees. It works from the same realism rules as the casting prompt,
// because a perfect actor dropped into a commercial storyboard still produces a
// commercial.
class Director : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    Director(SettingsStore *settings, Registry *registry, Pricing *pricing, Casting *casting,
             LogModel *log, QObject *parent = nullptr);

    bool running() const { return m_running; }
    QString error() const { return m_error; }

    // `project` is AdProject's request map: product, actor and scenes.
    Q_INVOKABLE void direct(const QVariantMap &request);
    Q_INVOKABLE void cancel();

    // What one direction pass costs: { amount, known }.
    Q_INVOKABLE QVariantMap estimate(const QVariantMap &request) const;

signals:
    void runningChanged();
    void errorChanged();
    // One entry per scene, in order: { imagePrompt, videoPrompt }.
    void directed(const QVariantList &shots);

private:
    void setRunning(bool on);
    void setError(const QString &error);

    SettingsStore *m_settings;
    Registry *m_registry;
    Pricing *m_pricing;
    Casting *m_casting;
    LogModel *m_log;

    QPointer<ProviderTask> m_task;
    bool m_running = false;
    QString m_error;
};
