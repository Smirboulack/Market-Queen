import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

// Provider + model in one row. Remembers the last choice per category, and
// says so when the matching API key is missing.
ColumnLayout {
    id: root

    property string category: "text"
    property string label: ""
    property var providerList: App.registry.providers(category)
    property string providerId: ""
    property string modelId: ""

    property var providerInfo: ({})
    readonly property string credential: providerInfo.credential !== undefined ? providerInfo.credential : ""

    onProviderIdChanged: providerInfo = providerId ? App.registry.provider(providerId) : ({})
    property bool keyMissing: false

    // Assigning a model to an editable ComboBox resets editText to entry 0, so
    // nothing is persisted until the initial values are in place.
    property bool ready: false

    spacing: 5
    Layout.fillWidth: true

    onCredentialChanged: refreshKeyState()

    function refreshKeyState() {
        keyMissing = credential !== "" && !App.settings.hasApiKey(credential);
    }

    function applyModel(value) {
        if (!value)
            return;
        modelId = value;
        const index = modelCombo.find(value);
        if (index >= 0)
            modelCombo.currentIndex = index;
        else
            modelCombo.editText = value;
    }

    Connections {
        target: App.settings
        function onApiKeysChanged() { root.refreshKeyState(); }
    }

    // The catalogue carries translated notes: rebuild it on a language switch.
    Connections {
        target: App.registry
        function onRetranslated() {
            root.providerList = App.registry.providers(root.category);
            if (root.providerId)
                root.providerInfo = App.registry.provider(root.providerId);
        }
    }

    Component.onCompleted: {
        const savedProvider = App.settings.pref(category + "Provider", "");
        const known = providerList.some(function (p) { return p.id === savedProvider; });
        providerId = known ? savedProvider : App.registry.defaultProvider(category);
        providerCombo.currentIndex = providerCombo.indexOfValue(providerId);

        const savedModel = App.settings.pref(category + "Model", "");
        // callLater: let the combo finish binding its model first.
        Qt.callLater(function () {
            root.applyModel(savedModel !== "" ? savedModel : root.providerInfo.defaultModel);
            root.ready = true;
        });

        refreshKeyState();
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: root.label
            visible: root.label !== ""
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        Text {
            text: qsTr("no API key")
            visible: root.keyMissing
            color: Theme.warning
            font.pixelSize: Theme.fontSmall
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledCombo {
            id: providerCombo
            Layout.preferredWidth: 170
            model: root.providerList
            textRole: "label"
            valueRole: "id"

            onActivated: {
                root.providerId = currentValue;
                App.settings.setPref(root.category + "Provider", currentValue);
                // Model ids do not carry over between providers.
                root.applyModel(root.providerInfo.defaultModel);
            }
        }

        StyledCombo {
            id: modelCombo
            Layout.fillWidth: true
            editable: true
            model: root.providerInfo.models !== undefined ? root.providerInfo.models : []

            onEditTextChanged: {
                if (!root.ready)
                    return;
                root.modelId = editText;
                App.settings.setPref(root.category + "Model", editText);
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: root.providerInfo.note !== undefined ? root.providerInfo.note : ""
        color: Theme.textFaint
        font.pixelSize: Theme.fontSmall
        wrapMode: Text.WordWrap
        visible: text !== ""
    }
}
