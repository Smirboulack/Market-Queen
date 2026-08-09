#pragma once

#include "SceneModel.h"

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QTimer;
class Registry;
class SettingsStore;

// The ad being built.
//
// Every studio step reads and writes this one object, so the recap panel, the
// cost estimate and the Generate button always describe the same thing rather
// than three snapshots of a form. It autosaves to the config directory, so
// closing the app halfway through a build loses nothing.
//
// There is deliberately no duration field: an ad lasts exactly as long as its
// words take to say. `spokenSeconds` derives it from the script.
class AdProject : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(QVariantMap product READ product NOTIFY productChanged)
    Q_PROPERTY(QVariantMap actor READ actor NOTIFY actorChanged)
    Q_PROPERTY(SceneModel *scenes READ scenes CONSTANT)
    Q_PROPERTY(QString script READ script WRITE setScript NOTIFY scriptChanged)

    Q_PROPERTY(QString aspectRatio READ aspectRatio WRITE setAspectRatio NOTIFY renderChanged)
    Q_PROPERTY(bool captions READ captions WRITE setCaptions NOTIFY renderChanged)

    // Navigation: linear on the first pass, free once a step has been cleared.
    // `furthestStep` is the last reachable index, so the rail and the recap
    // agree on what is clickable without either of them owning the rule.
    Q_PROPERTY(int currentStep READ currentStep WRITE setCurrentStep NOTIFY currentStepChanged)
    Q_PROPERTY(int furthestStep READ furthestStep NOTIFY stepsChanged)
    Q_PROPERTY(QVariantList stepStates READ stepStates NOTIFY stepsChanged)
    Q_PROPERTY(bool complete READ complete NOTIFY stepsChanged)

    Q_PROPERTY(double spokenSeconds READ spokenSeconds NOTIFY stepsChanged)

    // The pipeline request, as a bindable property: the estimate card has to
    // re-price itself on every edit, and a Q_INVOKABLE call would not re-run.
    Q_PROPERTY(QVariantMap request READ toRequest NOTIFY requestChanged)

public:
    // Casting and writing are one step: you cannot write for someone who
    // does not exist yet, and you rewrite the moment you recast.
    enum Step { StepProduct = 0, StepScenario, StepSummary, StepCount };
    Q_ENUM(Step)

    AdProject(SettingsStore *settings, Registry *registry, QObject *parent = nullptr);

    QVariantMap product() const { return m_product; }
    QVariantMap actor() const { return m_actor; }
    SceneModel *scenes() const { return m_scenes; }

    QString script() const { return m_script; }
    void setScript(const QString &script);

    QString aspectRatio() const { return m_aspectRatio; }
    void setAspectRatio(const QString &aspect);

    bool captions() const { return m_captions; }
    void setCaptions(bool on);

    int currentStep() const { return m_currentStep; }
    void setCurrentStep(int step);

    int furthestStep() const;
    QVariantList stepStates() const;
    bool complete() const;

    double spokenSeconds() const;

    // Field-level writers. QML edits one key at a time so a text field cannot
    // clobber the rest of the map on every keystroke.
    Q_INVOKABLE void setProductField(const QString &key, const QVariant &value);
    Q_INVOKABLE void setActorField(const QString &key, const QVariant &value);

    // Reference images. `target` is "product" or "actor" -- the two lists behave
    // identically, so they share one implementation and one QML component.
    // Several are allowed: the user is billed by their own provider, so there is
    // no reason for us to cap it. Index 0 is the primary, the one the models get
    // when only a single reference can be passed.
    Q_INVOKABLE void addImages(const QString &target, const QList<QUrl> &urls);
    Q_INVOKABLE void removeImage(const QString &target, int index);
    Q_INVOKABLE void setPrimaryImage(const QString &target, int index);

    // Loads a saved actor over the current one, portrait and voice included.
    Q_INVOKABLE void applyActor(const QVariantMap &actor);

    // Applies a director's answer to the scenes, leaving every line alone.
    Q_INVOKABLE void applyDirection(const QVariantList &shots);
    // Every line, joined: what the voice-over says in one take.
    Q_INVOKABLE QString spokenScript() const;

    Q_INVOKABLE void clear();

    // The request shape the current pipeline understands. This is the seam that
    // keeps the studio shippable before the pipeline is rewritten: S5 replaces
    // the body, not the callers.
    Q_INVOKABLE QVariantMap toRequest() const;

signals:
    void productChanged();
    void actorChanged();
    void scenesChanged();
    void scriptChanged();
    void renderChanged();
    void currentStepChanged();
    void stepsChanged();
    void requestChanged();
    // Text fields lose their binding the moment the user types in them, so any
    // change made behind their back has to be announced rather than inferred.
    // Both signals mean the same thing to QML -- re-read your value from the
    // model -- and are separate only so a panel can ignore the one that cannot
    // concern it.
    void cleared();
    void actorReset();

private:
    bool stepValid(int step) const;
    // Resolves a "product"/"actor" target to the map and key holding its list.
    QVariantMap *imageOwner(const QString &target, QString *key);
    void touch();
    void load();
    void save();
    QString draftFile() const;

    SettingsStore *m_settings;
    Registry *m_registry;
    QTimer *m_autosave;

    QVariantMap m_product;   // name, description, audience, images (QStringList)
    QVariantMap m_actor;     // name, brief, decor, traits, portraitPath, voice
    SceneModel *m_scenes;
    // Kept only so a draft written before scenes existed still opens with its
    // words intact; the first edit turns it into scenes.
    QString m_script;
    QString m_aspectRatio = QStringLiteral("9:16");
    bool m_captions = true;
    int m_currentStep = 0;
    bool m_loading = false;
};
