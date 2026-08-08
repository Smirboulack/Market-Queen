#include "Pricing.h"

#include "Paths.h"
#include "providers/Registry.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

#include <cmath>

namespace {

constexpr const char *kBundled = ":/qt/qml/MarketQueen/resources/pricing.json";
constexpr const char *kFileName = "pricing.json";

// A speaker in an ad delivers roughly this many words a second; the pipeline
// uses the same number when ffmpeg is unavailable, so the two agree.
constexpr double kWordsPerSecond = 2.6;
// Average characters per word, including the trailing space.
constexpr double kCharsPerWord = 6.0;
// Roughly four characters to a token, the usual English figure.
constexpr double kCharsPerToken = 4.0;

// System prompt plus the JSON scaffolding the writer is asked to fill in.
constexpr double kScriptOverheadTokens = 800.0;
// A product photo handed to a vision model.
constexpr double kImageTokens = 1100.0;
// Hook, caption and each shot's line and two prompts come back in about this
// much per shot, plus a little fixed overhead.
constexpr double kScriptOutputTokensPerShot = 220.0;

// Every shot is kept at or under this so its clip is bought at the five-second
// floor every video model offers.
constexpr double kSecondsPerShot = 5.0;

int wordCount(const QString &text)
{
    static const QRegularExpression whitespace(QStringLiteral("\\s+"));
    return text.split(whitespace, Qt::SkipEmptyParts).size();
}

} // namespace

Pricing::Pricing(Registry *registry, QObject *parent)
    : QObject(parent)
    , m_registry(registry)
{
    // The user's file wins outright rather than merging: a half-overridden
    // catalogue would be impossible to reason about when a number looks wrong.
    m_overridden = loadFrom(overridePath());
    if (!m_overridden)
        loadFrom(QString::fromLatin1(kBundled));
}

QString Pricing::overridePath() const
{
    return QDir(paths::configDir()).filePath(QString::fromLatin1(kFileName));
}

bool Pricing::loadFrom(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;

    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    const QJsonObject models = root.value(QStringLiteral("models")).toObject();
    if (models.isEmpty())
        return false;

    m_prices.clear();
    for (auto it = models.constBegin(); it != models.constEnd(); ++it) {
        const QJsonObject entry = it.value().toObject();
        if (entry.value(QStringLiteral("unknown")).toBool())
            continue; // recorded on purpose, but still has no price

        Price price;
        price.unit = entry.value(QStringLiteral("unit")).toString();
        price.amount = entry.value(QStringLiteral("amount")).toDouble();
        price.in = entry.value(QStringLiteral("in")).toDouble();
        price.out = entry.value(QStringLiteral("out")).toDouble();
        price.minUnits = entry.value(QStringLiteral("minUnits")).toDouble();
        price.approx = entry.value(QStringLiteral("approx")).toBool();
        price.known = !price.unit.isEmpty();
        if (price.known)
            m_prices.insert(it.key(), price);
    }

    m_updated = root.value(QStringLiteral("updated")).toString();
    return true;
}

Pricing::Price Pricing::priceFor(const QString &modelId) const
{
    return m_prices.value(modelId);
}

double Pricing::speechSeconds(int words)
{
    return qMax(3.0, words / kWordsPerSecond);
}

double Pricing::speechCharacters(int durationSeconds)
{
    return qMax(1.0, durationSeconds * kWordsPerSecond * kCharsPerWord);
}

int Pricing::shotCount(int durationSeconds)
{
    return qBound(2, int(std::ceil(durationSeconds / kSecondsPerShot)), 10);
}

int Pricing::clipSeconds(double shotSeconds)
{
    // Mirrors what the video providers accept: they round anything over seven
    // seconds up to a ten-second clip, everything else to five.
    return shotSeconds > 7.0 ? 10 : 5;
}

QVariantMap Pricing::unitPrice(const QString &modelId) const
{
    const Price price = priceFor(modelId);
    if (!price.known)
        return {};
    return {
        {QStringLiteral("amount"), price.unit == QLatin1String("tokens") ? price.out : price.amount},
        {QStringLiteral("unit"), price.unit},
        {QStringLiteral("approx"), price.approx},
    };
}

QVariantMap Pricing::line(const QString &step, const QString &providerId,
                          const QString &modelId, double units, double unitsOut) const
{
    const Price price = priceFor(modelId);

    QVariantMap row{
        {QStringLiteral("step"), step},
        {QStringLiteral("model"), m_registry ? m_registry->modelLabel(providerId, modelId) : modelId},
        {QStringLiteral("modelId"), modelId},
        {QStringLiteral("known"), price.known},
        {QStringLiteral("approx"), price.approx},
        {QStringLiteral("unit"), price.unit},
    };

    if (!price.known) {
        row.insert(QStringLiteral("units"), 0.0);
        row.insert(QStringLiteral("amount"), 0.0);
        return row;
    }

    double amount = 0.0;
    double shown = units;
    if (price.unit == QLatin1String("tokens")) {
        amount = units / 1e6 * price.in + unitsOut / 1e6 * price.out;
        shown = units + unitsOut;
    } else if (price.unit == QLatin1String("video")) {
        // Some models charge a flat fee per generation rather than by the
        // second, so the seconds asked for do not enter into it -- only how many
        // clips the cut needs, which the caller passes as the second quantity.
        shown = qMax(1.0, unitsOut);
        amount = shown * price.amount;
    } else {
        // Providers with a floor bill it even for a shorter request.
        shown = qMax(units, price.minUnits);
        amount = shown * price.amount;
    }

    row.insert(QStringLiteral("units"), shown);
    row.insert(QStringLiteral("amount"), amount);
    return row;
}

