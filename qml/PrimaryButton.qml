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

    // Cursor only. The hover *state* comes from control.hovered alone; when
    // the button is disabled the handler goes inactive and the cursor falls
    // back to the arrow by itself.
    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    background: Rectangle {
        id: bg

        radius: Theme.radius
        color: control.enabled ? control.accentColor : Theme.surfaceAlt

        states: [
            State {
                name: "pressed"
                when: control.pressed
                PropertyChanges { bg.color: Qt.darker(control.accentColor, 1.2) }
            },
            State {
                name: "hover"
                when: control.enabled && control.hovered
                PropertyChanges { bg.color: Theme.accentHover }
            }
        ]

        transitions: Transition {
            to: ""
            ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
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
