import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The studio: steps on the left, the step being edited in the middle, a live
// recap on the right.
//
// The centre fills the window rather than scrolling as a whole, because the
// scenario step owns its own scroll region: the written lines scroll, the
// prompt bar stays put at the bottom, and the actor drawer needs the full
// height. The steps that are just content bring their own ScrollView.
Item {
    id: root

    readonly property var project: App.project

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------------------ steps
        StepRail {
            Layout.fillHeight: true
            currentStep: root.project.currentStep
            stepStates: root.project.stepStates
            onStepPicked: function (index) { root.project.currentStep = index; }
        }

        // ------------------------------------------------------------ panel
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.project.currentStep

            ScrollView {
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    Item { implicitHeight: 4 }

                    StepProduct {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.pagePadding
                        Layout.rightMargin: Theme.gapLarge
                    }

                    Item { implicitHeight: Theme.gapLarge }
                }
            }

            StepScenario {}

            ScrollView {
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    Item { implicitHeight: 4 }

                    StepSummary {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.pagePadding
                        Layout.rightMargin: Theme.gapLarge
                    }

                    Item { implicitHeight: Theme.gapLarge }
                }
            }
        }

        // ------------------------------------------------------------ recap
        RecapPanel {
            Layout.fillHeight: true
        }
    }
}
