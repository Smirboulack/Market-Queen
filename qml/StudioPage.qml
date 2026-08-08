import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// The studio: steps on the left, the step being edited in the middle, a live
// recap on the right.
//
// The centre is deliberately the widest column. The form it replaces put six
// controls side by side and asked the user to judge the result afterwards;
// here every step gets the whole panel, and the recap is what carries the
// context between them.
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
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.gapLarge

                Item { implicitHeight: 4 }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.pagePadding
                    Layout.rightMargin: Theme.gapLarge
                    currentIndex: root.project.currentStep

                    StepProduct {}
                    StepActor {}
                    StepScript {}
                    StepSummary {}
                }

                Item { implicitHeight: Theme.gapLarge }
            }
        }

        // ------------------------------------------------------------ recap
        RecapPanel {
            Layout.fillHeight: true
        }
    }
}
