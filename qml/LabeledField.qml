import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

ColumnLayout {
    id: root

    property string label: ""
    property string placeholder: ""
    property alias text: field.text
    property alias echoMode: field.echoMode
    property alias readOnly: field.readOnly
    property string hint: ""

    signal editingFinished()

    spacing: 5
    Layout.fillWidth: true

    Text {
        text: root.label
        visible: root.label !== ""
        color: Theme.textDim
        font.pixelSize: Theme.fontSmall
        font.weight: Font.DemiBold
    }

    TextField {
        id: field

        Layout.fillWidth: true
        implicitHeight: Theme.fieldHeight
        placeholderText: root.placeholder
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font.pixelSize: Theme.fontBody
        leftPadding: 10
        rightPadding: 10
        selectByMouse: true
        selectionColor: Theme.accent

        onEditingFinished: root.editingFinished()

        background: Rectangle {
            radius: Theme.radiusSmall
            color: field.readOnly ? Theme.background : Theme.surfaceAlt
            border.width: 1
            border.color: field.activeFocus ? Theme.accent : Theme.border

            Behavior on border.color {
                ColorAnimation { duration: 120 }
            }
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
