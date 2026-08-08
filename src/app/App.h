#pragma once

#include "AdProject.h"
#include "LibraryModel.h"
#include "core/LogModel.h"
#include "core/Pricing.h"
#include "core/SettingsStore.h"
#include "i18n/Translator.h"
#include "pipeline/Pipeline.h"
#include "providers/Registry.h"

#include <QObject>
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QQmlEngine;

// The single object QML talks to. It owns the engine pieces and exposes the
// few OS-level helpers the UI needs.
class App : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(SettingsStore *settings READ settings CONSTANT)
    Q_PROPERTY(Registry *registry READ registry CONSTANT)
    Q_PROPERTY(Pricing *pricing READ pricing CONSTANT)
    Q_PROPERTY(Pipeline *pipeline READ pipeline CONSTANT)
    Q_PROPERTY(AdProject *project READ project CONSTANT)
    Q_PROPERTY(LogModel *log READ log CONSTANT)
    Q_PROPERTY(LibraryModel *library READ library CONSTANT)
    Q_PROPERTY(Translator *translator READ translator CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString ffmpegPath READ ffmpegPath NOTIFY ffmpegPathChanged)

public:
    explicit App(QObject *parent = nullptr);

    static App *create(QQmlEngine *engine, QJSEngine *jsEngine);

    SettingsStore *settings() const { return m_settings; }
    Registry *registry() const { return m_registry; }
    Pricing *pricing() const { return m_pricing; }
    Pipeline *pipeline() const { return m_pipeline; }
    AdProject *project() const { return m_project; }
    LogModel *log() const { return m_log; }
    LibraryModel *library() const { return m_library; }
    Translator *translator() const { return m_translator; }
    QString version() const;

    // Resolved ffmpeg binary, empty when it could not be found.
    QString ffmpegPath() const;

    Q_INVOKABLE void openExternal(const QString &url);
    Q_INVOKABLE void openPath(const QString &path);
    Q_INVOKABLE void revealPath(const QString &path);
    Q_INVOKABLE QString toLocalFile(const QString &url) const;
    Q_INVOKABLE QString toFileUrl(const QString &path) const;
    Q_INVOKABLE void copyToClipboard(const QString &text);

    // Asks the provider for the voices on the user's account.
    Q_INVOKABLE void loadVoices(const QString &providerId);

signals:
    void ffmpegPathChanged();
    void voicesLoaded(const QString &providerId, const QVariantList &voices);
    void voicesFailed(const QString &providerId, const QString &error);

private:
    SettingsStore *m_settings;
    Registry *m_registry;
    Pricing *m_pricing;
    LogModel *m_log;
    Pipeline *m_pipeline;
    AdProject *m_project;
    LibraryModel *m_library;
    Translator *m_translator;
};
