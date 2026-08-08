#include "VoiceBooth.h"

#include "core/LogModel.h"
#include "core/Paths.h"
#include "core/Pricing.h"
#include "core/SettingsStore.h"
#include "providers/ProviderTask.h"
#include "providers/Registry.h"
#include "providers/Types.h"
#include "providers/VoiceProviders.h"

#include <QDateTime>
#include <QDir>
#include <QFile>

namespace {

// ElevenLabs bills text-to-speech per thousand characters.
constexpr double kCharsPerKilo = 1000.0;

double settingOr(const QVariantMap &actor, const char *key, double fallback)
{
    const QVariant value = actor.value(QString::fromLatin1(key));
    return value.isValid() ? value.toDouble() : fallback;
}

} // namespace

VoiceBooth::VoiceBooth(SettingsStore *settings, Registry *registry, Pricing *pricing, LogModel *log,
                       QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_registry(registry)
    , m_pricing(pricing)
    , m_log(log)
{
}

QString VoiceBooth::scratchDir() const
{
    return paths::ensureDir(QDir(paths::configDir()).filePath(QStringLiteral("auditions")));
}

void VoiceBooth::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

void VoiceBooth::setAuditioning(bool on)
{
    if (m_auditioning == on)
        return;
    m_auditioning = on;
    emit auditioningChanged();
}

void VoiceBooth::setCloning(bool on)
{
    if (m_cloning == on)
        return;
    m_cloning = on;
    emit cloningChanged();
}

void VoiceBooth::cancel()
{
    if (m_task && !m_task->isFinished())
        m_task->cancel();
    m_task = nullptr;
    setAuditioning(false);
    setCloning(false);
}

// ---------------------------------------------------------------------------
// Audition
// ---------------------------------------------------------------------------
QVariantMap VoiceBooth::estimate(const QString &text) const
{
    QString providerId = m_settings->pref(QStringLiteral("voiceProvider")).toString();
    if (providerId.isEmpty())
        providerId = m_registry->defaultProvider(QStringLiteral("voice"));

    const QString model = m_registry->resolveModel(
        providerId, m_settings->pref(QStringLiteral("voiceModel")).toString());

    const QVariantMap unit = m_pricing->unitPrice(model);
    if (unit.isEmpty())
        return {{QStringLiteral("known"), false}, {QStringLiteral("amount"), 0.0}};

    const double kilos = text.size() / kCharsPerKilo;
    return {{QStringLiteral("known"), true},
            {QStringLiteral("amount"), unit.value(QStringLiteral("amount")).toDouble() * kilos}};
}

void VoiceBooth::audition(const QVariantMap &actor, const QString &text)
{
    if (m_auditioning || m_cloning)
        return;

    const QString line = text.trimmed();
    if (line.isEmpty()) {
        setError(tr("Write a line for them to say."));
        return;
    }

    const QString dir = scratchDir();
    if (dir.isEmpty()) {
        setError(tr("Could not create the auditions folder."));
        return;
    }

    QString providerId = m_settings->pref(QStringLiteral("voiceProvider")).toString();
    if (providerId.isEmpty())
        providerId = m_registry->defaultProvider(QStringLiteral("voice"));

    prov::VoiceRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    request.model = m_registry->resolveModel(
        providerId, m_settings->pref(QStringLiteral("voiceModel")).toString());
    request.voiceId = actor.value(QStringLiteral("voiceId")).toString();
    request.text = line;
    request.stability = settingOr(actor, "voiceStability", 0.45);
    request.similarity = settingOr(actor, "voiceSimilarity", 0.8);
    request.style = settingOr(actor, "voiceStyle", 0.35);
    request.speed = settingOr(actor, "voiceSpeed", 1.0);

    ProviderTask *task = providers::voice(providerId, request, this);
    if (!task) {
        setError(tr("No voice provider called %1.").arg(providerId));
        return;
    }

    setError({});
    setAuditioning(true);
    m_task = task;

    connect(task, &ProviderTask::failed, this, [this](const QString &error) {
        m_log->append(LogModel::Error, tr("Audition failed: %1").arg(error));
        setError(error);
        setAuditioning(false);
    });

    connect(task, &ProviderTask::succeeded, this, [this, dir](const QVariantMap &result) {
        const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
        const QString extension =
            result.value(QStringLiteral("extension"), QStringLiteral("mp3")).toString();

        // A fresh name every time: an audio player that already has the file
        // open will not reload one that kept its path.
        const QString path =
            QDir(dir).filePath(QStringLiteral("audition-%1.%2")
                                   .arg(QDateTime::currentDateTime().toString(
                                            QStringLiteral("yyyyMMdd-HHmmss-zzz")),
                                        extension));

        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            setError(tr("Could not write %1.").arg(QDir::toNativeSeparators(path)));
            setAuditioning(false);
            return;
        }
        file.write(data);
        file.close();

        m_samplePath = path;
        emit samplePathChanged();
        setAuditioning(false);
    });
}

// ---------------------------------------------------------------------------
// Cloning
// ---------------------------------------------------------------------------
void VoiceBooth::addCloneSamples(const QList<QUrl> &urls)
{
    const int before = m_cloneSamples.size();
    for (const QUrl &url : urls) {
        const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
        if (!path.isEmpty() && !m_cloneSamples.contains(path))
            m_cloneSamples.append(path);
    }
    if (m_cloneSamples.size() != before)
        emit cloneSamplesChanged();
}

void VoiceBooth::removeCloneSample(int index)
{
    if (index < 0 || index >= m_cloneSamples.size())
        return;
    m_cloneSamples.removeAt(index);
    emit cloneSamplesChanged();
}

void VoiceBooth::cloneVoice(const QString &name)
{
    if (m_auditioning || m_cloning)
        return;

    if (m_cloneSamples.isEmpty()) {
        setError(tr("Add at least one recording first."));
        return;
    }

    prov::VoiceCloneRequest request;
    request.apiKey = m_settings->apiKey(m_registry->credentialFor(QStringLiteral("elevenlabs")));
    request.name = name.trimmed().isEmpty() ? tr("Market Queen voice") : name.trimmed();
    request.description = tr("Cloned with Market Queen.");
    request.samplePaths = m_cloneSamples;

    auto *task = new ElevenLabsVoiceCloneTask(request, this);

    setError({});
    setCloning(true);
    m_task = task;

    m_log->append(LogModel::Info,
                  tr("Cloning a voice from %1 recording(s).").arg(m_cloneSamples.size()));

    connect(task, &ProviderTask::failed, this, [this](const QString &error) {
        m_log->append(LogModel::Error, tr("Cloning failed: %1").arg(error));
        setError(error);
        setCloning(false);
    });

    connect(task, &ProviderTask::succeeded, this, [this](const QVariantMap &result) {
        const QString voiceId = result.value(QStringLiteral("voiceId")).toString();
        const QString name = result.value(QStringLiteral("name")).toString();
        m_log->append(LogModel::Success, tr("Voice \"%1\" is on your account.").arg(name));
        setCloning(false);
        emit cloned(voiceId, name);
    });
}
