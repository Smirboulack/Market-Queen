#include "LogModel.h"

#include <QDebug>

LogModel::LogModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int LogModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_entries.size());
}

QVariant LogModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return {};

    const Entry &e = m_entries.at(index.row());
    switch (role) {
    case TimeRole:
        return e.time.toString(QStringLiteral("HH:mm:ss"));
    case LevelRole:
        return int(e.level);
    case MessageRole:
        return e.message;
    default:
        return {};
    }
}

QHash<int, QByteArray> LogModel::roleNames() const
{
    return {
        {TimeRole, "time"},
        {LevelRole, "level"},
        {MessageRole, "message"},
    };
}

void LogModel::append(Level level, const QString &message)
{
    if (message.isEmpty())
        return;

    if (m_entries.size() >= kMaxEntries) {
        beginRemoveRows({}, 0, 0);
        m_entries.removeFirst();
        endRemoveRows();
    }

    beginInsertRows({}, int(m_entries.size()), int(m_entries.size()));
    m_entries.append({QDateTime::currentDateTime(), level, message});
    endInsertRows();

    qInfo().noquote() << QStringLiteral("[%1] %2").arg(int(level)).arg(message);
}

void LogModel::clear()
{
    beginResetModel();
    m_entries.clear();
    endResetModel();
}

QString LogModel::asPlainText() const
{
    QStringList lines;
    lines.reserve(int(m_entries.size()));
    for (const Entry &e : m_entries)
        lines << QStringLiteral("%1  %2").arg(e.time.toString(Qt::ISODate), e.message);
    return lines.join(QLatin1Char('\n'));
}
