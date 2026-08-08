import QtQuick
import QtQuick.Layouts
import MarketQueen

Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property int step: 0
    default property alias content: body.data

    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.border

    implicitHeight: layout.implicitHeight + 2 * Theme.gapLarge
    Layout.fillWidth: true

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.gapLarge
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.title !== ""

            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 11
                color: Theme.accentSoft
                border.width: 1
                border.color: Theme.accent
                visible: root.step > 0

                Text {
                    anchors.centerIn: parent
                    text: root.step
                    color: Theme.accent
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.Bold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.title
                    color: Theme.text
                    font.pixelSize: Theme.fontTitle
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: root.subtitle
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall + 1
                    wrapMode: Text.WordWrap
                    visible: root.subtitle !== ""
                }
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Theme.gap
        }
    }
}
