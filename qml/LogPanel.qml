import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

Rectangle {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: Theme.radiusSmall
    color: Theme.background
    border.width: 1
    border.color: Theme.border
    clip: true

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 10
        spacing: 3
        model: App.log
        clip: true

        // Follow the tail unless the user scrolled up to read something.
        property bool pinned: true
        onContentYChanged: pinned = (contentY + height >= contentHeight - 24)
        onCountChanged: if (pinned) positionViewAtEnd()

        delegate: RowLayout {
            required property string time
            required property int level
            required property string message

            width: ListView.view.width
            spacing: 8

            Text {
                text: time
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                font.family: "Consolas"
                Layout.alignment: Qt.AlignTop
            }

            Text {
                Layout.fillWidth: true
                text: message
                color: Theme.levelColor(level)
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }
        }

        ScrollIndicator.vertical: ScrollIndicator {}
    }

    Text {
        anchors.centerIn: parent
        text: qsTr("Nothing yet.")
        color: Theme.textFaint
        font.pixelSize: Theme.fontSmall
        visible: list.count === 0
    }
}
