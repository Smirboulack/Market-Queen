import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// Step 2 -- the casting.
//
// The most important step in the app. A UGC ad lives or dies on whether the
// person on camera reads as a real human filming themselves, and no amount of
// scripting recovers a face that looks like a fragrance campaign.
//
// So the order here is deliberate: describe, cast a batch, reject most of it,
// keep one. The prompt that does the work is visible at the bottom rather than
// hidden, because tuning it is the real craft of this step.
ColumnLayout {
    id: root

    readonly property var project: App.project
    readonly property int batchSize: 4

    readonly property string portrait: project.actor.portraitPath !== undefined
                                       ? project.actor.portraitPath : ""
    readonly property var references: project.actor.referenceImages !== undefined
                                      ? project.actor.referenceImages : []

    // Q_INVOKABLE calls do not re-run on their own; touching the actor property
    // is what puts this binding back on the hook.
    readonly property string promptPreview: {
        root.project.actor;
        return App.casting.buildPrompt(root.project.actor);
    }

    property var castEstimate: ({ known: false, amount: 0 })

    function refreshEstimate() {
        castEstimate = App.casting.estimate(root.batchSize);
    }

    function setTrait(key, value) {
        const traits = root.project.actor.traits !== undefined ? root.project.actor.traits : ({});
        const next = {};
        for (const k in traits)
            next[k] = traits[k];
        next[key] = value;
        root.project.setActorField("traits", next);
    }

    function readTraits() {
        const traits = root.project.actor.traits !== undefined ? root.project.actor.traits : ({});
        gender.setValue(traits.gender);
        age.setValue(traits.age);
        style.setValue(traits.style);
        energy.setValue(traits.energy);
    }

    function resync() {
        briefField.text = root.project.actor.brief !== undefined ? root.project.actor.brief : "";
        decorField.text = root.project.actor.decor !== undefined ? root.project.actor.decor : "";
        nameField.text = root.project.actor.name !== undefined ? root.project.actor.name : "";
        readTraits();
    }

    spacing: Theme.gapLarge

    Component.onCompleted: {
        refreshEstimate();
        readTraits();
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: qsTr("Who says it?")
            color: Theme.text
            font.pixelSize: Theme.fontHeading
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("A real-looking person beats a polished one. Ordinary face, ordinary room.")
            color: Theme.textDim
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }
    }

    ActorStrip {
        currentId: root.project.actor.id !== undefined ? root.project.actor.id : ""
        onChosen: function (actor) { root.project.applyActor(actor); }
        onRemoveRequested: function (actorId) { App.actors.remove(actorId); }
    }

    SectionCard {
        title: qsTr("Describe them")
        subtitle: qsTr("Plain words work best. The traits below only fill in what you left out.")

        LabeledArea {
            id: briefField
            placeholder: qsTr("e.g. tired but friendly, no makeup, messy bun, slightly crooked smile")
            areaHeight: 72
            text: root.project.actor.brief !== undefined ? root.project.actor.brief : ""
            onTextChanged: root.project.setActorField("brief", text)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Theme.gap

            // Values stay English: they go into the prompt, not on screen.
            TraitPicker {
                id: gender
                label: qsTr("Gender")
                options: [
                    { label: qsTr("a woman"), value: "a woman" },
                    { label: qsTr("a man"), value: "a man" },
                    { label: qsTr("a non-binary person"), value: "a non-binary person" }
                ]
                onEdited: function (v) { root.setTrait("gender", v); }
            }

            TraitPicker {
                id: age
                label: qsTr("Age")
                options: [
                    { label: qsTr("early twenties"), value: "around 22 years old" },
                    { label: qsTr("late twenties"), value: "around 27 years old" },
                    { label: qsTr("thirties"), value: "around 35 years old" },
                    { label: qsTr("forties"), value: "around 45 years old" },
                    { label: qsTr("fifties or older"), value: "around 58 years old" }
                ]
                onEdited: function (v) { root.setTrait("age", v); }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Theme.gap

            TraitPicker {
                id: style
                label: qsTr("Dress")
                options: [
                    { label: qsTr("casual"), value: "dressed casually in a plain t-shirt" },
                    { label: qsTr("sportswear"), value: "in sportswear" },
                    { label: qsTr("office"), value: "in office clothes" },
                    { label: qsTr("streetwear"), value: "in streetwear" }
                ]
                onEdited: function (v) { root.setTrait("style", v); }
            }

            TraitPicker {
                id: energy
                label: qsTr("Energy")
                options: [
                    { label: qsTr("calm"), value: "calm, low energy" },
                    { label: qsTr("upbeat"), value: "upbeat and animated" },
                    { label: qsTr("just woke up"), value: "tired, just woke up" },
                    { label: qsTr("warm"), value: "warm and friendly" }
                ]
                onEdited: function (v) { root.setTrait("energy", v); }
            }
        }

        LabeledArea {
            id: decorField
            label: qsTr("Where they are")
            placeholder: qsTr("e.g. a small bathroom, towels on the floor, morning light through blinds")
            areaHeight: 64
            text: root.project.actor.decor !== undefined ? root.project.actor.decor : ""
            onTextChanged: root.project.setActorField("decor", text)
        }
    }

    SectionCard {
        title: qsTr("Someone real")
        subtitle: qsTr("Optional. A photo of an actual person keeps the same face across every shot.")

        ImageDropGrid {
            images: root.references
            onFilesAdded: function (urls) { root.project.addImages("actor", urls); }
            onRemoveRequested: function (index) { root.project.removeImage("actor", index); }
            onPrimaryRequested: function (index) { root.project.setPrimaryImage("actor", index); }
        }

        GhostButton {
            text: qsTr("Use this photo as the actor, without generating")
            visible: root.references.length > 0 && root.portrait !== root.references[0]
            onClicked: root.project.setActorField("portraitPath", root.references[0])
        }
    }

    SectionCard {
        title: qsTr("Cast")
        subtitle: qsTr("Four faces at a time. Keep the one that could be a real person's selfie.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PrimaryButton {
                text: App.casting.running
                      ? qsTr("Casting...")
                      : root.batchSize === 1 ? qsTr("Cast 1 portrait")
                      //: %1 is a number of portraits
                      : qsTr("Cast %1 portraits").arg(root.batchSize)
                loading: App.casting.running
                enabled: !App.casting.running
                onClicked: App.casting.generate(root.project.actor, root.batchSize)
            }

            GhostButton {
                text: qsTr("Cancel")
                destructive: true
                visible: App.casting.running
                onClicked: App.casting.cancel()
            }

            Text {
                text: root.castEstimate.known
                      ? Format.estimated(root.castEstimate.amount)
                      : qsTr("price unknown")
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: App.casting.error
            visible: text !== ""
            color: Theme.danger
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }

        PortraitGrid {
            candidates: App.casting.candidates
            chosen: root.portrait
            busy: App.casting.running
            received: App.casting.received
            requested: App.casting.requested
            onPicked: function (path) { root.project.setActorField("portraitPath", path); }
        }
    }

    // The voice belongs to the actor: saved with them, reloaded with them.
    SectionCard {
        title: qsTr("Their voice")
        subtitle: qsTr("Hear them for a fraction of a cent before you buy any video.")

        VoiceBooth {}
    }

    // Keeping an actor is what makes the effort above pay off twice.
    SectionCard {
        visible: root.portrait !== ""
        title: qsTr("Keep this actor")
        subtitle: qsTr("Saved actors are one click away in every ad after this one.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            LabeledField {
                id: nameField
                Layout.fillWidth: true
                placeholder: App.actors.suggestedName()
                text: root.project.actor.name !== undefined ? root.project.actor.name : ""
                onTextChanged: root.project.setActorField("name", text)
            }

            PrimaryButton {
                Layout.alignment: Qt.AlignBottom
                text: root.project.actor.id !== undefined && root.project.actor.id !== ""
                      ? qsTr("Update") : qsTr("Save actor")
                onClicked: {
                    const id = App.actors.save(root.project.actor);
                    root.project.setActorField("id", id);
                    const saved = App.actors.actor(id);
                    // save() may have copied the portrait into the library.
                    root.project.setActorField("portraitPath",
                                               saved.portraitPath !== undefined
                                               ? saved.portraitPath : root.portrait);
                    root.project.setActorField("name", saved.name);
                    nameField.text = saved.name;
                }
            }
        }
    }

    // The prompt is the product of this step, so it is readable rather than
    // hidden. casting.json in the config folder overrides how it is built.
    SectionCard {
        id: promptCard

        property bool expanded: false

        title: qsTr("What gets sent")

        GhostButton {
            text: promptCard.expanded ? qsTr("Hide the prompt") : qsTr("Show the prompt")
            onClicked: promptCard.expanded = !promptCard.expanded
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: promptCard.expanded

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: promptText.implicitHeight + 20
                radius: Theme.radiusSmall
                color: Theme.surfaceAlt
                border.width: 1
                border.color: Theme.border

                Text {
                    id: promptText
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.promptPreview
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                    font.family: "monospace"
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                Layout.fillWidth: true
                text: App.casting.overridden
                      //: %1 is a file path
                      ? qsTr("Built from your own %1.").arg(App.casting.overridePath)
                      //: %1 is a file path
                      : qsTr("Drop a casting.json at %1 to change how this is written.")
                            .arg(App.casting.overridePath)
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                wrapMode: Text.WordWrap
            }

            ModelPicker {
                category: "image"
                label: qsTr("Portrait model")
                onModelIdChanged: root.refreshEstimate()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        GhostButton {
            text: qsTr("Back")
            onClicked: root.project.currentStep = 0
        }

        Item { Layout.fillWidth: true }

        Text {
            text: qsTr("Cast someone to continue")
            visible: root.portrait === ""
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }

        PrimaryButton {
            text: qsTr("Next: write the script")
            enabled: root.project.stepStates[1] !== undefined
                     && root.project.stepStates[1].valid
            onClicked: root.project.currentStep = 2
        }
    }

    Connections {
        target: App.project
        function onCleared() { root.resync(); }
        function onActorReset() { root.resync(); }
    }
}
