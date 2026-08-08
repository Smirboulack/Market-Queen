#include "ActorLibrary.h"

#include "core/Paths.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>

namespace {

constexpr const char *kFileName = "actors.json";
constexpr const char *kPortraitFolder = "actors";

} // namespace

ActorLibrary::ActorLibrary(QObject *parent)
    : QAbstractListModel(parent)
{
    load();
}

QString ActorLibrary::storeFile() const
{
    return QDir(paths::configDir()).filePath(QString::fromLatin1(kFileName));
}

QString ActorLibrary::portraitDir() const
{
    return QDir(paths::configDir()).filePath(QString::fromLatin1(kPortraitFolder));
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
int ActorLibrary::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_actors.size();
}

QVariant ActorLibrary::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_actors.size())
        return {};

    const QVariantMap &actor = m_actors.at(index.row());
    switch (role) {
    case IdRole:       return actor.value(QStringLiteral("id"));
    case NameRole:     return actor.value(QStringLiteral("name"));
    case PortraitRole: return actor.value(QStringLiteral("portraitPath"));
    case BriefRole:    return actor.value(QStringLiteral("brief"));
    case DecorRole:    return actor.value(QStringLiteral("decor"));
    case ActorRole:    return actor;
    default:           return {};
    }
}

QHash<int, QByteArray> ActorLibrary::roleNames() const
{
    return {{IdRole, "actorId"},
            {NameRole, "name"},
            {PortraitRole, "portraitPath"},
            {BriefRole, "brief"},
            {DecorRole, "decor"},
            {ActorRole, "actor"}};
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------
void ActorLibrary::load()
{
    QFile file(storeFile());
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonArray array = QJsonDocument::fromJson(file.readAll()).array();

    beginResetModel();
    m_actors.clear();
    for (const QJsonValue &entry : array) {
        const QVariantMap actor = entry.toObject().toVariantMap();
        if (!actor.value(QStringLiteral("id")).toString().isEmpty())
            m_actors.append(actor);
    }
    endResetModel();

    emit countChanged();
}

void ActorLibrary::persist()
{
    if (paths::ensureDir(paths::configDir()).isEmpty())
        return;

    QJsonArray array;
    for (const QVariantMap &actor : m_actors)
        array.append(QJsonObject::fromVariantMap(actor));

    QFile file(storeFile());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
}

void ActorLibrary::refresh()
{
    load();
}

QString ActorLibrary::adoptPortrait(const QString &id, const QString &path) const
{
    if (path.isEmpty() || !QFileInfo::exists(path))
        return path;

    const QString dir = paths::ensureDir(portraitDir());
    if (dir.isEmpty())
        return path;

    // Already ours: a re-save of an unchanged actor must not copy the file onto
    // itself and must not accumulate duplicates.
    if (QFileInfo(path).absolutePath() == QFileInfo(dir).absoluteFilePath())
        return path;

    const QString extension = QFileInfo(path).suffix().isEmpty()
                                  ? QStringLiteral("png")
                                  : QFileInfo(path).suffix();
    const QString target = QDir(dir).filePath(QStringLiteral("%1.%2").arg(id, extension));

    QFile::remove(target);
    if (!QFile::copy(path, target))
        return path;

    return target;
}

// ---------------------------------------------------------------------------
// Entries
// ---------------------------------------------------------------------------
QString ActorLibrary::save(const QVariantMap &actor)
{
    QVariantMap entry = actor;

    QString id = entry.value(QStringLiteral("id")).toString();
    if (id.isEmpty())
        id = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    entry.insert(QStringLiteral("id"), id);

    if (entry.value(QStringLiteral("name")).toString().trimmed().isEmpty())
        entry.insert(QStringLiteral("name"), suggestedName());

    entry.insert(QStringLiteral("portraitPath"),
                 adoptPortrait(id, entry.value(QStringLiteral("portraitPath")).toString()));

    int existing = -1;
    for (int i = 0; i < m_actors.size(); ++i) {
        if (m_actors.at(i).value(QStringLiteral("id")).toString() == id) {
            existing = i;
            break;
        }
    }

    if (existing >= 0) {
        m_actors[existing] = entry;
        const QModelIndex changed = index(existing);
        emit dataChanged(changed, changed);
    } else {
        // Newest first: the actor just cast is the one about to be used.
        beginInsertRows({}, 0, 0);
        m_actors.prepend(entry);
        endInsertRows();
        emit countChanged();
    }

    persist();
    return id;
}

QVariantMap ActorLibrary::actor(const QString &id) const
{
    for (const QVariantMap &entry : m_actors) {
        if (entry.value(QStringLiteral("id")).toString() == id)
            return entry;
    }
    return {};
}

void ActorLibrary::remove(const QString &id)
{
    for (int i = 0; i < m_actors.size(); ++i) {
        if (m_actors.at(i).value(QStringLiteral("id")).toString() != id)
            continue;

        const QString portrait = m_actors.at(i).value(QStringLiteral("portraitPath")).toString();

        beginRemoveRows({}, i, i);
        m_actors.removeAt(i);
        endRemoveRows();

        // Only files we adopted are ours to delete; a portrait the user pointed
        // at from their own folders stays where it is.
        if (!portrait.isEmpty()
            && QFileInfo(portrait).absolutePath() == QFileInfo(portraitDir()).absoluteFilePath()) {
            QFile::remove(portrait);
        }

        persist();
        emit countChanged();
        return;
    }
}

QString ActorLibrary::suggestedName() const
{
    return tr("Actor %1").arg(m_actors.size() + 1);
}
