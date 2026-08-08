#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// The ad's scenes, as a real list model.
//
// This is a QAbstractListModel and not a QVariantList property for one concrete
// reason: a Repeater rebuilds every delegate when a list property is reassigned,
// so editing a line would destroy the text field being typed into and take the
// cursor with it. Row-level dataChanged leaves the other rows -- and the focus --
// exactly where they were.
class SceneModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(int count READ rowCount NOTIFY changed)

public:
    enum Roles {
        SceneIdRole = Qt::UserRole + 1,
        LineRole,
        KindRole,          // "talking" | "broll"
        ImagePromptRole,
        VideoPromptRole,
        SecondsRole,       // how long this line takes to say
        DirectedRole,      // whether it has visual prompts yet
    };

    explicit SceneModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void add(const QString &line = {});
    Q_INVOKABLE void remove(int row);
    Q_INVOKABLE void move(int from, int to);
    Q_INVOKABLE void setField(int row, const QString &key, const QVariant &value);

    // Applies a director's answer positionally, leaving every line untouched.
    void applyDirection(const QVariantList &shots);

    double seconds(int row) const;
    double totalSeconds() const;
    bool hasSpokenLine() const;
    QString spokenScript() const;

    QVariantList toList() const { return m_scenes; }
    void setList(const QVariantList &scenes);

signals:
    // Anything that changes what the ad is: rows added, removed, reordered, or
    // a line edited. Not emitted for a visual prompt, which changes how a scene
    // looks but not how long it runs or whether the step is satisfied.
    void changed();
    // Any edit at all, including visual prompts: what the draft has to save.
    void dirtied();

private:
    QVariantList m_scenes;
};
