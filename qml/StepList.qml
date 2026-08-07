import QtQuick
import QtQuick.Layouts
import SuperInfinity

// Pipeline steps. State values match Pipeline::StepState.
ColumnLayout {
    id: root

    property var steps: []

    spacing: 2
    Layout.fillWidth: true

    Repeater {
        model: root.steps

        RowLayout {
            required property var modelData
            required property int index

            readonly property int state: modelData.state
            readonly property bool isRunning: state === 1
            readonly property bool isDone: state === 2
            readonly property bool isSkipped: state === 3
            readonly property bool isFailed: state === 4

            Layout.fillWidth: true
            spacing: 10

            Item {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 30

                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: isDone ? Theme.success
                         : isFailed ? Theme.danger
                         : isRunning ? Theme.accent
                         : "transparent"
                    border.width: 1
                    border.color: isSkipped ? Theme.borderStrong
                                : (isDone || isFailed || isRunning) ? "transparent"
                                : Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: isDone ? "✓" : isFailed ? "✕" : isSkipped ? "–" : ""
                        color: isSkipped ? Theme.textFaint : "white"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }

                    SequentialAnimation on opacity {
                        running: isRunning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                    }
                }
            }

            Text {
                text: modelData.label
                color: isRunning ? Theme.text
                     : isDone ? Theme.text
                     : isFailed ? Theme.danger
                     : Theme.textFaint
                font.pixelSize: Theme.fontBody
                font.weight: isRunning ? Font.DemiBold : Font.Normal
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.maximumWidth: 190
                text: modelData.detail
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
