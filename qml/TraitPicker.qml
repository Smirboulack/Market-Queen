import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// One optional trait.
//
// Every trait starts on "doesn't matter" and contributes nothing to the prompt
// until it is set. They exist to fill gaps the free description left, not to
// turn casting back into a form -- which is why there are four of them and not
// fourteen.
ColumnLayout {
    id: root

    property string label: ""
    // [{ label: <translated>, value: <English prompt fragment> }]
    property var options: []
    property string value: ""

    signal edited(string value)

    spacing: 5
    Layout.fillWidth: true

    function setValue(v) {
        root.value = v === undefined ? "" : v;
        combo.currentIndex = Math.max(0, combo.indexOfValue(root.value));
    }

    Text {
        text: root.label
        color: Theme.textDim
        font.pixelSize: Theme.fontSmall
        font.weight: Font.DemiBold
    }

    StyledCombo {
        id: combo

        Layout.fillWidth: true
        model: [{ label: qsTr("doesn't matter"), value: "" }].concat(root.options)
        textRole: "label"
        valueRole: "value"

        onActivated: {
            root.value = currentValue;
            root.edited(currentValue);
        }
    }
}
