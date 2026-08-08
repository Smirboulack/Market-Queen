import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The batch you just cast, and the one you keep.
//
// Casting is a filter, not a generator: the value is in seeing four faces side
// by side and rejecting three. So the tiles are large enough to judge a face on
// -- a thumbnail you cannot read is a thumbnail you cannot choose from.
ColumnLayout {
    id: root

    property var candidates: []
    property string chosen: ""
    property bool busy: false
    property int received: 0
    property int requested: 0

    signal picked(string path)

    spacing: Theme.gap
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.busy || root.candidates.length > 0

        Text {
            text: root.busy
                  //: %1 and %2 are counts of portraits
                  ? qsTr("Casting... %1 of %2").arg(root.received).arg(root.requested)
                  : qsTr("Pick the one that looks real")
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        Text {
            text: qsTr("None of them? Cast again.")
            visible: !root.busy && root.candidates.length > 0 && root.chosen === ""
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 10
        visible: root.busy || root.candidates.length > 0

        Repeater {
            model: root.candidates

            Rectangle {
                id: shot

                required property var modelData
                required property int index

                readonly property bool isChosen: root.chosen === shot.modelData.path

                width: 132
                height: 176
                radius: Theme.radiusSmall
                color: Theme.background
                border.width: shot.isChosen ? 2 : 1
                border.color: shot.isChosen ? Theme.accent
                            : shotHover.hovered ? Theme.borderStrong
                            : Theme.border
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: shot.isChosen ? 2 : 1
                    source: App.toFileUrl(shot.modelData.path)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }

                // The chosen one is the only one that says anything.
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 2
                    implicitHeight: 24
                    radius: Theme.radiusSmall
                    color: Theme.accent
                    visible: shot.isChosen

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cast")
                        color: "white"
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                    }
                }

                HoverHandler {
                    id: shotHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.picked(shot.modelData.path)
                }
            }
        }

        // Placeholders for the portraits still in flight, so the row does not
        // jump around as they land one by one.
        Repeater {
            model: Math.max(0, root.requested - root.candidates.length)

            Rectangle {
                width: 132
                height: 176
                radius: Theme.radiusSmall
                color: Theme.surfaceAlt
                border.width: 1
                border.color: Theme.border
                visible: root.busy

                Text {
                    anchors.centerIn: parent
                    text: "..."
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontTitle
                }
            }
        }
    }
}
