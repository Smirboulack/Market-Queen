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
        id: frame

        Layout.fillWidth: true

        // The field grows with its content instead of scrolling inside itself:
        // an inner Flickable would swallow the wheel and freeze the page scroll
        // whenever the pointer happened to be over a text box.
        implicitHeight: Math.max(root.areaHeight, area.implicitHeight + 16)

        radius: Theme.radiusSmall
        color: Theme.surfaceAlt
        border.width: 1
        border.color: Theme.border

        states: [
            State {
                name: "focus"
                when: area.activeFocus
                PropertyChanges {
                    frame { border.color: Theme.accent }
                }
            },
            State {
                name: "hover"
                when: hover.hovered
                PropertyChanges {
                    frame { border.color: Theme.borderStrong }
                }
            }
        ]

        transitions: Transition {
            to: ""
            ColorAnimation {
                properties: "border.color"
                duration: Theme.hoverDuration
                easing.type: Easing.OutQuad
            }
        }

        Behavior on implicitHeight {
            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
        }

        // On the frame, not the TextArea: the border must also react over the
        // 8 px ring the inner area does not cover. Single hover source.
        HoverHandler {
            id: hover
        }

        TextArea {
            id: area

            anchors.fill: parent
            anchors.margins: 8
            placeholderText: root.placeholder
            color: Theme.text
            placeholderTextColor: Theme.textFaint
            font.pixelSize: Theme.fontBody
            wrapMode: TextArea.Wrap
            selectByMouse: true
            selectionColor: Theme.accent
            selectedTextColor: "white"
            background: null
            padding: 0
        }
    }
}
