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

// Casting: turns a description into candidate portraits.
//
// The whole point of this class is the prompt it builds. Image models default
// to advertising photography, and asking them for a "UGC look" does not move
// them -- they comply in words and still render a campaign shot. The scaffold in
// resources/casting.json names the camera, imposes concrete flaws and forbids
// the commercial vocabulary by name. It is data, not code, because this is the
// part of the product that needs the most iteration.
//
// Candidates are generated in parallel and land in a scratch folder. Only the
// one the user keeps is copied anywhere permanent.
class Casting : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    // [{ path, prompt }] -- newest batch, oldest first.
    Q_PROPERTY(QVariantList candidates READ candidates NOTIFY candidatesChanged)
    Q_PROPERTY(int received READ received NOTIFY progressChanged)
    Q_PROPERTY(int requested READ requested NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    // Where a casting.json would go to override the bundled scaffold.
    Q_PROPERTY(QString overridePath READ overridePath CONSTANT)
    Q_PROPERTY(bool overridden READ overridden CONSTANT)

public:
    Casting(SettingsStore *settings, Registry *registry, Pricing *pricing, LogModel *log,
            QObject *parent = nullptr);

    bool running() const { return m_requested > 0 && m_received + m_failed < m_requested; }
    QVariantList candidates() const { return m_candidates; }
    int received() const { return m_received; }
    int requested() const { return m_requested; }
    QString error() const { return m_error; }
    QString overridePath() const;
    bool overridden() const { return m_overridden; }

    // Fires `count` portrait requests at once. `actor` is AdProject's actor map:
    // brief, decor, traits, referenceImages.
    Q_INVOKABLE void generate(const QVariantMap &actor, int count = 4);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reset();

    // The exact text that would be sent. Shown in the UI: the realism work is
    // the product here, so it should be inspectable rather than magic.
    Q_INVOKABLE QString buildPrompt(const QVariantMap &actor) const;

    // The house style rules, shared with the director: an actor cast against
    // advertising photography and then dropped into a commercial storyboard
    // still produces a commercial.
    QString directionRules() const { return m_directionRules; }

    // What one batch costs: { amount, known }.
    Q_INVOKABLE QVariantMap estimate(int count) const;

signals:
    void runningChanged();
    void candidatesChanged();
    void progressChanged();
    void errorChanged();

private:
    bool loadScaffold(const QString &path);
    QString scratchDir() const;
    void setError(const QString &error);
    void finishOne();

    SettingsStore *m_settings;
    Registry *m_registry;
    Pricing *m_pricing;
    LogModel *m_log;

    QVariantMap m_portrait;   // fragment id -> text, with {slots}
    QStringList m_order;
    QStringList m_traitOrder;
    QString m_directionRules;
    QVariantMap m_fallbacks;
    bool m_overridden = false;

    QVariantList m_candidates;
    QList<QPointer<ProviderTask>> m_tasks;
    int m_requested = 0;
    int m_received = 0;
    int m_failed = 0;
    QString m_error;
};