QVariantMap Pricing::estimate(const QVariantMap &request) const
{
    const auto text = [&request](const char *key) {
        return request.value(QLatin1String(key)).toString();
    };

    const QString ownScript = text("script").trimmed();
    const int duration = request.value(QStringLiteral("durationSeconds"), 20).toInt();
    const bool hasPhoto = !text("productImagePath").isEmpty();

    // The voice-over drives both the TTS bill and the clip length, so work it
    // out first. A script the user wrote is measurable; otherwise we go by the
    // length they asked for.
    const double voiceSeconds =
        ownScript.isEmpty() ? double(duration) : speechSeconds(wordCount(ownScript));
    const double voiceChars =
        ownScript.isEmpty() ? speechCharacters(duration) : double(ownScript.size());

    // The ad is cut into shots, and each one buys its own frame and its own
    // clip. This is what multiplies the bill, so it has to be in the estimate.
    const int shots = shotCount(duration);
    const int clip = clipSeconds(voiceSeconds / shots);

    QVariantList lines;

    // ---- Script ---------------------------------------------------------
    if (ownScript.isEmpty()) {
        const QString provider = text("textProvider");
        const QString model = text("textModel");
        const QString brief = text("productName") + text("productDescription") + text("audience")
            + text("tone") + text("language") + text("avatarBrief") + text("extraInstructions");

        double inputTokens = kScriptOverheadTokens + brief.size() / kCharsPerToken;
        if (hasPhoto)
            inputTokens += kImageTokens;

        lines.append(line(QStringLiteral("script"), provider, model, inputTokens,
                          shots * kScriptOutputTokensPerShot));
    }

    // ---- Voice-over -----------------------------------------------------
    {
        const QString provider = text("voiceProvider");
        const QString model = m_registry
            ? m_registry->resolveModel(provider, text("voiceModel"))
            : text("voiceModel");
        lines.append(line(QStringLiteral("voice"), provider, model, voiceChars / 1000.0));
    }

    // ---- Frames ---------------------------------------------------------
    // The user's own photo covers the first shot; the rest are generated.
    const bool ownFrame =
        request.value(QStringLiteral("useProductPhotoAsFrame")).toBool() && hasPhoto;
    const int generatedFrames = ownFrame ? shots - 1 : shots;
    if (generatedFrames > 0) {
        const QString provider = text("imageProvider");
        const QString model = m_registry
            ? m_registry->resolveModel(provider, text("imageModel"))
            : text("imageModel");
        lines.append(line(QStringLiteral("frames"), provider, model, generatedFrames));
    }

    // ---- Video ----------------------------------------------------------
    {
        const QString provider = text("videoProvider");
        const QString model = m_registry
            ? m_registry->resolveModel(provider, text("videoModel"), clip)
            : text("videoModel");
        lines.append(line(QStringLiteral("video"), provider, model, double(shots) * clip, shots));
    }

    // ---- Subtitles ------------------------------------------------------
    if (request.value(QStringLiteral("captionsEnabled"), true).toBool()) {
        lines.append(line(QStringLiteral("captions"), text("captionsProvider"),
                          text("captionsModel"), voiceSeconds / 60.0));
    }

    double total = 0.0;
    int unknown = 0;
    bool approx = false;
    for (const QVariant &entry : std::as_const(lines)) {
        const QVariantMap row = entry.toMap();
        if (!row.value(QStringLiteral("known")).toBool()) {
            ++unknown;
            continue;
        }
        total += row.value(QStringLiteral("amount")).toDouble();
        approx = approx || row.value(QStringLiteral("approx")).toBool();
    }

    return {
        {QStringLiteral("lines"), lines},
        {QStringLiteral("total"), total},
        {QStringLiteral("unknownCount"), unknown},
        {QStringLiteral("approx"), approx},
    };
}

QVariantMap Pricing::actual(const QVariantList &consumed) const
{
    QVariantList lines;
    double total = 0.0;
    int unknown = 0;
    bool approx = false;

    for (const QVariant &entry : consumed) {
        const QVariantMap use = entry.toMap();
        const QVariantMap row = line(use.value(QStringLiteral("step")).toString(),
                                     use.value(QStringLiteral("provider")).toString(),
                                     use.value(QStringLiteral("model")).toString(),
                                     use.value(QStringLiteral("units")).toDouble(),
                                     use.value(QStringLiteral("unitsOut")).toDouble());
        lines.append(row);
        if (!row.value(QStringLiteral("known")).toBool()) {
            ++unknown;
            continue;
        }
        total += row.value(QStringLiteral("amount")).toDouble();
        approx = approx || row.value(QStringLiteral("approx")).toBool();
    }

    return {
        {QStringLiteral("lines"), lines},
        {QStringLiteral("total"), total},
        {QStringLiteral("unknownCount"), unknown},
        {QStringLiteral("approx"), approx},
    };
}
