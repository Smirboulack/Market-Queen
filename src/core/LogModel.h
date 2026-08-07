#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QList>
#include <QtQml/qqmlregistration.h>

class LogModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS

public:
    enum Level { Info, Success, Warning, Error };
    Q_ENUM(Level)

    enum Roles {
        TimeRole = Qt::UserRole + 1,
        LevelRole,
        MessageRole,
    };

    explicit LogModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void append(Level level, const QString &message);

    Q_INVOKABLE void clear();
    Q_INVOKABLE QString asPlainText() const;

private:
    struct Entry {
        QDateTime time;
        Level level;
        QString message;
    };

    QList<Entry> m_entries;
    static constexpr int kMaxEntries = 2000;
};
