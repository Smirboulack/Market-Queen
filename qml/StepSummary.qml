import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 4 -- the last look before anything is paid for.
//
// The right-hand recap already carries the content, so this panel is about the
// render itself: the format, the subtitles, the price, and the progress once it
// is running.
ColumnLayout {
    id: root

    readonly property var project: App.project
    readonly property bool busy: App.pipeline.running

    spacing: Theme.gapLarge

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: qsTr("Ready to shoot")
            color: Theme.text
            font.pixelSize: Theme.fontHeading
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            //: %1 is a duration in seconds
            text: qsTr("About %1 s of video. Nothing is charged until you press generate.")
                      .arg(root.project.spokenSeconds.toFixed(1))
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    SectionCard {
        title: qsTr("Output")

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            ColumnLayout {
                Layout.preferredWidth: 150
                spacing: 5

                Text {
                    text: qsTr("Format")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.DemiBold
                }

                StyledCombo {
                    id: aspect
                    Layout.fillWidth: true
                    model: ["9:16", "1:1", "16:9"]
                    Component.onCompleted: currentIndex = Math.max(0, model.indexOf(root.project.aspectRatio))
                    onActivated: root.project.aspectRatio = currentValue
                }
            }

            Item { Layout.fillWidth: true }
        }

        StyledCheck {
            text: qsTr("Burn in subtitles (uses OpenAI Whisper)")
            checked: root.project.captions
            onToggled: root.project.captions = checked
        }
    }

    // The models are here, folded away: choosing them is not part of making an
    // ad, it is something you do once and forget.
    SectionCard {
        id: advanced

        property bool expanded: false

        title: qsTr("Advanced")
        subtitle: qsTr("Which models do the work. The defaults are sensible.")

        GhostButton {
            text: advanced.expanded ? qsTr("Hide models") : qsTr("Choose models manually")
            onClicked: advanced.expanded = !advanced.expanded
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            visible: advanced.expanded

            ModelPicker { category: "image"; label: qsTr("Frames") }
            ModelPicker { category: "video"; label: qsTr("Video") }
            ModelPicker { category: "voice"; label: qsTr("Voice") }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        GhostButton {
            text: qsTr("Back")
            enabled: !root.busy
            onClicked: root.project.currentStep = 2
        }

        Item { Layout.fillWidth: true }

        GhostButton {
            text: qsTr("Cancel")
            destructive: true
            visible: root.busy
            onClicked: App.pipeline.cancel()
        }

        PrimaryButton {
            text: root.busy ? qsTr("Generating...") : qsTr("Generate the ad")
            loading: root.busy
            enabled: root.project.complete && !root.busy
            onClicked: App.pipeline.start(root.project.request)
        }
    }

    // Progress, steps and log only matter once something is running.
    SectionCard {
        visible: root.busy || App.pipeline.outputFile !== "" || App.pipeline.progress > 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: Theme.surfaceAlt

            Rectangle {
                width: parent.width * App.pipeline.progress
                height: parent.height
                radius: 2
                color: Theme.accent

                Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
            }
        }

        StepList {
            steps: App.pipeline.steps
        }

        Text {
            Layout.fillWidth: true
            text: App.pipeline.status
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            visible: text !== ""
        }
    }

    // Result
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: resultColumn.implicitHeight + 24
        radius: Theme.radius
        color: Theme.accentSoft
        border.width: 1
        border.color: Theme.accent
        visible: !root.busy && App.pipeline.outputFile !== ""

        ColumnLayout {
            id: resultColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: qsTr("Your ad is ready")
                color: Theme.text
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                //: %1 is a price
                text: qsTr("Cost %1").arg(Format.estimated(App.pipeline.cost.total))
                visible: App.pipeline.cost.lines !== undefined
                         && App.pipeline.cost.lines.length > 0
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
            }

            RowLayout {
                spacing: 8

                GhostButton {
                    text: qsTr("Play")
                    onClicked: App.openPath(App.pipeline.outputFile)
                }

                GhostButton {
                    text: qsTr("Show file")
                    onClicked: App.revealPath(App.pipeline.outputFile)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: qsTr("Activity")
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        GhostButton {
            text: qsTr("Clear")
            onClicked: App.log.clear()
        }
    }

    LogPanel {}
}
