import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The actors already cast, ready to be used again.
//
// This is what makes casting worth doing well once: a face that took four
// batches to land is one click away in every ad after this one.
ColumnLayout {
    id: root

    property string currentId: ""

    signal chosen(var actor)
    signal removeRequested(string actorId)

    spacing: 6
    Layout.fillWidth: true
    visible: App.actors.count > 0

    Text {
        text: qsTr("Your actors")
        color: Theme.textDim
        font.pixelSize: Theme.fontSmall
        font.weight: Font.DemiBold
    }

    ListView {
        Layout.fillWidth: true
        implicitHeight: 96
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        model: App.actors

        delegate: Rectangle {
            id: card

            required property string actorId
            required property string name
            required property string portraitPath
            required property var actor

            readonly property bool current: root.currentId !== "" && root.currentId === card.actorId

            width: 72
            height: 96
            radius: Theme.radiusSmall
            color: Theme.background
            border.width: card.current ? 2 : 1
            border.color: card.current ? Theme.accent
                        : cardHover.hovered ? Theme.borderStrong
                        : Theme.border
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: card.current ? 2 : 1
                source: card.portraitPath !== "" ? App.toFileUrl(card.portraitPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: 18
                color: Qt.alpha(Theme.background, 0.85)

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    text: card.name
                    color: Theme.text
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 3
                width: 18
                height: 18
                radius: 9
                visible: cardHover.hovered
                color: Qt.alpha(Theme.background, 0.85)
                border.width: 1
                border.color: Theme.borderStrong

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.danger
                    font.pixelSize: 12
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.removeRequested(card.actorId)
                }
            }

            HoverHandler {
                id: cardHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.chosen(card.actor)
            }
        }
    }
}
