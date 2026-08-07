import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

ColumnLayout {
    id: root

    property string label: ""
    property string placeholder: ""
    property alias text: area.text
    property int areaHeight: 96

    spacing: 5
    Layout.fillWidth: true

    Text {
        text: root.label
        visible: root.label !== ""
        color: Theme.textDim
        font.pixelSize: Theme.fontSmall
        font.weight: Font.DemiBold
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: root.areaHeight
        radius: Theme.radiusSmall
        color: Theme.surfaceAlt
        border.width: 1
        border.color: area.activeFocus ? Theme.accent : Theme.border

        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 4
            clip: true

            TextArea {
                id: area
                placeholderText: root.placeholder
                color: Theme.text
                placeholderTextColor: Theme.textFaint
                font.pixelSize: Theme.fontBody
                wrapMode: TextArea.Wrap
                selectByMouse: true
                selectionColor: Theme.accent
                background: null
            }
        }
    }
}
