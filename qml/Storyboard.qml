import QtMultimedia
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The finished ad, and the one scene you want to redo.
//
// This is the payoff of keeping every shot as its own file: a bad scene costs a
// few cents to re-shoot, against a dollar to relaunch the whole ad. Nothing else
// in the app changes the economics of iterating this much.
ColumnLayout {
    id: root

    readonly property var shots: App.pipeline.shots
    property int selected: 0

    property var redoCost: ({ known: false, amount: 0 })

    function refreshCost() {
        redoCost = App.pipeline.regenerateEstimate(root.selected);
    }

    readonly property var current: shots.length > selected && selected >= 0
                                   ? shots[selected] : null

    spacing: Theme.gap
    Layout.fillWidth: true

    onSelectedChanged: refreshCost()
    Component.onCompleted: refreshCost()

    // ------------------------------------------------------------- player
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 320
        radius: Theme.radius
        color: "black"
        border.width: 1
        border.color: Theme.border
        clip: true

        VideoOutput {
            id: output
            anchors.fill: parent
            anchors.margins: 1
            fillMode: VideoOutput.PreserveAspectFit
        }

        MediaPlayer {
            id: player
            source: App.pipeline.outputFile !== ""
                    ? App.toFileUrl(App.pipeline.outputFile) : ""
            videoOutput: output
            audioOutput: AudioOutput {}
        }

        // One control, centred, appearing on hover. A finished ad is something
        // you watch, not something you operate.
        Rectangle {
            anchors.centerIn: parent
            width: 56
            height: 56
            radius: 28
            color: Qt.alpha("black", 0.55)
            border.width: 1
            border.color: Qt.alpha("white", 0.4)
            visible: playerHover.hovered || player.playbackState !== MediaPlayer.PlayingState

            Icon {
                anchors.centerIn: parent
                name: player.playbackState === MediaPlayer.PlayingState
                      ? "pause-fill" : "play-fill"
                size: 22
                color: "white"
            }
        }

        HoverHandler { id: playerHover }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                if (player.playbackState === MediaPlayer.PlayingState)
                    player.pause();
                else
                    player.play();
            }
        }
    }

    // -------------------------------------------------------------- strip
    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: root.shots

            Rectangle {
                id: cell

                required property var modelData
                required property int index

                readonly property bool current: root.selected === cell.index

                width: 72
                height: 96
                radius: Theme.radiusSmall
                color: Theme.surfaceAlt
                border.width: cell.current ? 2 : 1
                border.color: cell.current ? Theme.accent
                            : cellHover.hovered ? Theme.borderStrong
                            : Theme.border
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: cell.current ? 2 : 1
                    source: cell.modelData.framePath !== ""
                            ? App.toFileUrl(cell.modelData.framePath) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: 16
                    color: Qt.alpha(Theme.background, 0.85)

                    Text {
                        anchors.centerIn: parent
                        //: %1 is a shot number, %2 a duration in seconds
                        text: qsTr("%1 · %2s")
                                  .arg(cell.index + 1)
                                  .arg(cell.modelData.duration.toFixed(1))
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                    }
                }

                HoverHandler {
                    id: cellHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        root.selected = cell.index;
                        // Jump the player to where this scene starts.
                        player.position = cell.modelData.start * 1000;
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ details
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: detail.implicitHeight + 2 * Theme.gap
        radius: Theme.radiusSmall
        color: Theme.surfaceAlt
        border.width: 1
        border.color: Theme.border
        visible: root.current !== null

        ColumnLayout {
            id: detail
            anchors.fill: parent
            anchors.margins: Theme.gap
            spacing: 6

            Text {
                //: %1 is a shot number
                text: qsTr("Scene %1").arg(root.selected + 1)
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.current !== null ? "« " + root.current.line + " »" : ""
                color: Theme.text
                font.pixelSize: Theme.fontBody
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: root.current !== null ? root.current.imagePrompt : ""
                visible: text !== ""
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                GhostButton {
                    text: App.pipeline.running
                          ? qsTr("Re-shooting...")
                          : root.redoCost.known
                            //: %1 is a price
                            ? qsTr("Re-shoot this scene — %1")
                                  .arg(Format.estimated(root.redoCost.amount))
                            : qsTr("Re-shoot this scene")
                    enabled: !App.pipeline.running
                    onClicked: App.pipeline.regenerateShot(root.selected)
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: qsTr("The voice-over is kept, so it is not paid for again.")
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }
            }
        }
    }

    Connections {
        target: App.pipeline
        function onShotsChanged() { root.refreshCost(); }
    }
}
