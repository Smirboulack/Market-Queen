import QtQuick
import QtQuick.Controls.Basic
import SuperInfinity

Button {
    id: control

    property color accentColor: Theme.accent
    property bool loading: false

    implicitHeight: 42
    implicitWidth: Math.max(140, label.implicitWidth + 44)
    enabled: !loading

    background: Rectangle {
        radius: Theme.radius
        color: !control.enabled ? Theme.surfaceAlt
             : control.pressed ? Qt.darker(control.accentColor, 1.2)
             : control.hovered ? Theme.accentHover
             : control.accentColor

        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
    }

    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 8

            BusyIndicator {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                running: control.loading
                visible: control.loading
            }

            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                color: control.enabled ? "white" : Theme.textFaint
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }
        }
    }
}