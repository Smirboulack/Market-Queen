#include "Director.h"

#include "Casting.h"
#include "core/Http.h"
#include "core/LogModel.h"
#include "core/Pricing.h"
#include "core/SettingsStore.h"
#include "providers/ProviderTask.h"
#include "providers/Registry.h"
#include "providers/Types.h"

#include <QFileInfo>

namespace {

// The direction pass is one short answer per scene plus the rules. Close enough
// to price it honestly before the call, which is all the estimate promises.
constexpr double kOutputTokensPerScene = 160.0;
constexpr double kOverheadTokens = 900.0;
constexpr double kTokensPerMillion = 1'000'000.0;

QStringList linesOf(const QVariantList &scenes, const char *key)
{
    QStringList out;
    for (const QVariant &entry : scenes) {
        const QString value = entry.toMap().value(QString::fromLatin1(key)).toString().trimmed();
        if (!entry.toMap().value(QStringLiteral("line")).toString().trimmed().isEmpty())
            out.append(value);
    }
    return out;
}

} // namespace

Director::Director(SettingsStore *settings, Registry *registry, Pricing *pricing, Casting *casting,
                   LogModel *log, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_registry(registry)
    , m_pricing(pricing)
    , m_casting(casting)
    , m_log(log)
{
}

void Director::setRunning(bool on)
{
    if (m_running == on)
        return;
    m_running = on;
    emit runningChanged();
}

void Director::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

void Director::cancel()
{
    if (m_task && !m_task->isFinished())
        m_task->cancel();
    m_task = nullptr;
    setRunning(false);
}

QVariantMap Director::estimate(const QVariantMap &request) const
{
    QString providerId = request.value(QStringLiteral("textProvider")).toString();
    if (providerId.isEmpty())
        providerId = m_registry->defaultProvider(QStringLiteral("text"));

    const QString model = m_registry->resolveModel(
        providerId, request.value(QStringLiteral("textModel")).toString());

    const QVariantMap unit = m_pricing->unitPrice(model);
    if (unit.isEmpty() || unit.value(QStringLiteral("unit")).toString() != QLatin1String("tokens"))
        return {{QStringLiteral("known"), false}, {QStringLiteral("amount"), 0.0}};

    const int scenes = request.value(QStringLiteral("scenes")).toList().size();
    const double tokens = kOverheadTokens + scenes * kOutputTokensPerScene;

    // unitPrice reports the output rate for token models, which is the larger
    // of the two -- so this rounds up rather than flattering the total.
    return {{QStringLiteral("known"), true},
            {QStringLiteral("amount"),
             unit.value(QStringLiteral("amount")).toDouble() * tokens / kTokensPerMillion}};
}

void Director::direct(const QVariantMap &request)
{
    if (m_running)
        return;

    const QVariantList scenes = request.value(QStringLiteral("scenes")).toList();
    const QStringList lines = linesOf(scenes, "line");
    if (lines.isEmpty()) {
        setError(tr("Write at least one line first."));
        return;
    }

    QString providerId = request.value(QStringLiteral("textProvider")).toString();
    if (providerId.isEmpty())
        providerId = m_registry->defaultProvider(QStringLiteral("text"));

    prov::ScriptRequest req;
    req.mode = prov::ScriptRequest::Mode::DirectVisuals;
    req.apiKey = m_settings->apiKey(m_registry->credentialFor(providerId));
    req.model = m_registry->resolveModel(providerId,
                                         request.value(QStringLiteral("textModel")).toString());
    req.productName = request.value(QStringLiteral("productName")).toString();
    req.productDescription = request.value(QStringLiteral("productDescription")).toString();
    req.actorBrief = request.value(QStringLiteral("avatarBrief")).toString();
    req.actorDecor = request.value(QStringLiteral("extraInstructions")).toString();
    req.directionRules = m_casting->directionRules();
    req.lines = lines;
    req.kinds = linesOf(scenes, "kind");

    // The product photo, so the model describes the real object rather than an
    // idea of it. The actor's portrait is not sent: it is the frame generator
    // that needs the face, not the writer.
    const QString productImage = request.value(QStringLiteral("productImagePath")).toString();
    if (!productImage.isEmpty() && QFileInfo::exists(productImage))
        req.referenceImageDataUri = http::imageToDataUri(productImage);

    ProviderTask *task = providers::script(providerId, req, this);
    if (!task) {
        setError(tr("No text provider called %1.").arg(providerId));
        return;
    }

    setError({});
    setRunning(true);
    m_task = task;

    m_log->append(LogModel::Info,
                  tr("Directing %1 scene(s) with %2.").arg(lines.size()).arg(req.model));

    connect(task, &ProviderTask::failed, this, [this](const QString &error) {
        m_log->append(LogModel::Error, tr("Direction failed: %1").arg(error));
        setError(error);
        setRunning(false);
    });

    connect(task, &ProviderTask::succeeded, this, [this, count = lines.size()](
                                                      const QVariantMap &result) {
        const QVariantList shots = result.value(QStringLiteral("shots")).toList();
        setRunning(false);

        if (shots.isEmpty()) {
            setError(tr("The model returned no shots."));
            return;
        }

        // Short answers are applied as far as they go rather than dropped: five
        // directed scenes out of six beats none, and the gap is visible in the
        // editor.
        if (shots.size() < count) {
            m_log->append(LogModel::Warning,
                          tr("Only %1 of %2 scenes came back directed.")
                              .arg(shots.size()).arg(count));
        }

        m_log->append(LogModel::Success, tr("%1 scene(s) directed.").arg(shots.size()));
        emit directed(shots);
    });
}
