import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// A pill. The only control this interface has left.
//
// It replaces the dropdowns, checkboxes and labelled fields the studio used to
// stack: a chip is off until you touch it, shows its value once you do, and
// takes exactly the room its own text needs. Ten of them read as a sentence;
// ten dropdowns read as a form.
Rectangle {
    id: root

    property string label: ""
    // Set once chosen; the chip then shows this instead of the label.
    property string value: ""
    // Shown *after* the label rather than in place of it -- for a chip that
    // keeps its name and carries a figure, like an action and its price.
    property string detail: ""
    property string icon: ""
    // A round thumbnail on the left -- used by the actor chip.
    property string portrait: ""
    property bool active: value !== "" || detail !== ""
    property bool opensMenu: false
    property bool accent: false

    signal clicked()

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 22
    radius: height / 2

    color: root.accent ? Theme.accent
         : root.active ? Theme.accentSoft
         : hover.hovered ? Theme.surfaceHover
         : "transparent"
    border.width: 1
    border.color: root.accent ? Theme.accent
                : root.active ? Theme.accent
                : hover.hovered ? Theme.borderStrong
                : Theme.border

    Behavior on color {
        ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 10
            visible: root.portrait !== ""
            color: Theme.surfaceAlt
            clip: true

            Image {
                anchors.fill: parent
                source: root.portrait !== "" ? App.toFileUrl(root.portrait) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
            }
        }

        Icon {
            name: root.icon
            size: 15
            visible: root.icon !== "" && root.portrait === ""
            color: root.accent ? "white"
                 : root.active ? Theme.accent : Theme.textFaint
        }

        Text {
            text: root.value !== "" ? root.value : root.label
            color: root.accent ? "white"
                 : root.active ? Theme.text : Theme.textDim
            font.pixelSize: Theme.fontSmall
            font.weight: root.active || root.accent ? Font.DemiBold : Font.Normal
        }

        Text {
            text: root.detail
            visible: root.detail !== ""
            color: root.accent ? Qt.alpha("white", 0.75) : Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }

        Icon {
            name: "arrow-down-s-line"
            size: 14
            visible: root.opensMenu
            color: root.accent ? "white" : Theme.textFaint
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.clicked()
    }
}
