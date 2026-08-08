import QtQuick
import QtQuick.Controls.Basic
import MarketQueen

// Checkbox in the app's look: hover ring on the box, pointing-hand cursor,
// mirroring-aware so Arabic flips it like everything else. The control's own
// `hovered` is the only hover source (see the spec in Theme.qml).
CheckBox {
    id: control

    font.pixelSize: Theme.fontSmall + 1

    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    indicator: Rectangle {
        x: control.mirrored ? control.width - width : 0
        y: (control.height - height) / 2
        width: 16
        height: 16
        radius: 4
        color: control.checked ? Theme.accent : Theme.surfaceAlt
        border.width: 1
        border.color: control.checked ? Theme.accent
                    : control.enabled && control.hovered ? Theme.borderStrong
                    : Theme.border

        Text {
            anchors.centerIn: parent
            text: "✓"
            color: "white"
            font.pixelSize: 10
            font.weight: Font.Bold
            visible: control.checked
        }
    }

    contentItem: Text {
        text: control.text
        color: control.enabled ? Theme.textDim : Theme.textFaint
        font: control.font
        leftPadding: control.mirrored ? 0 : 24
        rightPadding: control.mirrored ? 24 : 0
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
    }
}
