#include "Casting.h"

#include "core/Http.h"
#include "core/LogModel.h"
#include "core/Paths.h"
#include "core/Pricing.h"
#include "core/SettingsStore.h"
#include "providers/ProviderTask.h"
#include "providers/Registry.h"
#include "providers/Types.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {

constexpr const char *kBundled = ":/qt/qml/MarketQueen/resources/casting.json";
constexpr const char *kFileName = "casting.json";

// Portraits are shot vertical because the ad is. There is no control for it:
// a landscape reference for a 9:16 ad would only ever be a mistake.
constexpr const char *kPortraitAspect = "9:16";

QStringList toStringList(const QVariant &value)
{
    return value.toStringList();
}

} // namespace

Casting::Casting(SettingsStore *settings, Registry *registry, Pricing *pricing, LogModel *log,
                 QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_registry(registry)
    , m_pricing(pricing)
    , m_log(log)
{
    // The user's file wins outright rather than merging, for the same reason
    // the price catalogue does: a half-overridden scaffold would be impossible
    // to reason about when a portrait comes out wrong.
    m_overridden = loadScaffold(overridePath());
    if (!m_overridden)
        loadScaffold(QString::fromLatin1(kBundled));
}

QString Casting::overridePath() const
{
    return QDir(paths::configDir()).filePath(QString::fromLatin1(kFileName));
}

bool Casting::loadScaffold(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;

    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    const QJsonObject portrait = root.value(QStringLiteral("portrait")).toObject();
    if (portrait.isEmpty())
        return false;

    m_portrait = portrait.toVariantMap();
    m_fallbacks = root.value(QStringLiteral("fallbacks")).toObject().toVariantMap();
    m_directionRules = root.value(QStringLiteral("direction")).toString();

    m_order.clear();
    const QJsonArray order = root.value(QStringLiteral("order")).toArray();
    for (const QJsonValue &entry : order)
        m_order.append(entry.toString());

    m_traitOrder.clear();
    const QJsonArray traits = root.value(QStringLiteral("traitOrder")).toArray();
    for (const QJsonValue &entry : traits)
        m_traitOrder.append(entry.toString());

    // An override that forgot the order array still works: fall back to every
    // fragment the file defines, in the order the file lists them.
    if (m_order.isEmpty())
        m_order = m_portrait.keys();

    return true;
}

// ---------------------------------------------------------------------------
// The prompt
// ---------------------------------------------------------------------------
QString Casting::buildPrompt(const QVariantMap &actor) const
{
    // The subject line is the structured traits, then the free description.
    // Traits come first so a bare "tired" in the brief qualifies a person the
    // model has already been told the age and build of.
    QStringList subject;
    const QVariantMap traits = actor.value(QStringLiteral("traits")).toMap();

    // Named order first, then anything the scaffold did not list, so an added
    // trait still reaches the prompt instead of disappearing silently.
    QStringList keys = m_traitOrder;
    for (const QString &key : traits.keys()) {
        if (!keys.contains(key))
            keys.append(key);
    }

    for (const QString &key : keys) {
        const QString fragment = traits.value(key).toString().trimmed();
        if (!fragment.isEmpty())
            subject.append(fragment);
    }

    const QString brief = actor.value(QStringLiteral("brief")).toString().trimmed();
    if (!brief.isEmpty())
        subject.append(brief);

    QString subjectText = subject.join(QStringLiteral(", "));
    if (subjectText.isEmpty())
        subjectText = m_fallbacks.value(QStringLiteral("subject")).toString();

    QString locationText = actor.value(QStringLiteral("decor")).toString().trimmed();
    if (locationText.isEmpty())
        locationText = m_fallbacks.value(QStringLiteral("location")).toString();

    QStringList parts;
    for (const QString &key : m_order) {
        QString fragment = m_portrait.value(key).toString().trimmed();
        if (fragment.isEmpty())
            continue;
        fragment.replace(QStringLiteral("{subject}"), subjectText);
        fragment.replace(QStringLiteral("{location}"), locationText);
        parts.append(fragment);
    }

    return parts.join(QStringLiteral(" "));
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------
QVariantMap Casting::estimate(int count) const
{
    const QString providerId = m_settings->pref(QStringLiteral("imageProvider")).toString();
    const QString resolved = m_registry->resolveModel(
        providerId.isEmpty() ? m_registry->defaultProvider(QStringLiteral("image")) : providerId,
        m_settings->pref(QStringLiteral("imageModel")).toString());

    const QVariantMap unit = m_pricing->unitPrice(resolved);
    if (unit.isEmpty())
        return QVariantMap{{QStringLiteral("known"), false}, {QStringLiteral("amount"), 0.0}};

    return QVariantMap{{QStringLiteral("known"), true},
                       {QStringLiteral("amount"), unit.value(QStringLiteral("amount")).toDouble() * count}};
}

QString Casting::scratchDir() const
{
    return paths::ensureDir(QDir(paths::configDir()).filePath(QStringLiteral("casting")));
}

void Casting::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

void Casting::reset()
{
    cancel();
    m_candidates.clear();
    m_requested = m_received = m_failed = 0;
    setError({});
    emit candidatesChanged();
    emit progressChanged();
    emit runningChanged();
}

void Casting::cancel()
{
    for (const QPointer<ProviderTask> &task : m_tasks) {
        if (task && !task->isFinished())
            task->cancel();
    }
    m_tasks.clear();

    if (m_requested > 0) {
        m_requested = m_received + m_failed;
        emit progressChanged();
        emit runningChanged();
    }
}

void Casting::finishOne()
{
    emit progressChanged();
    if (m_received + m_failed >= m_requested) {
        // Every request failed: the batch produced nothing and the reason is
        // already in the log, but the panel needs to say so where the user is
        // looking.
        if (m_received == 0 && m_failed > 0 && m_error.isEmpty())
            setError(tr("No portrait came back. Check the log."));
        emit runningChanged();
    }
}

void Casting::generate(const QVariantMap &actor, int count)
{
    if (running())
        return;

    const QString dir = scratchDir();
    if (dir.isEmpty()) {
        setError(tr("Could not create the casting folder."));
        return;
    }

    // A new batch replaces the previous one: keeping candidates across batches
    // would make the grid a pile rather than a choice.
    m_candidates.clear();
    m_tasks.clear();
    m_received = m_failed = 0;
    m_requested = qMax(1, count);
    setError({});
    emit candidatesChanged();
    emit progressChanged();
    emit runningChanged();

    QString providerId = m_settings->pref(QStringLiteral("imageProvider")).toString();
    if (providerId.isEmpty())
        providerId = m_registry->defaultProvider(QStringLiteral("image"));

    const QString requestedModel = m_settings->pref(QStringLiteral("imageModel")).toString();
    const QString model = m_registry->resolveModel(providerId, requestedModel);
    const QString prompt = buildPrompt(actor);

    // A photo of the real person, when there is one, is what keeps the same
    // face across the whole batch and every later shot.
    QString referenceUri;
    const QStringList references = toStringList(actor.value(QStringLiteral("referenceImages")));
    if (!references.isEmpty())
        referenceUri = http::imageToDataUri(references.first());

    m_log->append(LogModel::Info, tr("Casting %1 portrait(s) with %2.").arg(m_requested).arg(model));

    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));

    for (int i = 0; i < m_requested; ++i) {
        prov::ImageRequest request;
        request.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
        request.model = model;
        request.prompt = prompt;
        request.aspectRatio = QString::fromLatin1(kPortraitAspect);
        request.referenceImageDataUri = referenceUri;

        ProviderTask *task = providers::image(providerId, request, this);
        if (!task) {
            ++m_failed;
            setError(tr("No image provider called %1.").arg(providerId));
            finishOne();
            continue;
        }

        m_tasks.append(task);

        connect(task, &ProviderTask::failed, this, [this](const QString &error) {
            ++m_failed;
            m_log->append(LogModel::Error, tr("Portrait failed: %1").arg(error));
            setError(error);
            finishOne();
        });

        connect(task, &ProviderTask::succeeded, this,
                [this, dir, stamp, i, prompt](const QVariantMap &result) {
            const QByteArray data = result.value(QStringLiteral("data")).toByteArray();
            const QString extension =
                result.value(QStringLiteral("extension"), QStringLiteral("png")).toString();
            const QString path =
                QDir(dir).filePath(QStringLiteral("%1-%2.%3").arg(stamp).arg(i + 1).arg(extension));

            QFile file(path);
            if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                ++m_failed;
                setError(tr("Could not write %1.").arg(QDir::toNativeSeparators(path)));
                finishOne();
                return;
            }
            file.write(data);
            file.close();

            ++m_received;
            m_candidates.append(QVariantMap{{QStringLiteral("path"), path},
                                            {QStringLiteral("prompt"), prompt}});
            emit candidatesChanged();
            finishOne();
        });
    }
}
