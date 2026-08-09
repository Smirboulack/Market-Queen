import QtMultimedia
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import MarketQueen

// The casting drawer.
//
// Three prompt bars, one under the other: who they are, where they are, how they
// sound. No labelled fields, no stacked dropdowns -- the optional traits are
// chips inside the first bar, and the four voice settings hide behind four
// presets, because nobody tunes similarity_boost by hand on the first pass.
Rectangle {
    id: root

    readonly property var project: App.project
    readonly property var actor: project.actor
    readonly property string portrait: actor.portraitPath !== undefined ? actor.portraitPath : ""
    readonly property var references: actor.referenceImages !== undefined
                                      ? actor.referenceImages : []

    property var castCost: ({ known: false, amount: 0 })
    property var auditionCost: ({ known: false, amount: 0 })
    property string auditionLine: qsTr("Honestly, I did not think this would work.")
    property bool fineTuning: false

    signal closeRequested()

    function setting(key, fallback) {
        return root.actor[key] !== undefined ? root.actor[key] : fallback;
    }

    function setTrait(key, value) {
        const traits = root.actor.traits !== undefined ? root.actor.traits : ({});
        const next = {};
        for (const k in traits)
            next[k] = traits[k];
        next[key] = value;
        root.project.setActorField("traits", next);
    }

    function trait(key) {
        const traits = root.actor.traits !== undefined ? root.actor.traits : ({});
        return traits[key] !== undefined ? traits[key] : "";
    }

    function refresh() {
        castCost = App.casting.estimate(4);
        auditionCost = App.voiceBooth.estimate(root.auditionLine);
    }

    function resync() {
        briefBar.text = root.setting("brief", "");
        decorBar.text = root.setting("decor", "");
        gender.value = root.trait("gender");
        age.value = root.trait("age");
        dress.value = root.trait("style");
        energy.value = root.trait("energy");
        voiceBox.setValue(root.setting("voiceId", ""));
    }

    color: Theme.surface
    border.width: 1
    border.color: Theme.border

    Component.onCompleted: { refresh(); resync(); }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLarge
        spacing: Theme.gap

        // ------------------------------------------------------------ header
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: qsTr("Actor")
                color: Theme.text
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            IconButton {
                icon: "close-line"
                onClicked: root.closeRequested()
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.gap

                // ------------------------------------------------- saved
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: App.actors.count > 0

                    Text {
                        text: qsTr("Your actors")
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                    }

                    ListView {
                        Layout.fillWidth: true
                        implicitHeight: 76
                        orientation: ListView.Horizontal
                        spacing: 6
                        clip: true
                        model: App.actors

                        delegate: Rectangle {
                            id: saved

                            required property string actorId
                            required property string name
                            required property string portraitPath
                            required property var actor

                            readonly property bool current:
                                root.actor.id !== undefined && root.actor.id === saved.actorId

                            width: 56
                            height: 76
                            radius: Theme.radiusSmall
                            color: Theme.background
                            border.width: saved.current ? 2 : 1
                            border.color: saved.current ? Theme.accent
                                        : savedHover.hovered ? Theme.borderStrong
                                        : Theme.border
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: saved.current ? 2 : 1
                                source: saved.portraitPath !== ""
                                        ? App.toFileUrl(saved.portraitPath) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }

                            IconButton {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 1
                                icon: "close-line"
                                destructive: true
                                visible: savedHover.hovered
                                onClicked: App.actors.remove(saved.actorId)
                            }

                            HoverHandler {
                                id: savedHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: root.project.applyActor(saved.actor)
                            }
                        }
                    }
                }

                // ------------------------------------------------ casting
                PromptBar {
                    id: briefBar

                    placeholder: qsTr("Describe the person. Ordinary face, ordinary room.")
                    minHeight: 56
                    busy: App.casting.running
                    submitIcon: "magic-line"
                    onSubmitted: function (text) {
                        root.project.setActorField("brief", text);
                        App.casting.generate(root.project.actor, 4);
                    }
                    onTextChanged: root.project.setActorField("brief", text)

                    ChoiceChip {
                        id: gender
                        label: qsTr("Gender")
                        options: [
                            { label: qsTr("a woman"), value: "a woman" },
                            { label: qsTr("a man"), value: "a man" },
                            { label: qsTr("a non-binary person"), value: "a non-binary person" }
                        ]
                        onPicked: function (v) { root.setTrait("gender", v); }
                    }

                    ChoiceChip {
                        id: age
                        label: qsTr("Age")
                        options: [
                            { label: qsTr("early twenties"), value: "around 22 years old" },
                            { label: qsTr("late twenties"), value: "around 27 years old" },
                            { label: qsTr("thirties"), value: "around 35 years old" },
                            { label: qsTr("forties"), value: "around 45 years old" },
                            { label: qsTr("fifties or older"), value: "around 58 years old" }
                        ]
                        onPicked: function (v) { root.setTrait("age", v); }
                    }

                    ChoiceChip {
                        id: dress
                        label: qsTr("Dress")
                        options: [
                            { label: qsTr("casual"), value: "dressed casually in a plain t-shirt" },
                            { label: qsTr("sportswear"), value: "in sportswear" },
                            { label: qsTr("office"), value: "in office clothes" },
                            { label: qsTr("streetwear"), value: "in streetwear" }
                        ]
                        onPicked: function (v) { root.setTrait("style", v); }
                    }

                    ChoiceChip {
                        id: energy
                        label: qsTr("Energy")
                        options: [
                            { label: qsTr("calm"), value: "calm, low energy" },
                            { label: qsTr("upbeat"), value: "upbeat and animated" },
                            { label: qsTr("just woke up"), value: "tired, just woke up" },
                            { label: qsTr("warm"), value: "warm and friendly" }
                        ]
                        onPicked: function (v) { root.setTrait("energy", v); }
                    }

                    Chip {
                        label: qsTr("Reference")
                        //: %1 is a count of photos
                        value: root.references.length > 0
                               ? qsTr("%1 photo(s)").arg(root.references.length) : ""
                        icon: root.references.length === 0 ? "image-add-line" : "image-line"
                        onClicked: referenceDialog.open()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: App.casting.running
                              //: %1 and %2 are counts of portraits
                              ? qsTr("Casting... %1 of %2")
                                    .arg(App.casting.received).arg(App.casting.requested)
                              : root.castCost.known
                                //: %1 is a price
                                ? qsTr("Four faces for %1")
                                      .arg(Format.estimated(root.castCost.amount))
                                : qsTr("price unknown")
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: qsTr("Cancel")
                        visible: App.casting.running
                        color: Theme.danger
                        font.pixelSize: Theme.fontSmall

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: App.casting.cancel()
                        }
                    }

                    Text {
                        text: qsTr("Use my photo")
                        visible: root.references.length > 0
                                 && root.portrait !== root.references[0]
                        color: Theme.accent
                        font.pixelSize: Theme.fontSmall

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: root.project.setActorField("portraitPath",
                                                                 root.references[0])
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: App.casting.error
                    visible: text !== ""
                    color: Theme.danger
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                }

                // ----------------------------------------------- candidates
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: App.casting.candidates.length > 0 || root.portrait !== ""

                    Repeater {
                        model: App.casting.candidates

                        Rectangle {
                            id: face

                            required property var modelData

                            readonly property bool chosen: root.portrait === face.modelData.path

                            width: 84
                            height: 112
                            radius: Theme.radiusSmall
                            color: Theme.background
                            border.width: face.chosen ? 2 : 1
                            border.color: face.chosen ? Theme.accent
                                        : faceHover.hovered ? Theme.borderStrong
                                        : Theme.border
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: face.chosen ? 2 : 1
                                source: App.toFileUrl(face.modelData.path)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                mipmap: true
                            }

                            HoverHandler {
                                id: faceHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: root.project.setActorField("portraitPath",
                                                                     face.modelData.path)
                            }
                        }
                    }

                    // The kept portrait stays visible after a batch is replaced.
                    Rectangle {
                        width: 84
                        height: 112
                        radius: Theme.radiusSmall
                        color: Theme.background
                        border.width: 2
                        border.color: Theme.accent
                        clip: true
                        visible: root.portrait !== ""
                                 && App.casting.candidates.length === 0

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: App.toFileUrl(root.portrait)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                        }
                    }
                }

                // ---------------------------------------------------- decor
                PromptBar {
                    id: decorBar

                    placeholder: qsTr("Where they are. A small bathroom, towels on the floor…")
                    minHeight: 40
                    submitIcon: "check-line"
                    onSubmitted: function (text) { root.project.setActorField("decor", text); }
                    onTextChanged: root.project.setActorField("decor", text)
                }

                // ---------------------------------------------------- voice
                PromptBar {
                    id: auditionBar

                    placeholder: qsTr("A line to hear them say…")
                    minHeight: 40
                    busy: App.voiceBooth.auditioning
                    submitIcon: "play-fill"
                    text: root.auditionLine
                    onSubmitted: function (text) {
                        root.auditionLine = text;
                        App.voiceBooth.audition(root.project.actor, text);
                    }
                    onTextChanged: {
                        root.auditionLine = text;
                        root.auditionCost = App.voiceBooth.estimate(text);
                    }

                    Chip {
                        id: voiceChip
                        label: qsTr("Voice")
                        value: voiceBox.value !== "" ? voiceBox.label : ""
                        icon: "mic-line"
                        opensMenu: true
                        onClicked: voiceMenu.open()
                    }

                    Chip {
                        label: qsTr("Load voices")
                        icon: "refresh-line"
                        onClicked: App.loadVoices(App.settings.pref("voiceProvider", "elevenlabs"))
                    }
                }

                // Four presets instead of four sliders: nobody sets
                // similarity_boost by hand before they have heard anything.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { label: qsTr("Natural"),  s: 0.35, m: 0.80, y: 0.45 },
                            { label: qsTr("Composed"), s: 0.65, m: 0.85, y: 0.20 },
                            { label: qsTr("Lively"),   s: 0.25, m: 0.75, y: 0.60 },
                            { label: qsTr("Intense"),  s: 0.15, m: 0.70, y: 0.80 }
                        ]

                        Chip {
                            id: preset
                            required property var modelData

                            label: preset.modelData.label
                            active: Math.abs(root.setting("voiceStability", 0.45)
                                             - preset.modelData.s) < 0.01
                                    && Math.abs(root.setting("voiceStyle", 0.35)
                                                - preset.modelData.y) < 0.01
                            onClicked: {
                                root.project.setActorField("voiceStability", preset.modelData.s);
                                root.project.setActorField("voiceSimilarity", preset.modelData.m);
                                root.project.setActorField("voiceStyle", preset.modelData.y);
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.auditionCost.known
                              ? Format.estimated(root.auditionCost.amount)
                              : ""
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.fineTuning ? qsTr("Hide the sliders")
                                              : qsTr("Fine-tune")
                        color: Theme.accent
                        font.pixelSize: Theme.fontSmall

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: root.fineTuning = !root.fineTuning
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.fineTuning

                    LabeledSlider {
                        label: qsTr("Stability")
                        value: root.setting("voiceStability", 0.45)
                        onEdited: function (v) { root.project.setActorField("voiceStability", v); }
                    }

                    LabeledSlider {
                        label: qsTr("Similarity")
                        value: root.setting("voiceSimilarity", 0.8)
                        onEdited: function (v) { root.project.setActorField("voiceSimilarity", v); }
                    }

                    LabeledSlider {
                        label: qsTr("Style")
                        value: root.setting("voiceStyle", 0.35)
                        onEdited: function (v) { root.project.setActorField("voiceStyle", v); }
                    }

                    LabeledSlider {
                        label: qsTr("Speed")
                        from: 0.7
                        to: 1.2
                        value: root.setting("voiceSpeed", 1.0)
                        onEdited: function (v) { root.project.setActorField("voiceSpeed", v); }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: App.voiceBooth.error
                    visible: text !== ""
                    color: Theme.danger
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WordWrap
                }

                Item { implicitHeight: 4 }
            }
        }

        // ------------------------------------------------------------ keep
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.portrait !== ""

            Text {
                Layout.fillWidth: true
                text: root.actor.name !== undefined && root.actor.name !== ""
                      ? root.actor.name : App.actors.suggestedName()
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                elide: Text.ElideRight
            }

            PrimaryButton {
                text: root.actor.id !== undefined && root.actor.id !== ""
                      ? qsTr("Update") : qsTr("Keep this actor")
                onClicked: {
                    const id = App.actors.save(root.project.actor);
                    const kept = App.actors.actor(id);
                    root.project.setActorField("id", id);
                    root.project.setActorField("name", kept.name);
                    if (kept.portraitPath !== undefined)
                        root.project.setActorField("portraitPath", kept.portraitPath);
                }
            }
        }
    }

    Menu {
        id: voiceMenu

        implicitWidth: 240

        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        Repeater {
            model: voiceBox.options

            MenuItem {
                id: voiceItem
                required property var modelData

                implicitHeight: 30

                contentItem: Text {
                    text: voiceItem.modelData.label
                    color: voiceItem.modelData.value === voiceBox.value ? Theme.accent : Theme.text
                    font.pixelSize: Theme.fontSmall
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                    elide: Text.ElideRight
                }

                background: Rectangle {
                    color: voiceItem.hovered ? Theme.surfaceAlt : "transparent"
                }

                onTriggered: {
                    voiceBox.setValue(voiceItem.modelData.value);
                    root.project.setActorField("voiceId", voiceItem.modelData.value);
                }
            }
        }
    }

    // Holds the loaded voice list and the current pick. Not visible: the chip is
    // the control, this is only where its options live.
    QtObject {
        id: voiceBox

        property var options: []
        property string value: ""
        property string label: ""

        function setValue(v) {
            value = v === undefined ? "" : v;
            label = "";
            for (let i = 0; i < options.length; ++i) {
                if (options[i].value === value) {
                    label = options[i].label;
                    return;
                }
            }
            if (value !== "")
                label = value;
        }
    }

    MediaPlayer {
        id: player
        source: App.voiceBooth.samplePath !== ""
                ? App.toFileUrl(App.voiceBooth.samplePath) : ""
        audioOutput: AudioOutput {}
    }

    FileDialog {
        id: referenceDialog
        title: qsTr("Choose reference photos")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp)")]
        onAccepted: root.project.addImages("actor", selectedFiles)
    }

    Connections {
        target: App.voiceBooth
        function onSamplePathChanged() {
            if (App.voiceBooth.samplePath !== "")
                player.play();
        }
    }

    Connections {
        target: App

        function onVoicesLoaded(providerId, voices) {
            const current = voiceBox.value;
            voiceBox.options = voices.map(function (v) {
                return {
                    label: v.description ? v.label + " — " + v.description : v.label,
                    value: v.id
                };
            });
            voiceBox.setValue(current);
        }

        function onVoicesFailed(providerId, error) {
            App.log.append(3, qsTr("Could not load voices: %1").arg(error));
        }
    }

    Connections {
        target: App.project
        function onCleared() { root.resync(); }
        function onActorReset() { root.resync(); }
    }
}
