import QtQuick
import QtQuick.Controls.Basic
import MarketQueen

Button {
    id: control

    property bool destructive: false

    implicitHeight: 34
    implicitWidth: label.implicitWidth + 28

    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    background: Rectangle {
        id: bg

        radius: Theme.radiusSmall
        color: "transparent"
        border.width: 1
        border.color: Theme.border

        // One authority for the visual state (see the spec in Theme.qml):
        // hover and press land instantly, only the way back to rest fades,
        // and fill and border always move together.
        states: [
            State {
                name: "pressed"
                when: control.pressed
                PropertyChanges {
                    bg {
                        color: Theme.surfaceHover
                        border.color: Theme.borderStrong
                    }
                }
            },
            State {
                name: "hover"
                when: control.enabled && control.hovered
                PropertyChanges {
                    bg {
                        border.color: Theme.borderStrong
                    }
                }
            }
        ]

        transitions: Transition {
            to: ""
            ColorAnimation {
                properties: "color,border.color"
                duration: Theme.hoverDuration
                easing.type: Easing.OutQuad
            }
        }
    }

    contentItem: Text {
        id: label
        text: control.text
        color: !control.enabled ? Theme.textFaint
             : control.destructive ? Theme.danger
             : Theme.text
        font.pixelSize: Theme.fontSmall + 1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
