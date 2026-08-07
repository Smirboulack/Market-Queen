import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

Rectangle {
    id: root

    property int currentIndex: 0

    implicitWidth: 208
    color: Theme.surface

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 9
                color: Theme.surfaceAlt
                clip: true

                Image {
                    anchors.fill: parent
                    source: "assets/icon-full.png"
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    asynchronous: true
                }
            }

            ColumnLayout {
                spacing: 0

                Text {
                    text: "Super Infinity"
                    color: Theme.text
                    font.pixelSize: Theme.fontBody + 1
                    font.weight: Font.DemiBold
                }

                Text {
                    // Company name: never translated.
                    text: "SegfaultLabs"
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: [
                    { label: qsTr("Create"), glyph: "✦" },
                    { label: qsTr("Library"), glyph: "▦" },
                    { label: qsTr("Settings"), glyph: "⚙" }
                ]

                Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Theme.radiusSmall
                    color: root.currentIndex === index ? Theme.accentSoft
                         : mouse.containsMouse ? Theme.surfaceAlt
                         : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 110 }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            text: modelData.glyph
                            color: root.currentIndex === index ? Theme.accent : Theme.textFaint
                            font.pixelSize: Theme.fontBody
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: root.currentIndex === index ? Theme.text : Theme.textDim
                            font.pixelSize: Theme.fontBody
                            font.weight: root.currentIndex === index ? Font.DemiBold : Font.Normal
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentIndex = index
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Bring-your-own-keys means no account, no quota, no subscription.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: statusColumn.implicitHeight + 20
            radius: Theme.radiusSmall
            color: Theme.surfaceAlt
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: statusColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: App.ffmpegPath !== "" ? Theme.success : Theme.warning
                    }

                    Text {
                        text: App.ffmpegPath !== "" ? qsTr("FFmpeg ready") : qsTr("FFmpeg missing")
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Your keys, your files.\nNothing is uploaded to us.")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                }
            }
        }

        Text {
            text: "v" + App.version
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }
    }
}
