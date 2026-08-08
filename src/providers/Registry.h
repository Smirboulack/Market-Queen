#pragma once

#include "Types.h"

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class ProviderTask;

// Catalogue of everything the app can talk to, plus the factory that turns a
// provider id into a running task. Adding a provider means adding one entry
// here and one class in the matching *Providers.cpp -- nothing in the UI or the
// pipeline changes.
class Registry : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    // The descriptions are translated, so the list has to be rebuilt when the
    // language changes; binding to this property is enough for QML to follow.
    Q_PROPERTY(QVariantList credentialList READ credentials NOTIFY retranslated)

public:
    explicit Registry(QObject *parent = nullptr);

    // Categories: "text", "image", "video", "voice", "captions".
    Q_INVOKABLE QVariantList providers(const QString &category) const;
    Q_INVOKABLE QVariantMap provider(const QString &id) const;
    Q_INVOKABLE QString credentialFor(const QString &providerId) const;
    Q_INVOKABLE QString defaultProvider(const QString &category) const;

    // Readable name for a model, or the id itself when it came from "Other...".
    Q_INVOKABLE QString modelLabel(const QString &providerId, const QString &modelId) const;

    // [{id, label, envVar, signupUrl, note}] for the settings page.
    QVariantList credentials() const;

    void retranslate();

    // A model the user can pick: technical id + something readable.
    struct Model {
        QString id;
        QString label;
    };

    struct Entry {
        QString id;
        QString category;
        QString label;
        QString credential;
        QList<Model> models;
        QString defaultModel;
        QString note;
    };

    const QList<Entry> &entries() const { return m_entries; }

    // "auto" is a placeholder, not a model id. This turns it into a real one,
    // picked from what the shot needs. Returns the id unchanged otherwise.
    Q_INVOKABLE QString resolveModel(const QString &providerId, const QString &modelId,
                                     int durationSeconds = 0) const;

    static bool isAuto(const QString &modelId) { return modelId == QLatin1String("auto"); }

signals:
    void retranslated();

private:
    void buildEntries();

    QList<Entry> m_entries;
};

// Task factory. Returns nullptr when the provider id is unknown.
namespace providers {

ProviderTask *script(const QString &providerId, const prov::ScriptRequest &request,
                     QObject *parent = nullptr);
ProviderTask *image(const QString &providerId, const prov::ImageRequest &request,
                    QObject *parent = nullptr);
ProviderTask *video(const QString &providerId, const prov::VideoRequest &request,
                    QObject *parent = nullptr);
ProviderTask *avatar(const QString &providerId, const prov::AvatarRequest &request,
                     QObject *parent = nullptr);
ProviderTask *voice(const QString &providerId, const prov::VoiceRequest &request,
                    QObject *parent = nullptr);
ProviderTask *transcribe(const QString &providerId, const prov::TranscribeRequest &request,
                         QObject *parent = nullptr);

// Lists the voices available on the user's account (ElevenLabs / OpenAI).
ProviderTask *voiceCatalog(const QString &providerId, const QString &apiKey,
                           QObject *parent = nullptr);

} // namespace providers
