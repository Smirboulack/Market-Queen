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
    property string glyph: ""
    // A round thumbnail on the left -- used by the actor chip.
    property string portrait: ""
    property bool active: value !== ""
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

        Text {
            text: root.glyph
            visible: root.glyph !== "" && root.portrait === ""
            color: root.accent ? "white"
                 : root.active ? Theme.accent : Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }

        Text {
            text: root.value !== "" ? root.value : root.label
            color: root.accent ? "white"
                 : root.active ? Theme.text : Theme.textDim
            font.pixelSize: Theme.fontSmall
            font.weight: root.active || root.accent ? Font.DemiBold : Font.Normal
        }

        Text {
            text: "⌄"
            visible: root.opensMenu
            color: root.accent ? "white" : Theme.textFaint
            font.pixelSize: Theme.fontSmall
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
