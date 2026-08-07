#include "App.h"

#include "LibraryModel.h"
#include "core/LogModel.h"
#include "core/SettingsStore.h"
#include "media/Ffmpeg.h"
#include "pipeline/Pipeline.h"
#include "providers/ProviderTask.h"
#include "providers/Registry.h"

#include <QClipboard>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlEngine>
#include <QUrl>

App::App(QObject *parent)
    : QObject(parent)
    , m_settings(new SettingsStore(this))
    , m_registry(new Registry(this))
    , m_log(new LogModel(this))
    , m_pipeline(new Pipeline(m_settings, m_registry, m_log, this))
    , m_library(new LibraryModel(m_settings, this))
    , m_translator(new Translator(this))
{
    connect(m_settings, &SettingsStore::ffmpegPathChanged, this, &App::ffmpegPathChanged);

    // Settings owns the choice; the translator carries it out.
    connect(m_settings, &SettingsStore::uiLanguageChanged, this,
            [this]() { m_translator->applyLanguage(m_settings->uiLanguage()); });

    // QQmlApplicationEngine::retranslate() only re-evaluates qsTr() bindings;
    // strings that C++ built once have to be rebuilt by hand.
    connect(m_translator, &Translator::languageChanged, this, [this]() {
        m_registry->retranslate();
        m_pipeline->retranslate();
    });

    // A finished run should show up in the library right away.
    connect(m_pipeline, &Pipeline::finished, this, [this](bool, const QString &) {
        m_library->refresh();
    });

    // Deferred: the translator is installed right after this constructor
    // returns, and these two lines should already be in the user's language.
    QMetaObject::invokeMethod(
        this,
        [this]() {
            m_log->append(LogModel::Info,
                          tr("Super Infinity %1. Add your API keys in Settings to get started.")
                              .arg(version()));
            if (ffmpegPath().isEmpty()) {
                m_log->append(LogModel::Warning,
                              tr("FFmpeg was not found. It is needed for the final render; "
                                 "set its path in Settings."));
            }
        },
        Qt::QueuedConnection);
}

App *App::create(QQmlEngine *engine, QJSEngine *)
{
    // The engine owns the singleton.
    return new App(engine);
}

QString App::version() const
{
    return QStringLiteral(APP_VERSION);
}

QString App::ffmpegPath() const
{
    return ffmpeg::resolve(m_settings->ffmpegPath());
}

void App::openExternal(const QString &url)
{
    QDesktopServices::openUrl(QUrl(url));
}

void App::openPath(const QString &path)
{
    const QString local = toLocalFile(path);
    if (local.isEmpty() || !QFileInfo::exists(local))
        return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(local));
}

void App::revealPath(const QString &path)
{
    const QString local = toLocalFile(path);
    if (local.isEmpty())
        return;

    const QFileInfo info(local);
    if (!info.exists()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(info.absolutePath()));
        return;
    }

#if defined(Q_OS_WIN)
    QProcess::startDetached(QStringLiteral("explorer.exe"),
                            {QStringLiteral("/select,") + QDir::toNativeSeparators(info.absoluteFilePath())});
#elif defined(Q_OS_MACOS)
    QProcess::startDetached(QStringLiteral("open"),
                            {QStringLiteral("-R"), info.absoluteFilePath()});
#else
    QDesktopServices::openUrl(
        QUrl::fromLocalFile(info.isDir() ? info.absoluteFilePath() : info.absolutePath()));
#endif
}

QString App::toLocalFile(const QString &url) const
{
    if (url.startsWith(QLatin1String("file:")))
        return QUrl(url).toLocalFile();
    return url;
}

QString App::toFileUrl(const QString &path) const
{
    if (path.isEmpty() || path.startsWith(QLatin1String("file:")))
        return path;
    return QUrl::fromLocalFile(path).toString();
}

void App::copyToClipboard(const QString &text)
{
    if (QClipboard *clipboard = QGuiApplication::clipboard())
        clipboard->setText(text);
}

void App::loadVoices(const QString &providerId)
{
    const QString credential = m_registry->credentialFor(providerId);
    ProviderTask *task = providers::voiceCatalog(providerId, m_settings->apiKey(credential), this);
    if (!task) {
        emit voicesFailed(providerId, tr("This provider has no voice list."));
        return;
    }

    connect(task, &ProviderTask::succeeded, this, [this, providerId](const QVariantMap &result) {
        emit voicesLoaded(providerId, result.value(QStringLiteral("voices")).toList());
    });
    connect(task, &ProviderTask::failed, this, [this, providerId](const QString &error) {
        emit voicesFailed(providerId, error);
    });
}
