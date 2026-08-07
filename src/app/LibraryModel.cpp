#include "LibraryModel.h"

#include "core/SettingsStore.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>

LibraryModel::LibraryModel(SettingsStore *settings, QObject *parent)
    : QAbstractListModel(parent)
    , m_settings(settings)
{
    connect(settings, &SettingsStore::projectsDirChanged, this, &LibraryModel::refresh);
    refresh();
}

int LibraryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_projects.size());
}

QVariant LibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_projects.size())
        return {};

    const Project &p = m_projects.at(index.row());
    switch (role) {
    case NameRole:
        return p.folderName;
    case ProductRole:
        return p.productName;
    case HookRole:
        return p.hook;
    case CreatedRole:
        return p.createdAt;
    case DirRole:
        return p.dir;
    case FinalVideoRole:
        return p.finalVideo;
    case ThumbnailRole:
        return p.thumbnail.isEmpty() ? QString() : QUrl::fromLocalFile(p.thumbnail).toString();
    case SuccessRole:
        return p.success;
    default:
        return {};
    }
}

QHash<int, QByteArray> LibraryModel::roleNames() const
{
    return {
        {NameRole, "name"},         {ProductRole, "productName"},
        {HookRole, "hook"},         {CreatedRole, "createdAt"},
        {DirRole, "dir"},           {FinalVideoRole, "finalVideo"},
        {ThumbnailRole, "thumbnail"}, {SuccessRole, "success"},
    };
}

void LibraryModel::refresh()
{
    beginResetModel();
    m_projects.clear();

    QDir root(m_settings->projectsDir());
    if (root.exists()) {
        const QFileInfoList folders =
            root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed);

        for (const QFileInfo &folder : folders) {
            QFile manifestFile(QDir(folder.absoluteFilePath()).filePath(QStringLiteral("project.json")));
            if (!manifestFile.open(QIODevice::ReadOnly))
                continue;

            const QJsonObject manifest = QJsonDocument::fromJson(manifestFile.readAll()).object();

            Project project;
            project.folderName = folder.fileName();
            project.dir = folder.absoluteFilePath();
            project.productName = manifest.value(QStringLiteral("productName")).toString();
            project.hook = manifest.value(QStringLiteral("hook")).toString();
            project.success = manifest.value(QStringLiteral("success")).toBool();

            const QDateTime created =
                QDateTime::fromString(manifest.value(QStringLiteral("createdAt")).toString(),
                                      Qt::ISODate);
            project.createdAt = created.isValid()
                ? created.toString(QStringLiteral("d MMM yyyy, HH:mm"))
                : folder.birthTime().toString(QStringLiteral("d MMM yyyy, HH:mm"));

            const auto resolve = [&folder](const QString &relative) {
                return relative.isEmpty()
                    ? QString()
                    : QDir(folder.absoluteFilePath()).filePath(relative);
            };
            project.finalVideo = resolve(manifest.value(QStringLiteral("final")).toString());
            project.thumbnail = resolve(manifest.value(QStringLiteral("frame")).toString());

            if (!project.finalVideo.isEmpty() && !QFileInfo::exists(project.finalVideo))
                project.finalVideo.clear();
            if (!project.thumbnail.isEmpty() && !QFileInfo::exists(project.thumbnail))
                project.thumbnail.clear();

            m_projects.append(project);
        }
    }

    endResetModel();
    emit countChanged();
}
