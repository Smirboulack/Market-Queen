import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// A chip that opens its options underneath.
//
// This is what the four stacked dropdowns became. Unset, it is a faint "⊕ Âge"
// taking twenty pixels; set, it says "35 ans" and lights up. The options only
// exist while you are looking at them.
Item {
    id: root

    property string label: ""
    // [{ label, value }]
    property var options: []
    property string value: ""

    signal picked(string value)

    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight

    readonly property string currentLabel: {
        for (let i = 0; i < options.length; ++i) {
            if (options[i].value === root.value)
                return options[i].label;
        }
        return "";
    }

    Chip {
        id: chip
        label: root.label
        value: root.currentLabel
        glyph: root.value === "" ? "⊕" : ""
        opensMenu: true
        onClicked: menu.open()
    }

    Menu {
        id: menu

        y: chip.height + 4
        implicitWidth: 190

        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        // "Doesn't matter" is an option, not the absence of one: taking a trait
        // back off has to be as easy as putting it on.
        Repeater {
            model: [{ label: qsTr("doesn't matter"), value: "" }].concat(root.options)

            MenuItem {
                id: item
                required property var modelData

                implicitHeight: 30

                contentItem: Text {
                    text: item.modelData.label
                    color: item.modelData.value === root.value ? Theme.accent : Theme.text
                    font.pixelSize: Theme.fontSmall
                    font.weight: item.modelData.value === root.value ? Font.DemiBold : Font.Normal
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                }

                background: Rectangle {
                    // Grouped rows snap both ways, like every other list here.
                    color: item.hovered ? Theme.surfaceAlt : "transparent"
                }

                onTriggered: {
                    root.value = item.modelData.value;
                    root.picked(item.modelData.value);
                }
            }
        }
    }
}
