import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

ApplicationWindow {
    id: window

    width: 1280
    height: 840
    minimumWidth: 1040
    minimumHeight: 680
    visible: true
    // Product and company name: neither is translated.
    title: "Super Infinity - SegfaultLabs"
    // No fade here: a theme switch snaps everywhere at once, and a window
    // that fades under content that snaps reads as two competing animations.
    color: Theme.background

    // Arabic mirrors the whole interface.
    LayoutMirroring.enabled: App.translator.rightToLeft
    LayoutMirroring.childrenInherit: true

    RowLayout {
        anchors.fill: parent
        spacing: 0

        SideNav {
            id: nav
            Layout.fillHeight: true
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: nav.currentIndex

            CreatePage {}
            LibraryPage {}
            SettingsPage {}
        }
    }
}
