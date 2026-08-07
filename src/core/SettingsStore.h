#pragma once

#include <QHash>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Persists user preferences (plain JSON) and API keys (encrypted blob) under
// the platform config directory.
class SettingsStore : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(QString projectsDir READ projectsDir WRITE setProjectsDir NOTIFY projectsDirChanged)
    Q_PROPERTY(QString ffmpegPath READ ffmpegPath WRITE setFfmpegPath NOTIFY ffmpegPathChanged)
    Q_PROPERTY(QString configLocation READ configLocation CONSTANT)
    Q_PROPERTY(bool darkMode READ darkMode WRITE setDarkMode NOTIFY darkModeChanged)
    Q_PROPERTY(QString uiLanguage READ uiLanguage WRITE setUiLanguage NOTIFY uiLanguageChanged)

public:
    explicit SettingsStore(QObject *parent = nullptr);

    QString projectsDir() const;
    void setProjectsDir(const QString &dir);

    QString ffmpegPath() const;
    void setFfmpegPath(const QString &path);

    QString configLocation() const;

    // Light is the default; the choice is remembered.
    bool darkMode() const;
    void setDarkMode(bool dark);

    // Empty means "follow the system locale".
    QString uiLanguage() const;
    void setUiLanguage(const QString &code);

    // Secrets. Reading falls back to the provider's conventional environment
    // variable, so CI and power users can avoid the on-disk store entirely.
    Q_INVOKABLE QString apiKey(const QString &credentialId) const;
    Q_INVOKABLE bool hasApiKey(const QString &credentialId) const;
    Q_INVOKABLE void setApiKey(const QString &credentialId, const QString &value);
    Q_INVOKABLE bool apiKeyFromEnvironment(const QString &credentialId) const;

    // Free-form preferences (last used models, toggles, ...).
    Q_INVOKABLE QVariant pref(const QString &key, const QVariant &fallback = {}) const;
    Q_INVOKABLE void setPref(const QString &key, const QVariant &value);

    Q_INVOKABLE void save();

signals:
    void projectsDirChanged();
    void ffmpegPathChanged();
    void apiKeysChanged();
    void darkModeChanged();
    void uiLanguageChanged();

private:
    void load();
    void saveSecrets();
    QString settingsFile() const;
    QString secretsFile() const;
    static QByteArray environmentVariableFor(const QString &credentialId);

    QVariantMap m_prefs;
    QHash<QString, QString> m_secrets;
    bool m_loading = false;
};
