import QtQuick
import QtQuick.Controls.Basic
import SuperInfinity

Button {
    id: control

    property bool destructive: false

    implicitHeight: 34
    implicitWidth: label.implicitWidth + 28

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.pressed ? Theme.surfaceHover
             : control.hovered ? Theme.surfaceAlt
             : "transparent"
        border.width: 1
        border.color: control.hovered ? Theme.borderStrong : Theme.border

        // Fill and border move together, or it looks like two animations.
        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
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
