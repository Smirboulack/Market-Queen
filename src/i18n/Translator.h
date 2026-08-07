#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QQmlApplicationEngine;
class QTranslator;

// Loads the compiled .qm catalogues and switches the whole UI at runtime:
// QQmlApplicationEngine::retranslate() re-evaluates every qsTr() binding, so no
// restart is needed. Arabic also flips the layout direction.
class Translator : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(QString currentLanguage READ currentLanguage NOTIFY languageChanged)
    // Endonym of the active language ("Français"), used as the default target
    // language for the generated script.
    Q_PROPERTY(QString currentLabel READ currentLabel NOTIFY languageChanged)
    Q_PROPERTY(bool rightToLeft READ rightToLeft NOTIFY languageChanged)

public:
    explicit Translator(QObject *parent = nullptr);

    // [{ code, label, englishLabel, rightToLeft }]. "" is "follow the system".
    Q_INVOKABLE QVariantList languages() const;

    QString currentLanguage() const { return m_current; }
    QString currentLabel() const;
    bool rightToLeft() const;

    void attach(QQmlApplicationEngine *engine);

    // An empty code picks the closest match for the system locale.
    Q_INVOKABLE void applyLanguage(const QString &code);

signals:
    void languageChanged();

private:
    static QString resolveSystemLanguage();

    QPointer<QQmlApplicationEngine> m_engine;
    QTranslator *m_appTranslator = nullptr;
    QTranslator *m_qtTranslator = nullptr;
    QString m_current;
};
