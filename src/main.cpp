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

// Two icons, on purpose: the title bar draws ICON_SMALL at 16px, where the full
// character is unreadable, so it gets the head instead. Everything else
// (taskbar, alt-tab, explorer) keeps the full artwork.
void applyWindowIcons(const QQmlApplicationEngine &engine)
{
#ifdef Q_OS_WIN
    HINSTANCE instance = GetModuleHandleW(nullptr);

    const auto load = [instance](int resourceId, int metric) {
        return static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(resourceId), IMAGE_ICON,
                                             GetSystemMetrics(metric),
                                             GetSystemMetrics(metric == SM_CXSMICON ? SM_CYSMICON
                                                                                    : SM_CYICON),
                                             LR_DEFAULTCOLOR));
    };

    HICON smallIcon = load(2 /* IDI_APP_HEAD */, SM_CXSMICON);
    HICON bigIcon = load(1 /* IDI_APP_FULL */, SM_CXICON);

    for (QObject *object : engine.rootObjects()) {
        auto *window = qobject_cast<QWindow *>(object);
        if (!window)
            continue;
        const HWND hwnd = reinterpret_cast<HWND>(window->winId());
        if (smallIcon)
            SendMessageW(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(smallIcon));
        if (bigIcon)
            SendMessageW(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(bigIcon));
    }
#else
    Q_UNUSED(engine);
#endif
}

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

    QCoreApplication::setOrganizationName(QStringLiteral("MarketQueen"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("github.io"));
    QCoreApplication::setApplicationName(QStringLiteral("Market Queen"));
    QCoreApplication::setApplicationVersion(QStringLiteral(APP_VERSION));

    // Basic is the only style that lets us fully control the look on every OS.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // Taskbar, dock and alt-tab. Windows refines this per-window below.
    QGuiApplication::setWindowIcon(
        QIcon(QStringLiteral(":/qt/qml/MarketQueen/assets/icon-full.png")));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    // The singleton has to exist before the first window is built: it owns the
    // settings the UI binds to, and the language the UI is built in.
    auto *appObject = engine.singletonInstance<App *>("MarketQueen", "App");
    if (!appObject)
        return -1;

    appObject->translator()->attach(&engine);
    appObject->translator()->applyLanguage(appObject->settings()->uiLanguage());

    engine.loadFromModule("MarketQueen", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    applyWindowIcons(engine);
    applyTitleBarTheme(engine, appObject->settings()->darkMode());
    QObject::connect(appObject->settings(), &SettingsStore::darkModeChanged, &app,
                     [&engine, appObject]() {
                         applyTitleBarTheme(engine, appObject->settings()->darkMode());
                     });

    return app.exec();
}
