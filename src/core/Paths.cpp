#include "Paths.h"

#include <QDir>
#include <QStandardPaths>

namespace paths {

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString defaultProjectsDir()
{
    const QString movies = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    const QString base = movies.isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
        : movies;
    return QDir(base).filePath(QStringLiteral("Market Queen"));
}

QString ensureDir(const QString &path)
{
    if (path.isEmpty())
        return {};
    QDir dir(path);
    if (!dir.exists() && !dir.mkpath(QStringLiteral(".")))
        return {};
    return dir.absolutePath();
}

QString slugify(const QString &text, int maxLength)
{
    QString out;
    out.reserve(text.size());
    bool lastDash = false;
    for (const QChar c : text) {
        if (c.isLetterOrNumber()) {
            out += c.toLower();
            lastDash = false;
        } else if (!lastDash && !out.isEmpty()) {
            out += QLatin1Char('-');
            lastDash = true;
        }
    }
    while (out.endsWith(QLatin1Char('-')))
        out.chop(1);
    if (out.size() > maxLength) {
        out.truncate(maxLength);
        while (out.endsWith(QLatin1Char('-')))
            out.chop(1);
    }
    return out.isEmpty() ? QStringLiteral("untitled") : out;
}

} // namespace paths
