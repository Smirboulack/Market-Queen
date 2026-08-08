#pragma once

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

class SettingsStore;

// Every run leaves a folder behind with a project.json manifest; the library is
// just a listing of those folders, newest first.
class LibraryModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    // What every listed project cost, added up. Projects written before costs
    // were recorded contribute nothing.
    Q_PROPERTY(double totalCost READ totalCost NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        ProductRole,
        HookRole,
        CreatedRole,
        DirRole,
        FinalVideoRole,
        ThumbnailRole,
        SuccessRole,
        CostRole,
        HasCostRole,
    };

    explicit LibraryModel(SettingsStore *settings, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    double totalCost() const;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh();

signals:
    void countChanged();

private:
    struct Project {
        QString folderName;
        QString productName;
        QString hook;
        QString createdAt;
        QString dir;
        QString finalVideo;
        QString thumbnail;
        bool success = false;
        double cost = 0.0;
        bool hasCost = false;
    };

    SettingsStore *m_settings;
    QList<Project> m_projects;
};
