import QtQuick
import QtQuick.Layouts
import SuperInfinity

// Two or three mutually exclusive options in one pill.
Rectangle {
    id: root

    property var options: []      // [{ label, value }]
    property var value: undefined

    signal picked(var value)

    implicitHeight: 34
    implicitWidth: row.implicitWidth + 8
    radius: Theme.radiusSmall
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.border

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        Repeater {
            model: root.options

            Rectangle {
                id: segment
                required property var modelData

                readonly property bool selected: root.value === modelData.value

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: text.implicitWidth + 28
                radius: Theme.radiusSmall - 2
                // Segments touch each other: hover snaps both ways (see
                // Theme.qml), so sliding across the pill never lights two.
                color: selected ? Theme.accent
                     : hover.hovered ? Theme.surfaceHover
                     : "transparent"

                Text {
                    id: text
                    anchors.centerIn: parent
                    text: segment.modelData.label
                    color: segment.selected ? "white" : Theme.textDim
                    font.pixelSize: Theme.fontSmall + 1
                    font.weight: segment.selected ? Font.DemiBold : Font.Normal
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.picked(segment.modelData.value)
                }
            }
        }
    }
}
