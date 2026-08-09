import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// One step's worth of recap, and the way back to that step.
//
// Empty blocks stay on screen rather than appearing as they fill: the shape of
// the whole ad should be readable from the first second, including the parts
// that are still missing.
Rectangle {
    id: root

    property string title: ""
    property string placeholder: ""
    property int stepIndex: -1
    property bool filled: false
    default property alias content: body.data

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + 2 * Theme.gap
    radius: Theme.radiusSmall
    color: hover.hovered ? Theme.surfaceAlt : "transparent"
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.title
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            Icon {
                name: "edit-line"
                size: 14
                visible: hover.hovered
                color: Theme.accent
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 4
            visible: root.filled
        }

        Text {
            Layout.fillWidth: true
            text: root.placeholder
            visible: !root.filled
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }
    }

    HoverHandler {
        id: hover
        enabled: root.stepIndex >= 0
                 && App.project.stepStates[root.stepIndex] !== undefined
                 && App.project.stepStates[root.stepIndex].reachable
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: hover.enabled
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: App.project.currentStep = root.stepIndex
    }
}
