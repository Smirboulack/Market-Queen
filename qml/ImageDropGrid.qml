import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import MarketQueen

// Every picture of the product, not just one.
//
// The first image is the primary: it is the one handed to a model that only
// accepts a single reference. That makes ordering meaningful, so promoting an
// image is an explicit act -- the star -- rather than a side effect of dragging
// things around.
Rectangle {
    id: root

    property var images: []

    signal filesAdded(var urls)
    signal removeRequested(int index)
    signal primaryRequested(int index)

    readonly property int tileSize: 88

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 28
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.border

    // Drag-over works like hover: instant in, fill and border together, fade
    // only on the way out (see the spec in Theme.qml).
    states: State {
        name: "drag"
        when: dropArea.containsDrag
        PropertyChanges {
            root {
                color: Theme.accentSoft
                border.color: Theme.accent
            }
        }
    }

    transitions: Transition {
        to: ""
        ColorAnimation {
            properties: "color,border.color"
            duration: Theme.hoverDuration
            easing.type: Easing.OutQuad
        }
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ------------------------------------------------------- empty state
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.images.length === 0

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10
                text: "＋"
                color: Theme.textFaint
                font.pixelSize: 30
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Drop your product pictures here")
                color: Theme.text
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 6
                text: qsTr("As many as you like. Packshot, in use, close-up on the label.")
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
            }
        }

        // ------------------------------------------------------------- grid
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: root.images.length > 0

            Repeater {
                model: root.images

                Rectangle {
                    id: tile

                    required property string modelData
                    required property int index

                    readonly property bool primary: index === 0

                    width: root.tileSize
                    height: root.tileSize
                    radius: Theme.radiusSmall
                    color: Theme.background
                    border.width: tile.primary ? 2 : 1
                    border.color: tile.primary ? Theme.accent
                                : tileHover.hovered ? Theme.borderStrong
                                : Theme.border
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: tile.primary ? 2 : 1
                        source: App.toFileUrl(tile.modelData)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }

                    // Primary marker. Always lit on the first tile, offered on
                    // the others only while the pointer is on them.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 4
                        width: 20
                        height: 20
                        radius: 10
                        visible: tile.primary || tileHover.hovered
                        color: tile.primary ? Theme.accent : Qt.alpha(Theme.background, 0.85)
                        border.width: 1
                        border.color: tile.primary ? Theme.accent : Theme.borderStrong

                        Text {
                            anchors.centerIn: parent
                            text: tile.primary ? "★" : "☆"
                            color: tile.primary ? "white" : Theme.text
                            font.pixelSize: 11
                        }

                        TapHandler {
                            enabled: !tile.primary
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: root.primaryRequested(tile.index)
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        width: 20
                        height: 20
                        radius: 10
                        visible: tileHover.hovered
                        color: Qt.alpha(Theme.background, 0.85)
                        border.width: 1
                        border.color: Theme.borderStrong

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Theme.danger
                            font.pixelSize: 13
                        }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: root.removeRequested(tile.index)
                        }
                    }

                    HoverHandler {
                        id: tileHover
                    }
                }
            }

            // Add one more, in place, without hunting for the button below.
            Rectangle {
                width: root.tileSize
                height: root.tileSize
                radius: Theme.radiusSmall
                color: addHover.hovered ? Theme.surfaceHover : "transparent"
                border.width: 1
                border.color: addHover.hovered ? Theme.borderStrong : Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "＋"
                    color: Theme.textFaint
                    font.pixelSize: 22
                }

                HoverHandler {
                    id: addHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: fileDialog.open()
                }
            }
        }

        // ------------------------------------------------------------ footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.images.length === 0
                      ? ""
                      : root.images.length === 1
                        ? qsTr("1 picture. It is the reference.")
                        //: %1 is a number of pictures
                        : qsTr("%1 pictures. The starred one is the main reference.")
                              .arg(root.images.length)
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }

            GhostButton {
                text: qsTr("Browse")
                onClicked: fileDialog.open()
            }
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        onDropped: function (drop) {
            if (drop.hasUrls && drop.urls.length > 0)
                root.filesAdded(drop.urls);
        }
    }

    FileDialog {
        id: fileDialog
        title: qsTr("Choose product pictures")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp)")]
        onAccepted: root.filesAdded(selectedFiles)
    }
}
