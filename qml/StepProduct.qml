import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 1 -- what is being sold.
//
// This step is pure context: nothing here is generated, everything here is fed
// to every step that follows.
ColumnLayout {
    id: root

    readonly property var project: App.project

    spacing: Theme.gapLarge

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: qsTr("What are you selling?")
            color: Theme.text
            font.pixelSize: Theme.fontHeading
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Everything the actor says and everything on screen is built from this.")
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    SectionCard {
        LabeledField {
            id: nameField
            label: qsTr("Product or service")
            placeholder: qsTr("e.g. Lumen glow serum")
            text: root.project.product.name !== undefined ? root.project.product.name : ""
            onTextChanged: root.project.setProductField("name", text)
        }

        LabeledArea {
            id: descriptionField
            label: qsTr("What it is")
            placeholder: qsTr("A vitamin C serum that clears dull skin in two weeks. Fragrance free, 30 ml.")
            areaHeight: 96
            text: root.project.product.description !== undefined
                  ? root.project.product.description : ""
            onTextChanged: root.project.setProductField("description", text)
        }

        LabeledField {
            id: audienceField
            label: qsTr("Who it is for")
            placeholder: qsTr("e.g. women 25-35 who care about clean beauty")
            text: root.project.product.audience !== undefined ? root.project.product.audience : ""
            onTextChanged: root.project.setProductField("audience", text)
        }
    }

    SectionCard {
        title: qsTr("Reference")
        subtitle: qsTr("A picture of the real product keeps it recognisable in every shot.")

        ImageDropField {
            id: photoField
            filePath: {
                const images = root.project.product.images;
                return images !== undefined && images.length > 0 ? images[0] : "";
            }
            onFilePathChanged: {
                const images = root.project.product.images;
                const current = images !== undefined && images.length > 0 ? images[0] : "";
                if (filePath === current)
                    return;
                if (current !== "")
                    root.project.removeProductImage(0);
                if (filePath !== "")
                    root.project.addProductImage(filePath);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        PrimaryButton {
            text: qsTr("Next: cast your actor")
            enabled: root.project.stepStates[0] !== undefined
                     && root.project.stepStates[0].valid
            onClicked: root.project.currentStep = 1
        }
    }

    Connections {
        target: App.project
        function onCleared() {
            nameField.text = "";
            descriptionField.text = "";
            audienceField.text = "";
            photoField.filePath = "";
        }
    }
}
