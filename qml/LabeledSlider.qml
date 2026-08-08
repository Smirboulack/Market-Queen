import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// A voice setting.
//
// The number is always on screen next to the label: these four values are the
// difference between a read that sounds human and one that sounds like an
// announcer, and "somewhere left of centre" is not something you can come back
// to tomorrow and reproduce.
ColumnLayout {
    id: root

    property string label: ""
    property string hint: ""
    property real from: 0.0
    property real to: 1.0
    property real value: 0.5
    property int decimals: 2

    signal edited(real value)

    spacing: 4
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            text: root.label
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        Text {
            text: root.value.toFixed(root.decimals)
            color: Theme.text
            font.pixelSize: Theme.fontSmall
            font.family: "monospace"
        }
    }

    Slider {
        id: slider

        Layout.fillWidth: true
        from: root.from
        to: root.to
        value: root.value
        implicitHeight: 22

        onMoved: {
            root.value = value;
            root.edited(value);
        }

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 4
            radius: 2
            color: Theme.surfaceHover

            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 16
            height: 16
            radius: 8
            color: slider.pressed ? Theme.accentHover : Theme.surface
            border.width: 2
            border.color: Theme.accent
        }
    }

    Text {
        Layout.fillWidth: true
        text: root.hint
        visible: root.hint !== ""
        color: Theme.textFaint
        font.pixelSize: Theme.fontSmall
        wrapMode: Text.WordWrap
    }
}
