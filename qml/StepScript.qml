import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 3 -- the words, scene by scene.
//
// The model no longer writes the script: it is the one part of an ad where a
// human knows something the model does not. What the model still does is say
// what the camera sees while each line is spoken -- direction, not writing.
//
// There is no duration control anywhere. The ad lasts exactly as long as the
// words take to say, and the running total below says how long that is.
ColumnLayout {
    id: root

    readonly property var project: App.project
    readonly property var scenes: project.scenes

    property var directCost: ({ known: false, amount: 0 })

    // Non-binding suggestions, shown as ghost text in an empty scene. They are
    // what tends to work, not a shape the script has to fit.
    readonly property var beats: [
        { name: qsTr("Hook"),    hint: qsTr("Name the frustration in one sentence. You have three seconds.") },
        { name: qsTr("Problem"), hint: qsTr("Make it concrete. What did you try that failed?") },
        { name: qsTr("Product"), hint: qsTr("Introduce it as what finally worked, not as a product.") },
        { name: qsTr("Proof"),   hint: qsTr("One specific detail. A number, a timeframe, a moment.") },
        { name: qsTr("Ask"),     hint: qsTr("Say what to do next, casually.") }
    ]

    function beatHint(index) {
        return index < beats.length
               ? beats[index].hint
               : qsTr("Keep going, or leave it here.");
    }

    function refreshCost() {
        directCost = App.director.estimate(root.project.request);
    }

    spacing: Theme.gapLarge

    Component.onCompleted: {
        // An empty script is an empty editor with nowhere to type.
        if (root.scenes.count === 0)
            root.scenes.add();
        refreshCost();
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: qsTr("What do they say?")
            color: Theme.text
            font.pixelSize: Theme.fontHeading
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("One line per scene, in your own words. No duration to pick: the ad lasts as long as the words do.")
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    Repeater {
        model: root.scenes

        SceneCard {
            id: card

            // The row's data comes in as `model`; `position` rather than
            // `index` because the delegate needs that name for the role.
            required property var model
            required property int index

            position: card.index
            total: root.scenes.count
            line: card.model.line
            kind: card.model.kind
            imagePrompt: card.model.imagePrompt
            videoPrompt: card.model.videoPrompt
            seconds: card.model.seconds
            directed: card.model.directed
            beatHint: root.beatHint(card.index)

            onLineEdited: function (text) { root.scenes.setField(card.index, "line", text); }
            onKindEdited: function (v) { root.scenes.setField(card.index, "kind", v); }
            onImagePromptEdited: function (t) { root.scenes.setField(card.index, "imagePrompt", t); }
            onVideoPromptEdited: function (t) { root.scenes.setField(card.index, "videoPrompt", t); }
            onMoveRequested: function (to) { root.scenes.move(card.index, to); }
            onRemoveRequested: root.scenes.remove(card.index)

            // A direction pass rewrites the visuals behind the fields' backs;
            // the fields dropped their bindings the moment they were typed in.
            Connections {
                target: root.scenes
                function onDataChanged() { card.resync(); }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        GhostButton {
            text: qsTr("Add a scene")
            onClicked: root.scenes.add()
        }

        Item { Layout.fillWidth: true }

        Text {
            //: %1 is a count of scenes, %2 a duration in seconds
            text: qsTr("%1 scene(s) · %2 s")
                      .arg(root.scenes.count)
                      .arg(root.project.spokenSeconds.toFixed(1))
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
        }

        Text {
            text: qsTr("15 to 30 s converts best")
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }
    }

    // Direction is the one LLM call left, and it never touches a spoken word.
    SectionCard {
        title: qsTr("Direct the shots")
        subtitle: qsTr("Turns your lines into what the camera sees. Your words are never changed.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PrimaryButton {
                text: App.director.running ? qsTr("Directing...") : qsTr("Direct the shots")
                loading: App.director.running
                enabled: !App.director.running
                         && root.project.stepStates[2] !== undefined
                         && root.project.stepStates[2].valid
                onClicked: App.director.direct(root.project.request)
            }

            GhostButton {
                text: qsTr("Cancel")
                destructive: true
                visible: App.director.running
                onClicked: App.director.cancel()
            }

            Text {
                text: root.directCost.known
                      ? Format.estimated(root.directCost.amount)
                      : qsTr("price unknown")
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: App.director.error
            visible: text !== ""
            color: Theme.danger
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Optional: undirected scenes still render, from a generic prompt. Directing them is what keeps the same person in the same room across every cut.")
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        GhostButton {
            text: qsTr("Back")
            onClicked: root.project.currentStep = 1
        }

        Item { Layout.fillWidth: true }

        PrimaryButton {
            text: qsTr("Next: review")
            enabled: root.project.stepStates[2] !== undefined
                     && root.project.stepStates[2].valid
            onClicked: root.project.currentStep = 3
        }
    }

    Connections {
        target: App.director
        function onDirected(shots) { root.project.applyDirection(shots); }
    }

    Connections {
        target: App.project
        function onRequestChanged() { root.refreshCost(); }
        function onCleared() {
            if (root.scenes.count === 0)
                root.scenes.add();
        }
    }
}
