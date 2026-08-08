import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pagePadding
        spacing: Theme.gapLarge

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 4

                Text {
                    text: qsTr("Library")
                    color: Theme.text
                    font.pixelSize: Theme.fontHeading
                    font.weight: Font.DemiBold
                }

                Text {
                    text: App.library.count === 0
                          ? qsTr("Everything you generate lands here.")
                          : qsTr("%1 project(s) in %2").arg(App.library.count)
                                                       .arg(App.settings.projectsDir)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideMiddle
                }
            }

            Item { Layout.fillWidth: true }

            GhostButton {
                text: qsTr("Open folder")
                onClicked: App.openPath(App.settings.projectsDir)
            }

            GhostButton {
                text: qsTr("Refresh")
                onClicked: App.library.refresh()
            }
        }

        GridView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 236
            cellHeight: 268
            model: App.library

            delegate: Item {
                required property string name
                required property string productName
                required property string hook
                required property string createdAt
                required property string dir
                required property string finalVideo
                required property string thumbnail
                required property bool success

                width: GridView.view.cellWidth
                height: GridView.view.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: Theme.gap
                    anchors.bottomMargin: Theme.gap
                    radius: Theme.radius
                    // Cards sit in a grid: hover snaps both ways, fill and
                    // border together (see the spec in Theme.qml).
                    color: hover.hovered ? Theme.surfaceAlt : Theme.surface
                    border.width: 1
                    border.color: hover.hovered ? Theme.borderStrong : Theme.border

                    HoverHandler {
                        id: hover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: {
                            if (finalVideo !== "")
                                App.openPath(finalVideo);
                            else
                                App.openPath(dir);
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 138
                            radius: Theme.radiusSmall
                            color: Theme.background
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: thumbnail
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: thumbnail !== ""
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "▦"
                                color: Theme.textFaint
                                font.pixelSize: 26
                                visible: thumbnail === ""
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                width: badge.implicitWidth + 12
                                height: 18
                                radius: 9
                                color: Theme.tint(success ? Theme.success : Theme.danger)

                                Text {
                                    id: badge
                                    anchors.centerIn: parent
                                    text: success ? qsTr("done") : qsTr("failed")
                                    color: success ? Theme.success : Theme.danger
                                    font.pixelSize: Theme.fontSmall - 1
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: productName !== "" ? productName : name
                            color: Theme.text
                            font.pixelSize: Theme.fontBody
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: hook
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: createdAt
                                color: Theme.textFaint
                                font.pixelSize: Theme.fontSmall
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: qsTr("Show file")
                                color: linkHover.hovered ? Theme.accentHover : Theme.accent
                                font.pixelSize: Theme.fontSmall

                                HoverHandler {
                                    id: linkHover
                                }

                                // ReleaseWithinBounds takes the exclusive grab
                                // on press, so the card's own TapHandler never
                                // sees this click. With the default (passive)
                                // policy both fired: one click revealed the
                                // file AND opened the video.
                                TapHandler {
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: App.revealPath(finalVideo !== "" ? finalVideo : dir)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: App.library.count === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "▦"
                    color: Theme.textFaint
                    font.pixelSize: 34
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No projects yet")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                }
            }
        }
    }
}
