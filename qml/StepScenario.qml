import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 2 -- the scenario: who says it, and what they say.
//
// One step, two halves, and no form in either. The words go into a prompt bar
// and come out as numbered lines above it, one per send -- which is both what a
// chat input does and exactly the shape the pipeline needs, since every scene
// buys its own audio and its own clip.
//
// The actor is a chip in that bar rather than a panel of its own: casting is
// something you do *while* writing, and you recast the moment a line stops
// sounding like the person you picked.
Item {
    id: root

    readonly property var project: App.project
    readonly property var scenes: project.scenes
    readonly property string portrait: project.actor.portraitPath !== undefined
                                       ? project.actor.portraitPath : ""
    readonly property string actorName: {
        const n = project.actor.name;
        return n !== undefined && n !== "" ? n : qsTr("Actor");
    }

    property bool drawerOpen: false
    property string nextKind: "talking"
    property var directCost: ({ known: false, amount: 0 })

    readonly property var beats: [
        qsTr("Name the frustration in one sentence. You have three seconds."),
        qsTr("Make it concrete. What did you try that failed?"),
        qsTr("Introduce it as what finally worked, not as a product."),
        qsTr("One specific detail. A number, a timeframe, a moment."),
        qsTr("Say what to do next, casually.")
    ]

    function hint() {
        const i = root.scenes.count;
        return i < beats.length ? beats[i] : qsTr("Keep going, or leave it here.");
    }

    function refreshCost() {
        directCost = App.director.estimate(root.project.request);
    }

    Component.onCompleted: refreshCost()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------------------ script
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.gapLarge
            Layout.topMargin: 4
            Layout.bottomMargin: Theme.gapLarge
            spacing: Theme.gap

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: qsTr("Scenario")
                    color: Theme.text
                    font.pixelSize: Theme.fontHeading
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Write what they say. One line, one scene.")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    wrapMode: Text.WordWrap
                }
            }

            // The lines already written, newest at the bottom, like a thread.
            ScrollView {
                id: thread

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.scenes

                        SceneBubble {
                            id: bubble

                            required property var model
                            required property int index

                            position: bubble.index
                            total: root.scenes.count
                            line: bubble.model.line
                            kind: bubble.model.kind
                            imagePrompt: bubble.model.imagePrompt
                            seconds: bubble.model.seconds
                            directed: bubble.model.directed

                            onLineEdited: function (text) {
                                root.scenes.setField(bubble.index, "line", text);
                            }
                            onKindToggled: root.scenes.setField(
                                bubble.index, "kind",
                                bubble.model.kind === "broll" ? "talking" : "broll")
                            onMoveRequested: function (to) { root.scenes.move(bubble.index, to); }
                            onRemoveRequested: root.scenes.remove(bubble.index)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.gapLarge
                        Layout.bottomMargin: Theme.gapLarge
                        text: qsTr("Nothing written yet. The first line is the hook — you have three seconds.")
                        visible: root.scenes.count === 0
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // --------------------------------------------------------- bar
            PromptBar {
                id: bar

                placeholder: root.hint()
                onSubmitted: function (text) {
                    root.scenes.add(text);
                    if (root.nextKind === "broll") {
                        root.scenes.setField(root.scenes.count - 1, "kind", "broll");
                        root.nextKind = "talking";
                    }
                    bar.clear();
                }

                Chip {
                    portrait: root.portrait
                    icon: root.portrait === "" ? "user-add-line" : ""
                    label: qsTr("Pick an actor")
                    value: root.portrait !== "" ? root.actorName : ""
                    accent: root.portrait === ""
                    opensMenu: true
                    onClicked: root.drawerOpen = true
                }

                Chip {
                    label: qsTr("Talking")
                    value: root.nextKind === "broll" ? qsTr("Product shot") : ""
                    icon: root.nextKind === "broll" ? "image-line" : "user-smile-line"
                    onClicked: root.nextKind = root.nextKind === "broll" ? "talking" : "broll"
                }
            }

            // ------------------------------------------------------- footer
            //
            // One elastic cell in the middle: without it the row's implicit
            // width wins over the column's and the whole panel slides under the
            // recap. It carries the error when there is one, the advice when
            // there is not, and shrinks to nothing before anything else moves.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    //: %1 is a count of scenes, %2 a duration in seconds
                    text: qsTr("%1 scene(s) · %2 s")
                              .arg(root.scenes.count)
                              .arg(root.project.spokenSeconds.toFixed(1))
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: App.director.error !== "" ? App.director.error
                                                    : qsTr("15 to 30 s converts best")
                    color: App.director.error !== "" ? Theme.danger : Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                    elide: Text.ElideRight
                }

                Chip {
                    label: App.director.running ? qsTr("Directing…") : qsTr("Direct the shots")
                    detail: !App.director.running && root.directCost.known
                            ? Format.estimated(root.directCost.amount) : ""
                    icon: "magic-line"
                    enabled: !App.director.running && root.scenes.count > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: App.director.direct(root.project.request)
                }

                PrimaryButton {
                    text: qsTr("Next: review")
                    enabled: root.project.stepStates[1] !== undefined
                             && root.project.stepStates[1].valid
                    onClicked: root.project.currentStep = 2
                }
            }
        }

        // ------------------------------------------------------------ drawer
        ActorPanel {
            Layout.preferredWidth: root.drawerOpen ? 400 : 0
            Layout.minimumWidth: root.drawerOpen ? 400 : 0
            Layout.fillHeight: true
            visible: Layout.preferredWidth > 0
            clip: true
            onCloseRequested: root.drawerOpen = false

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }
    }

    Connections {
        target: App.director
        function onDirected(shots) { root.project.applyDirection(shots); }
    }

    Connections {
        target: App.project
        function onRequestChanged() { root.refreshCost(); }
    }
}
