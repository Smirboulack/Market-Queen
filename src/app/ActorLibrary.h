#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// The actors the user has kept.
//
// An actor is the expensive part of a good ad: it takes several batches to land
// a face that reads as real, and once it does it should never have to be found
// again. Saving one copies its portrait out of the casting scratch folder into
// the config directory, so clearing scratch can never orphan a saved actor.
class ActorLibrary : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        PortraitRole,
        BriefRole,
        DecorRole,
        ActorRole,   // the whole map, for loading one back into the project
    };

    explicit ActorLibrary(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Inserts or updates, and returns the actor's id. An actor carrying an id
    // that is already on file is updated in place rather than duplicated.
    Q_INVOKABLE QString save(const QVariantMap &actor);
    Q_INVOKABLE QVariantMap actor(const QString &id) const;
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE void refresh();

    // Suggests a name for an actor that has none, so saving never blocks on a
    // dialog: "Actor 3".
    Q_INVOKABLE QString suggestedName() const;

signals:
    void countChanged();

private:
    QString storeFile() const;
    QString portraitDir() const;
    void load();
    void persist();
    // Copies a portrait out of scratch into the library folder, returning the
    // new path. Files already inside the library are left where they are.
    QString adoptPortrait(const QString &id, const QString &path) const;

    QList<QVariantMap> m_actors;
};
