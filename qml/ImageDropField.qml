import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import SuperInfinity

// Drop target + file picker for the product photo.
Rectangle {
    id: root

    property string filePath: ""

    Layout.fillWidth: true
    implicitHeight: 132
    radius: Theme.radius
    color: dropArea.containsDrag ? Theme.accentSoft : Theme.surfaceAlt
    border.width: 1
    border.color: dropArea.containsDrag ? Theme.accent : Theme.border

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Rectangle {
            Layout.preferredWidth: 104
            Layout.fillHeight: true
            radius: Theme.radiusSmall
            color: Theme.background
            border.width: 1
            border.color: Theme.border
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: 4
                source: root.filePath ? App.toFileUrl(root.filePath) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: root.filePath !== ""
            }

            Text {
                anchors.centerIn: parent
                text: "＋"
                color: Theme.textFaint
                font.pixelSize: 28
                visible: root.filePath === ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Text {
                text: root.filePath === "" ? qsTr("Product photo") : qsTr("Photo added")
                color: Theme.text
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.filePath === ""
                      ? qsTr("Drop a picture here, or browse. Optional, but it keeps the real product in frame.")
                      : root.filePath
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
                elide: Text.ElideMiddle
                maximumLineCount: 2
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                spacing: 8

                GhostButton {
                    text: qsTr("Browse")
                    onClicked: fileDialog.open()
                }

                GhostButton {
                    text: qsTr("Remove")
                    destructive: true
                    visible: root.filePath !== ""
                    onClicked: root.filePath = ""
                }
            }
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        onDropped: function (drop) {
            if (drop.hasUrls && drop.urls.length > 0)
                root.filePath = App.toLocalFile(drop.urls[0].toString());
        }
    }

    FileDialog {
        id: fileDialog
        title: qsTr("Choose a product photo")
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp)")]
        onAccepted: root.filePath = App.toLocalFile(selectedFile.toString())
    }
}
