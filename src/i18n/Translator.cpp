#include "Translator.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QLibraryInfo>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QTranslator>

namespace {

struct Language {
    const char *code;
    const char *label;        // written in the language itself
    const char *englishLabel;
    bool rightToLeft;
};

// Keep in sync with the TS_FILES list in CMakeLists.txt.
constexpr Language kLanguages[] = {
    {"en", "English", "English", false},
    {"fr", "Français", "French", false},
    {"es", "Español", "Spanish", false},
    {"de", "Deutsch", "German", false},
    {"it", "Italiano", "Italian", false},
    {"pt", "Português", "Portuguese", false},
    {"nl", "Nederlands", "Dutch", false},
    {"pl", "Polski", "Polish", false},
    {"ru", "Русский", "Russian", false},
    {"zh", "中文", "Chinese (Simplified)", false},
    {"ar", "العربية", "Arabic", true},
};

const Language *findLanguage(const QString &code)
{
    for (const Language &language : kLanguages) {
        if (code == QLatin1String(language.code))
            return &language;
    }
    return nullptr;
}

} // namespace

Translator::Translator(QObject *parent)
    : QObject(parent)
    , m_appTranslator(new QTranslator(this))
    , m_qtTranslator(new QTranslator(this))
{
}

QVariantList Translator::languages() const
{
    QVariantList list;
    for (const Language &language : kLanguages) {
        list.append(QVariantMap{
            {QStringLiteral("code"), QString::fromLatin1(language.code)},
            {QStringLiteral("label"), QString::fromUtf8(language.label)},
            {QStringLiteral("englishLabel"), QString::fromUtf8(language.englishLabel)},
            {QStringLiteral("rightToLeft"), language.rightToLeft},
        });
    }
    return list;
}

QString Translator::currentLabel() const
{
    const Language *language = findLanguage(m_current);
    return language ? QString::fromUtf8(language->label) : QStringLiteral("English");
}

bool Translator::rightToLeft() const
{
    const Language *language = findLanguage(m_current);
    return language && language->rightToLeft;
}

void Translator::attach(QQmlApplicationEngine *engine)
{
    m_engine = engine;
}

QString Translator::resolveSystemLanguage()
{
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &tag : uiLanguages) {
        // "fr-CA" and "fr" both map to our "fr" catalogue.
        const QString base = tag.section(QLatin1Char('-'), 0, 0).toLower();
        if (findLanguage(base))
            return base;
    }
    return QStringLiteral("en");
}

void Translator::applyLanguage(const QString &code)
{
    const QString target = code.isEmpty() ? resolveSystemLanguage() : code;
    if (!findLanguage(target))
        return;

    QCoreApplication::removeTranslator(m_appTranslator);
    QCoreApplication::removeTranslator(m_qtTranslator);

    // English is the source language: there is no catalogue to load.
    if (target != QLatin1String("en")) {
        if (m_appTranslator->load(QStringLiteral(":/i18n/superinfinity_%1.qm").arg(target)))
            QCoreApplication::installTranslator(m_appTranslator);

        // Qt's own strings (dialog buttons, text field context menu).
        if (m_qtTranslator->load(QLocale(target), QStringLiteral("qtbase"), QStringLiteral("_"),
                                 QLibraryInfo::path(QLibraryInfo::TranslationsPath))) {
            QCoreApplication::installTranslator(m_qtTranslator);
        }
    }

    m_current = target;

    const Language *language = findLanguage(target);
    QGuiApplication::setLayoutDirection(language && language->rightToLeft ? Qt::RightToLeft
                                                                         : Qt::LeftToRight);

    if (m_engine)
        m_engine->retranslate();

    emit languageChanged();
}
