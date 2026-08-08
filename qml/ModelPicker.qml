import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Provider + model. Both are fixed lists; the model list ends with an "Other…"
// entry so a brand-new model id can still be pasted in without waiting for a
// release.
ColumnLayout {
    id: root

    property string category: "text"
    property string label: ""
    property var providerList: App.registry.providers(category)
    property string providerId: ""
    property string modelId: ""

    property var providerInfo: ({})
    readonly property string credential: providerInfo.credential !== undefined ? providerInfo.credential : ""
    property bool keyMissing: false
    property bool ready: false

    // The catalogue's models, each with its unit price appended. Seeing
    // "$0.28/s" while choosing is what stops the total on the right being a
    // surprise; a model we have no price for is simply left plain.
    readonly property var pricedModels: {
        const models = providerInfo.models !== undefined ? providerInfo.models : [];
        return models.map(function (model) {
            const price = Format.unitPriceLabel(App.pricing.unitPrice(model.value));
            return {
                label: price === "" ? model.label : model.label + "   " + price,
                value: model.value
            };
        });
    }

    spacing: 5
    Layout.fillWidth: true

    onProviderIdChanged: providerInfo = providerId ? App.registry.provider(providerId) : ({})

    function refreshKeyState() {
        keyMissing = credential !== "" && !App.settings.hasApiKey(credential);
    }

    onCredentialChanged: refreshKeyState()

    Connections {
        target: App.settings
        function onApiKeysChanged() { root.refreshKeyState(); }
    }

    // The catalogue carries translated labels: rebuild it on a language switch.
    Connections {
        target: App.registry
        function onRetranslated() {
            root.providerList = App.registry.providers(root.category);
            if (root.providerId) {
                root.providerInfo = App.registry.provider(root.providerId);
                modelPicker.setValue(root.modelId);
            }
        }
    }

    Component.onCompleted: {
        const savedProvider = App.settings.pref(category + "Provider", "");
        const known = providerList.some(function (p) { return p.id === savedProvider; });
        providerId = known ? savedProvider : App.registry.defaultProvider(category);
        providerCombo.currentIndex = providerCombo.indexOfValue(providerId);

        const savedModel = App.settings.pref(category + "Model", "");
        modelId = savedModel !== "" ? savedModel : providerInfo.defaultModel;
        modelPicker.setValue(modelId);

        refreshKeyState();
        ready = true;
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
        Layout.alignment: Qt.AlignTop
        spacing: 8

        StyledCombo {
            id: providerCombo

            Layout.preferredWidth: 170
            Layout.alignment: Qt.AlignTop
            model: root.providerList
            textRole: "label"
            valueRole: "id"

            onActivated: {
                root.providerId = currentValue;
                App.settings.setPref(root.category + "Provider", currentValue);
                // Model ids do not carry over between providers.
                root.modelId = root.providerInfo.defaultModel;
                modelPicker.setValue(root.modelId);
                App.settings.setPref(root.category + "Model", root.modelId);
            }
        }

        PickerWithCustom {
            id: modelPicker

            Layout.fillWidth: true
            options: root.pricedModels
            customLabel: qsTr("Other model id...")
            customPlaceholder: qsTr("e.g. fal-ai/some-new-model")

            onValueEdited: function (value) {
                if (!root.ready)
                    return;
                root.modelId = value;
                App.settings.setPref(root.category + "Model", value);
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
