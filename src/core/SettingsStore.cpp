#include "SettingsStore.h"

#include "Crypto.h"
#include "Paths.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

SettingsStore::SettingsStore(QObject *parent)
    : QObject(parent)
{
    load();
}

QString SettingsStore::settingsFile() const
{
    return QDir(paths::configDir()).filePath(QStringLiteral("settings.json"));
}

QString SettingsStore::secretsFile() const
{
    return QDir(paths::configDir()).filePath(QStringLiteral("secrets.bin"));
}

QString SettingsStore::configLocation() const
{
    return QDir::toNativeSeparators(paths::configDir());
}

void SettingsStore::load()
{
    m_loading = true;

    QFile settings(settingsFile());
    if (settings.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(settings.readAll());
        if (doc.isObject())
            m_prefs = doc.object().toVariantMap();
    }

    QFile secrets(secretsFile());
    if (secrets.open(QIODevice::ReadOnly)) {
        bool ok = false;
        const QByteArray plain = crypto::unseal(secrets.readAll(), crypto::deviceKey(), &ok);
        if (ok) {
            const QJsonDocument doc = QJsonDocument::fromJson(plain);
            const QJsonObject obj = doc.object();
            for (auto it = obj.constBegin(); it != obj.constEnd(); ++it)
                m_secrets.insert(it.key(), it.value().toString());
        }
        // A failed unseal means the file came from another machine or was
        // tampered with; we start from an empty set rather than crash.
    }

    if (!m_prefs.contains(QStringLiteral("projectsDir")))
        m_prefs.insert(QStringLiteral("projectsDir"), paths::defaultProjectsDir());

    m_loading = false;
}

void SettingsStore::save()
{
    if (m_loading)
        return;
    if (paths::ensureDir(paths::configDir()).isEmpty())
        return;

    QSaveFile file(settingsFile());
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(QJsonObject::fromVariantMap(m_prefs)).toJson(QJsonDocument::Indented));
        file.commit();
    }
}

void SettingsStore::saveSecrets()
{
    if (paths::ensureDir(paths::configDir()).isEmpty())
        return;

    QJsonObject obj;
    for (auto it = m_secrets.constBegin(); it != m_secrets.constEnd(); ++it) {
        if (!it.value().isEmpty())
            obj.insert(it.key(), it.value());
    }

    const QByteArray blob =
        crypto::seal(QJsonDocument(obj).toJson(QJsonDocument::Compact), crypto::deviceKey());

    QSaveFile file(secretsFile());
    if (file.open(QIODevice::WriteOnly)) {
        file.write(blob);
        file.commit();
        QFile::setPermissions(secretsFile(), QFile::ReadOwner | QFile::WriteOwner);
    }
}

QString SettingsStore::projectsDir() const
{
    const QString dir = m_prefs.value(QStringLiteral("projectsDir")).toString();
    return dir.isEmpty() ? paths::defaultProjectsDir() : dir;
}

void SettingsStore::setProjectsDir(const QString &dir)
{
    if (dir == projectsDir())
        return;
    m_prefs.insert(QStringLiteral("projectsDir"),
                   dir.isEmpty() ? paths::defaultProjectsDir() : dir);
    save();
    emit projectsDirChanged();
}

QString SettingsStore::ffmpegPath() const
{
    return m_prefs.value(QStringLiteral("ffmpegPath")).toString();
}

void SettingsStore::setFfmpegPath(const QString &path)
{
    if (path == ffmpegPath())
        return;
    m_prefs.insert(QStringLiteral("ffmpegPath"), path);
    save();
    emit ffmpegPathChanged();
}

bool SettingsStore::darkMode() const
{
    return m_prefs.value(QStringLiteral("darkMode"), false).toBool();
}

void SettingsStore::setDarkMode(bool dark)
{
    if (dark == darkMode())
        return;
    m_prefs.insert(QStringLiteral("darkMode"), dark);
    save();
    emit darkModeChanged();
}

QString SettingsStore::uiLanguage() const
{
    return m_prefs.value(QStringLiteral("uiLanguage")).toString();
}

void SettingsStore::setUiLanguage(const QString &code)
{
    if (code == uiLanguage())
        return;
    m_prefs.insert(QStringLiteral("uiLanguage"), code);
    save();
    emit uiLanguageChanged();
}

QByteArray SettingsStore::environmentVariableFor(const QString &credentialId)
{
    static const QHash<QString, QByteArray> map = {
        {QStringLiteral("openai"), "OPENAI_API_KEY"},
        {QStringLiteral("anthropic"), "ANTHROPIC_API_KEY"},
        {QStringLiteral("gemini"), "GEMINI_API_KEY"},
        {QStringLiteral("fal"), "FAL_KEY"},
        {QStringLiteral("replicate"), "REPLICATE_API_TOKEN"},
        {QStringLiteral("elevenlabs"), "ELEVENLABS_API_KEY"},
    };
    return map.value(credentialId);
}

QString SettingsStore::apiKey(const QString &credentialId) const
{
    const QString stored = m_secrets.value(credentialId);
    if (!stored.isEmpty())
        return stored;

    const QByteArray envName = environmentVariableFor(credentialId);
    if (!envName.isEmpty()) {
        const QByteArray value = qgetenv(envName.constData());
        if (!value.isEmpty())
            return QString::fromUtf8(value).trimmed();
    }
    return {};
}

bool SettingsStore::hasApiKey(const QString &credentialId) const
{
    return !apiKey(credentialId).isEmpty();
}

bool SettingsStore::apiKeyFromEnvironment(const QString &credentialId) const
{
    if (!m_secrets.value(credentialId).isEmpty())
        return false;
    const QByteArray envName = environmentVariableFor(credentialId);
    return !envName.isEmpty() && !qgetenv(envName.constData()).isEmpty();
}

void SettingsStore::setApiKey(const QString &credentialId, const QString &value)
{
    const QString trimmed = value.trimmed();
    if (m_secrets.value(credentialId) == trimmed)
        return;

    if (trimmed.isEmpty())
        m_secrets.remove(credentialId);
    else
        m_secrets.insert(credentialId, trimmed);

    saveSecrets();
    emit apiKeysChanged();
}

QVariant SettingsStore::pref(const QString &key, const QVariant &fallback) const
{
    const QVariant value = m_prefs.value(key);
    return value.isValid() ? value : fallback;
}

void SettingsStore::setPref(const QString &key, const QVariant &value)
{
    if (m_prefs.value(key) == value)
        return;
    m_prefs.insert(key, value);
    save();
}
