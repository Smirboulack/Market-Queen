#include "app/App.h"
#include "core/SettingsStore.h"
#include "i18n/Translator.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QWindow>

#ifdef Q_OS_WIN
#  include <dwmapi.h>
#  include <windows.h>
#endif

namespace {

// Windows keeps the title bar light unless the window opts in, so it has to
// follow the in-app theme.
void applyTitleBarTheme(const QQmlApplicationEngine &engine, bool dark)
{
#ifdef Q_OS_WIN
    for (QObject *object : engine.rootObjects()) {
        auto *window = qobject_cast<QWindow *>(object);
        if (!window)
            continue;
        const BOOL useDark = dark ? TRUE : FALSE;
        // DWMWA_USE_IMMERSIVE_DARK_MODE
        DwmSetWindowAttribute(reinterpret_cast<HWND>(window->winId()), 20, &useDark,
                              sizeof(useDark));
        // The attribute only repaints on the next frame change.
        window->requestUpdate();
    }
#else
    Q_UNUSED(engine);
    Q_UNUSED(dark);
#endif
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QCoreApplication::setOrganizationName(QStringLiteral("SuperInfinity"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("github.io"));
    QCoreApplication::setApplicationName(QStringLiteral("Super Infinity"));
    QCoreApplication::setApplicationVersion(QStringLiteral(APP_VERSION));

    // Basic is the only style that lets us fully control the look on every OS.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    // The singleton has to exist before the first window is built: it owns the
    // settings the UI binds to, and the language the UI is built in.
    auto *appObject = engine.singletonInstance<App *>("SuperInfinity", "App");
    if (!appObject)
        return -1;

    appObject->translator()->attach(&engine);
    appObject->translator()->applyLanguage(appObject->settings()->uiLanguage());

    engine.loadFromModule("SuperInfinity", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    applyTitleBarTheme(engine, appObject->settings()->darkMode());
    QObject::connect(appObject->settings(), &SettingsStore::darkModeChanged, &app,
                     [&engine, appObject]() {
                         applyTitleBarTheme(engine, appObject->settings()->darkMode());
                     });

    return app.exec();
}
