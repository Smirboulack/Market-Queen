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
    color: Theme.background

    // Arabic mirrors the whole interface.
    LayoutMirroring.enabled: App.translator.rightToLeft
    LayoutMirroring.childrenInherit: true

    Behavior on color {
        ColorAnimation { duration: 160 }
    }

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
