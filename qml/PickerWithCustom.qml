import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

// A fixed list of choices, plus a last "Other…" entry that reveals a free-text
// field. Everything the user picks is a real option; typing is opt-in, so the
// combo itself stays a plain click target.
ColumnLayout {
    id: root

    property string label: ""
    property var options: []                    // [{ label, value }]
    property bool allowCustom: true
    property string customLabel: qsTr("Other...")
    property string customPlaceholder: qsTr("Type your own")
    property string hint: ""

    readonly property string customToken: "__custom__"
    readonly property var comboModel: allowCustom
        ? options.concat([{ label: customLabel, value: customToken }])
        : options

    property bool isCustom: false

    // What the caller should read. The custom token is internal and must never
    // leak out as a value, which is what happens when the option list is empty
    // and the only entry is "Other…".
    readonly property string value: {
        if (isCustom)
            return customField.text.trim();
        const v = combo.currentValue;
        return (v === undefined || v === customToken) ? "" : String(v);
    }

    signal valueEdited(string value)

    spacing: 5
    Layout.fillWidth: true

    // Selects `v` if it is one of the options, otherwise drops it into the
    // free-text field so a saved custom value survives a restart.
    function setValue(v) {
        const index = comboModel.findIndex(function (o) { return o.value === v; });
        if (v && index >= 0 && v !== customToken) {
            combo.currentIndex = index;
            isCustom = false;
        } else if (v && allowCustom) {
            customField.text = v;
            combo.currentIndex = comboModel.length - 1;
            isCustom = true;
        } else {
            combo.currentIndex = 0;
        }
        // Keep the flag in sync with what is actually selected.
        isCustom = allowCustom && combo.currentValue === customToken;
    }

    Text {
        text: root.label
        visible: root.label !== ""
        color: Theme.textDim
        font.pixelSize: Theme.fontSmall
        font.weight: Font.DemiBold
    }

    StyledCombo {
        id: combo

        Layout.fillWidth: true
        model: root.comboModel
        textRole: "label"
        valueRole: "value"

        onActivated: {
            root.isCustom = root.allowCustom && currentValue === root.customToken;
            root.valueEdited(root.value);
        }
    }

    TextField {
        id: customField

        Layout.fillWidth: true
        visible: root.isCustom
        implicitHeight: Theme.fieldHeight
        placeholderText: root.customPlaceholder
        color: Theme.text
        placeholderTextColor: Theme.textFaint
        font.pixelSize: Theme.fontBody
        leftPadding: 12
        rightPadding: 12
        selectByMouse: true
        selectionColor: Theme.accent
        selectedTextColor: "white"

        onTextChanged: if (root.isCustom) root.valueEdited(root.value)

        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surfaceAlt
            border.width: 1
            border.color: customField.activeFocus ? Theme.accent : Theme.border

            Behavior on border.color {
                ColorAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutQuad }
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
