#include "SceneModel.h"

#include <QRegularExpression>
#include <QUuid>

namespace {

// The same figure the pipeline plans against, so what the editor shows and what
// the ad runs to are one number.
constexpr double kWordsPerSecond = 2.6;

int wordCount(const QString &text)
{
    static const QRegularExpression whitespace(QStringLiteral("\\s+"));
    return text.trimmed().isEmpty() ? 0
                                    : text.split(whitespace, Qt::SkipEmptyParts).size();
}

} // namespace

SceneModel::SceneModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int SceneModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_scenes.size();
}

QVariant SceneModel::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_scenes.size())
        return {};

    const QVariantMap scene = m_scenes.at(index.row()).toMap();
    switch (role) {
    case SceneIdRole:     return scene.value(QStringLiteral("id"));
    case LineRole:        return scene.value(QStringLiteral("line"));
    case KindRole:        return scene.value(QStringLiteral("kind"), QStringLiteral("talking"));
    case ImagePromptRole: return scene.value(QStringLiteral("imagePrompt"));
    case VideoPromptRole: return scene.value(QStringLiteral("videoPrompt"));
    case SecondsRole:     return seconds(index.row());
    case DirectedRole:
        return !scene.value(QStringLiteral("imagePrompt")).toString().trimmed().isEmpty();
    default:              return {};
    }
}

QHash<int, QByteArray> SceneModel::roleNames() const
{
    return {{SceneIdRole, "sceneId"},
            {LineRole, "line"},
            {KindRole, "kind"},
            {ImagePromptRole, "imagePrompt"},
            {VideoPromptRole, "videoPrompt"},
            {SecondsRole, "seconds"},
            {DirectedRole, "directed"}};
}

void SceneModel::add(const QString &line)
{
    beginInsertRows({}, m_scenes.size(), m_scenes.size());
    m_scenes.append(QVariantMap{
        {QStringLiteral("id"), QUuid::createUuid().toString(QUuid::WithoutBraces).left(8)},
        {QStringLiteral("line"), line},
        {QStringLiteral("kind"), QStringLiteral("talking")},
        {QStringLiteral("imagePrompt"), QString()},
        {QStringLiteral("videoPrompt"), QString()},
    });
    endInsertRows();

    emit changed();
    emit dirtied();
}

void SceneModel::remove(int row)
{
    if (row < 0 || row >= m_scenes.size())
        return;

    beginRemoveRows({}, row, row);
    m_scenes.removeAt(row);
    endRemoveRows();

    emit changed();
    emit dirtied();
}

void SceneModel::move(int from, int to)
{
    if (from < 0 || from >= m_scenes.size() || to < 0 || to >= m_scenes.size() || from == to)
        return;

    // beginMoveRows counts the destination in the pre-move indexing, where a
    // downward move has to clear the row it is passing.
    if (!beginMoveRows({}, from, from, {}, to > from ? to + 1 : to))
        return;
    m_scenes.move(from, to);
    endMoveRows();

    emit changed();
    emit dirtied();
}

void SceneModel::setField(int row, const QString &key, const QVariant &value)
{
    if (row < 0 || row >= m_scenes.size())
        return;

    QVariantMap scene = m_scenes.at(row).toMap();
    if (scene.value(key) == value)
        return;

    scene.insert(key, value);
    m_scenes[row] = scene;

    const QModelIndex changedIndex = index(row);
    if (key == QLatin1String("line")) {
        emit dataChanged(changedIndex, changedIndex, {LineRole, SecondsRole});
        emit changed();
    } else if (key == QLatin1String("kind")) {
        emit dataChanged(changedIndex, changedIndex, {KindRole});
    } else {
        emit dataChanged(changedIndex, changedIndex,
                         {ImagePromptRole, VideoPromptRole, DirectedRole});
    }

    emit dirtied();
}

void SceneModel::applyDirection(const QVariantList &shots)
{
    // Positional, and only as far as both lists reach: a short answer must not
    // shift everyone's visuals up by one.
    const int count = qMin(shots.size(), m_scenes.size());
    for (int i = 0; i < count; ++i) {
        const QVariantMap shot = shots.at(i).toMap();
        QVariantMap scene = m_scenes.at(i).toMap();
        scene.insert(QStringLiteral("imagePrompt"),
                     shot.value(QStringLiteral("imagePrompt")).toString().trimmed());
        scene.insert(QStringLiteral("videoPrompt"),
                     shot.value(QStringLiteral("videoPrompt")).toString().trimmed());
        m_scenes[i] = scene;
    }

    if (count > 0) {
        emit dataChanged(index(0), index(count - 1),
                         {ImagePromptRole, VideoPromptRole, DirectedRole});
        emit dirtied();
    }
}

double SceneModel::seconds(int row) const
{
    if (row < 0 || row >= m_scenes.size())
        return 0.0;
    return wordCount(m_scenes.at(row).toMap().value(QStringLiteral("line")).toString())
           / kWordsPerSecond;
}

double SceneModel::totalSeconds() const
{
    double total = 0.0;
    for (int row = 0; row < m_scenes.size(); ++row)
        total += seconds(row);
    return total;
}

bool SceneModel::hasSpokenLine() const
{
    for (const QVariant &entry : m_scenes) {
        if (!entry.toMap().value(QStringLiteral("line")).toString().trimmed().isEmpty())
            return true;
    }
    return false;
}

QString SceneModel::spokenScript() const
{
    QStringList lines;
    for (const QVariant &entry : m_scenes) {
        const QString line = entry.toMap().value(QStringLiteral("line")).toString().trimmed();
        if (!line.isEmpty())
            lines.append(line);
    }
    return lines.join(QStringLiteral(" "));
}

void SceneModel::setList(const QVariantList &scenes)
{
    beginResetModel();
    m_scenes = scenes;
    endResetModel();
    emit changed();
}
