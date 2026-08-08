#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Registry;

// What each model costs, and what a run is about to cost.
//
// The numbers live in resources/pricing.json rather than in this file: provider
// prices move often, and a data file can be corrected by a pull request instead
// of a release. A pricing.json dropped in the config directory overrides the
// bundled one, so nobody has to wait for us to notice a change.
//
// A model the catalogue does not know is never guessed at: it is reported as
// unknown and left out of the total. Everything here is an estimate and is
// labelled as one -- it is not a billing source.
class Pricing : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(QString updated READ updated CONSTANT)
    Q_PROPERTY(bool overridden READ overridden CONSTANT)
    Q_PROPERTY(QString overridePath READ overridePath CONSTANT)

public:
    explicit Pricing(Registry *registry, QObject *parent = nullptr);

    // Date the prices were last checked, "yyyy-MM-dd".
    QString updated() const { return m_updated; }
    // True when a user file replaced the bundled catalogue.
    bool overridden() const { return m_overridden; }
    // Where such a file would go, whether or not it exists.
    QString overridePath() const;

    // Enough to draw "$0.28/s" next to a model name: {amount, unit, approx}.
    // Empty when the price is unknown.
    Q_INVOKABLE QVariantMap unitPrice(const QString &modelId) const;

    // What the form is about to spend, taking the same map CreatePage builds
    // for the pipeline. Returns:
    //   { lines: [{step, model, units, unit, amount, known, approx}],
    //     total, unknownCount, approx }
    // `total` covers the known lines only; `unknownCount` says how many were
    // left out, so the UI can say so instead of quietly under-reporting.
    Q_INVOKABLE QVariantMap estimate(const QVariantMap &request) const;

    // Same shape, from what a finished run actually consumed:
    // [{step, model, units, unitsOut}].
    QVariantMap actual(const QVariantList &consumed) const;

    // Seconds of speech a script of `words` words takes. The pipeline sizes its
    // clips from the same figure, so the estimate matches what it will buy.
    static double speechSeconds(int words);
    // Characters of speech in an ad of this length -- the TTS billing unit.
    static double speechCharacters(int durationSeconds);

    // How many shots an ad of this length is cut into.
    //
    // Video models sell clips in fixed sizes, five seconds being the smallest
    // everyone offers. Keeping every shot at or under five seconds means each
    // one is bought at that floor with nothing wasted, and no shot ever has to
    // be stretched or looped to fill its slot. The user picks the ad's length;
    // this decides what that costs in cuts, so there is no second control to
    // get wrong.
    static int shotCount(int durationSeconds);
    // Seconds of video bought for one shot of `shotSeconds` on screen.
    static int clipSeconds(double shotSeconds);

private:
    struct Price {
        QString unit;       // tokens | image | second | kchars | minute
        double amount = 0;  // per unit; unused for tokens
        double in = 0;      // dollars per 1M input tokens
        double out = 0;     // dollars per 1M output tokens
        double minUnits = 0;
        bool approx = false;
        bool known = false;
    };

    bool loadFrom(const QString &path);
    Price priceFor(const QString &modelId) const;

    // One row of the estimate. For token pricing `units` is the input count and
    // `unitsOut` the output count; everything else uses `units` alone.
    QVariantMap line(const QString &step, const QString &providerId,
                     const QString &modelId, double units, double unitsOut = 0) const;

    Registry *m_registry;
    QHash<QString, Price> m_prices;
    QString m_updated;
    bool m_overridden = false;
};
