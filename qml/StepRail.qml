import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The four steps, in order, with their state.
//
// A step is reachable once every step before it is satisfied, which makes the
// first pass linear and every pass after it free. Unreachable steps stay
// visible but inert: seeing what comes next is the point of a rail.
Rectangle {
    id: root

    property int currentStep: 0
    property var stepStates: []

    signal stepPicked(int index)

    implicitWidth: 200
    color: Theme.surface

    readonly property var labels: [
        { title: qsTr("Product"),  hint: qsTr("What you are selling") },
        { title: qsTr("Scenario"), hint: qsTr("Who says it, and what") },
        { title: qsTr("Summary"),  hint: qsTr("Check and generate") }
    ]

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gap + 4
        spacing: 4

        Text {
            Layout.bottomMargin: 6
            text: qsTr("YOUR AD")
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        Repeater {
            model: root.labels

            Rectangle {
                id: row

                required property var modelData
                required property int index

                readonly property var stepState: root.stepStates[index] !== undefined
                                                 ? root.stepStates[index]
                                                 : ({ valid: false, reachable: false })
                readonly property bool current: root.currentStep === index

                Layout.fillWidth: true
                implicitHeight: 52
                radius: Theme.radiusSmall
                // Grouped rows snap both ways, like the side nav.
                color: row.current ? Theme.accentSoft
                     : (rowHover.hovered && row.stepState.reachable) ? Theme.surfaceAlt
                     : "transparent"
                opacity: row.stepState.reachable ? 1.0 : 0.4

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Number, or a tick once the step holds together.
                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 11
                        color: row.stepState.valid ? Theme.accent
                             : row.current ? Theme.accentSoft
                             : "transparent"
                        border.width: 1
                        border.color: row.stepState.valid || row.current
                                      ? Theme.accent : Theme.borderStrong

                        Text {
                            anchors.centerIn: parent
                            text: row.stepState.valid ? "✓" : (row.index + 1)
                            color: row.stepState.valid ? "white"
                                 : row.current ? Theme.accent : Theme.textFaint
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Bold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: row.modelData.title
                            color: row.current ? Theme.text : Theme.textDim
                            font.pixelSize: Theme.fontBody
                            font.weight: row.current ? Font.DemiBold : Font.Normal
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.hint
                            color: Theme.textFaint
                            font.pixelSize: Theme.fontSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                HoverHandler {
                    id: rowHover
                    enabled: row.stepState.reachable
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: row.stepState.reachable
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.stepPicked(row.index)
                }
            }
        }

        Item { Layout.fillHeight: true }

        GhostButton {
            Layout.fillWidth: true
            text: qsTr("Start over")
            destructive: true
            visible: App.project.furthestStep > 0 && !App.pipeline.running
            onClicked: App.project.clear()
        }
    }
}
