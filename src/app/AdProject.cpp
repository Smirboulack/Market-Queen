#include "AdProject.h"

#include "core/Paths.h"
#include "core/SettingsStore.h"
#include "providers/Registry.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTimer>

namespace {

// Same figure the script writer uses to size a script, so the duration shown
// while writing matches the one the pipeline plans against.
constexpr double kWordsPerSecond = 2.6;

// Long enough that a burst of keystrokes writes once, short enough that the
// draft on disk is never far behind what is on screen.
constexpr int kAutosaveDelayMs = 400;

QStringList toStringList(const QVariant &value)
{
    return value.toStringList();
}

} // namespace

AdProject::AdProject(SettingsStore *settings, Registry *registry, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_registry(registry)
    , m_autosave(new QTimer(this))
{
    m_autosave->setSingleShot(true);
    m_autosave->setInterval(kAutosaveDelayMs);
    connect(m_autosave, &QTimer::timeout, this, &AdProject::save);

    // Anything that changes the ad changes what Generate would run, so the
    // estimate re-prices itself without every setter having to remember.
    for (auto signal : {&AdProject::productChanged, &AdProject::actorChanged,
                        &AdProject::scenesChanged, &AdProject::scriptChanged,
                        &AdProject::renderChanged})
        connect(this, signal, this, &AdProject::requestChanged);

    load();
}

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------
void AdProject::setProductField(const QString &key, const QVariant &value)
{
    if (m_product.value(key) == value)
        return;
    m_product.insert(key, value);
    emit productChanged();
    emit stepsChanged();
    touch();
}

void AdProject::setActorField(const QString &key, const QVariant &value)
{
    if (m_actor.value(key) == value)
        return;
    m_actor.insert(key, value);
    emit actorChanged();
    emit stepsChanged();
    touch();
}

void AdProject::addProductImage(const QString &path)
{
    if (path.isEmpty())
        return;

    QStringList images = toStringList(m_product.value(QStringLiteral("images")));
    if (images.contains(path))
        return;

    images.append(path);
    m_product.insert(QStringLiteral("images"), images);
    emit productChanged();
    touch();
}

void AdProject::removeProductImage(int index)
{
    QStringList images = toStringList(m_product.value(QStringLiteral("images")));
    if (index < 0 || index >= images.size())
        return;

    images.removeAt(index);
    m_product.insert(QStringLiteral("images"), images);
    emit productChanged();
    touch();
}

void AdProject::setScript(const QString &script)
{
    if (m_script == script)
        return;
    m_script = script;
    emit scriptChanged();
    emit stepsChanged();
    touch();
}

void AdProject::setAspectRatio(const QString &aspect)
{
    if (m_aspectRatio == aspect)
        return;
    m_aspectRatio = aspect;
    emit renderChanged();
    touch();
}

void AdProject::setCaptions(bool on)
{
    if (m_captions == on)
        return;
    m_captions = on;
    emit renderChanged();
    touch();
}

void AdProject::clear()
{
    m_product.clear();
    m_actor.clear();
    m_scenes.clear();
    m_script.clear();
    m_aspectRatio = QStringLiteral("9:16");
    m_captions = true;
    m_currentStep = 0;

    emit productChanged();
    emit actorChanged();
    emit scenesChanged();
    emit scriptChanged();
    emit renderChanged();
    emit currentStepChanged();
    emit stepsChanged();
    emit cleared();
    touch();
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------
bool AdProject::stepValid(int step) const
{
    switch (step) {
    case StepProduct:
        return !m_product.value(QStringLiteral("name")).toString().trimmed().isEmpty();
    case StepActor:
        // S2 raises this to "a portrait has been generated or supplied".
        return !m_actor.value(QStringLiteral("brief")).toString().trimmed().isEmpty();
    case StepScript:
        return !m_script.trimmed().isEmpty();
    case StepSummary:
        return stepValid(StepProduct) && stepValid(StepActor) && stepValid(StepScript);
    default:
        return false;
    }
}

int AdProject::furthestStep() const
{
    // Walk forward while each step is satisfied: the first unsatisfied step is
    // as far as the user may go, which makes the first pass linear and every
    // pass after it free.
    for (int step = 0; step < StepCount; ++step) {
        if (!stepValid(step))
            return step;
    }
    return StepCount - 1;
}

QVariantList AdProject::stepStates() const
{
    const int furthest = furthestStep();

    QVariantList states;
    states.reserve(StepCount);
    for (int step = 0; step < StepCount; ++step) {
        states.append(QVariantMap{{QStringLiteral("valid"), stepValid(step)},
                                  {QStringLiteral("reachable"), step <= furthest}});
    }
    return states;
}

bool AdProject::complete() const
{
    return stepValid(StepSummary);
}

void AdProject::setCurrentStep(int step)
{
    const int wanted = qBound(0, step, int(StepCount) - 1);
    if (wanted > furthestStep() || m_currentStep == wanted)
        return;

    m_currentStep = wanted;
    emit currentStepChanged();
    touch();
}

double AdProject::spokenSeconds() const
{
    const QString text = m_script.trimmed();
    if (text.isEmpty())
        return 0.0;

    static const QRegularExpression whitespace(QStringLiteral("\\s+"));
    const int words = text.split(whitespace, Qt::SkipEmptyParts).size();
    return words / kWordsPerSecond;
}

// ---------------------------------------------------------------------------
// Adapter onto the current pipeline
// ---------------------------------------------------------------------------
QVariantMap AdProject::toRequest() const
{
    // Model choices still live in the preferences the pickers write, so the
    // studio and the old form agree on what "your usual models" means.
    const auto pickedProvider = [this](const QString &category) {
        const QString saved = m_settings->pref(category + QStringLiteral("Provider")).toString();
        return saved.isEmpty() ? m_registry->defaultProvider(category) : saved;
    };
    const auto pickedModel = [this](const QString &category, const QString &providerId) {
        const QString saved = m_settings->pref(category + QStringLiteral("Model")).toString();
        if (!saved.isEmpty())
            return saved;
        return m_registry->provider(providerId).value(QStringLiteral("defaultModel")).toString();
    };

    const QString textProvider = pickedProvider(QStringLiteral("text"));
    const QString imageProvider = pickedProvider(QStringLiteral("image"));
    const QString videoProvider = pickedProvider(QStringLiteral("video"));
    const QString voiceProvider = pickedProvider(QStringLiteral("voice"));

    const QStringList images = toStringList(m_product.value(QStringLiteral("images")));

    // The pipeline still sizes its shot count from a duration. We no longer ask
    // for one, so we hand it the length of the script instead -- which is the
    // rule the whole V3 plan is built on.
    const int duration = qMax(5, int(qRound(spokenSeconds())));

    return QVariantMap{
        {QStringLiteral("productName"), m_product.value(QStringLiteral("name")).toString().trimmed()},
        {QStringLiteral("productDescription"),
         m_product.value(QStringLiteral("description")).toString().trimmed()},
        {QStringLiteral("audience"), m_product.value(QStringLiteral("audience")).toString().trimmed()},
        {QStringLiteral("tone"), m_actor.value(QStringLiteral("tone")).toString()},
        {QStringLiteral("language"), m_actor.value(QStringLiteral("language")).toString()},
        {QStringLiteral("avatarBrief"), m_actor.value(QStringLiteral("brief")).toString().trimmed()},
        {QStringLiteral("extraInstructions"), m_actor.value(QStringLiteral("decor")).toString().trimmed()},
        {QStringLiteral("script"), m_script.trimmed()},
        {QStringLiteral("durationSeconds"), duration},
        {QStringLiteral("aspectRatio"), m_aspectRatio},
        // One image for now: the pipeline takes a single reference. S1 keeps
        // collecting them, S5 is what finally passes them all through.
        {QStringLiteral("productImagePath"), images.value(0)},
        {QStringLiteral("useProductPhotoAsFrame"), false},
        {QStringLiteral("textProvider"), textProvider},
        {QStringLiteral("textModel"), pickedModel(QStringLiteral("text"), textProvider)},
        {QStringLiteral("imageProvider"), imageProvider},
        {QStringLiteral("imageModel"), pickedModel(QStringLiteral("image"), imageProvider)},
        {QStringLiteral("videoProvider"), videoProvider},
        {QStringLiteral("videoModel"), pickedModel(QStringLiteral("video"), videoProvider)},
        {QStringLiteral("voiceProvider"), voiceProvider},
        {QStringLiteral("voiceModel"), pickedModel(QStringLiteral("voice"), voiceProvider)},
        {QStringLiteral("voiceId"), m_actor.value(QStringLiteral("voiceId")).toString()},
        {QStringLiteral("captionsEnabled"), m_captions},
        {QStringLiteral("captionsProvider"), QStringLiteral("openai-whisper")},
        {QStringLiteral("captionsModel"), QStringLiteral("whisper-1")},
    };
}

// ---------------------------------------------------------------------------
// Draft persistence
// ---------------------------------------------------------------------------
QString AdProject::draftFile() const
{
    return QDir(paths::configDir()).filePath(QStringLiteral("draft.json"));
}

void AdProject::touch()
{
    if (!m_loading)
        m_autosave->start();
}

void AdProject::save()
{
    const QJsonObject root{
        {QStringLiteral("schemaVersion"), 3},
        {QStringLiteral("product"), QJsonObject::fromVariantMap(m_product)},
        {QStringLiteral("actor"), QJsonObject::fromVariantMap(m_actor)},
        {QStringLiteral("scenes"), QJsonArray::fromVariantList(m_scenes)},
        {QStringLiteral("script"), m_script},
        {QStringLiteral("aspectRatio"), m_aspectRatio},
        {QStringLiteral("captions"), m_captions},
        {QStringLiteral("currentStep"), m_currentStep},
    };

    if (paths::ensureDir(paths::configDir()).isEmpty())
        return;

    QFile file(draftFile());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

void AdProject::load()
{
    QFile file(draftFile());
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    if (root.isEmpty())
        return;

    m_loading = true;

    m_product = root.value(QStringLiteral("product")).toObject().toVariantMap();
    m_actor = root.value(QStringLiteral("actor")).toObject().toVariantMap();
    m_scenes = root.value(QStringLiteral("scenes")).toArray().toVariantList();
    m_script = root.value(QStringLiteral("script")).toString();
    m_aspectRatio = root.value(QStringLiteral("aspectRatio")).toString(QStringLiteral("9:16"));
    m_captions = root.value(QStringLiteral("captions")).toBool(true);
    m_currentStep = root.value(QStringLiteral("currentStep")).toInt();

    // A draft saved on a step that is no longer satisfied would otherwise open
    // on a panel the rail says is unreachable.
    m_currentStep = qBound(0, m_currentStep, furthestStep());

    m_loading = false;

    emit productChanged();
    emit actorChanged();
    emit scenesChanged();
    emit scriptChanged();
    emit renderChanged();
    emit currentStepChanged();
    emit stepsChanged();
}
