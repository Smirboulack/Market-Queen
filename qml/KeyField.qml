import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import SuperInfinity

// One API key: hidden by default, saved on edit, never leaves the machine.
Rectangle {
    id: root

    required property var credential

    // Plain properties refreshed by hand: the store is not a bindable source.
    property bool fromEnvironment: false
    property bool hasKey: false

    function refreshState() {
        fromEnvironment = App.settings.apiKeyFromEnvironment(credential.id);
        hasKey = App.settings.hasApiKey(credential.id);
    }

    Component.onCompleted: refreshState()

    Connections {
        target: App.settings
        function onApiKeysChanged() { root.refreshState(); }
    }

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + 28
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 4
                color: root.hasKey ? Theme.success : Theme.borderStrong
            }

            Text {
                text: root.credential.label
                color: Theme.text
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }

            Text {
                text: root.credential.note
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            GhostButton {
                text: qsTr("Get a key")
                onClicked: App.openExternal(root.credential.signupUrl)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: field

                Layout.fillWidth: true
                implicitHeight: Theme.fieldHeight
                echoMode: reveal.checked ? TextInput.Normal : TextInput.Password
                placeholderText: root.fromEnvironment
                                 ? qsTr("Using %1 from your environment").arg(root.credential.envVar)
                                 : qsTr("Paste your key")
                color: Theme.text
                placeholderTextColor: Theme.textFaint
                font.pixelSize: Theme.fontBody
                leftPadding: 10
                rightPadding: 10
                selectByMouse: true
                selectionColor: Theme.accent

                Component.onCompleted: text = App.settings.apiKey(root.credential.id)

                onEditingFinished: {
                    App.settings.setApiKey(root.credential.id, text);
                    root.refreshState();
                    saved.show();
                }

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.background
                    border.width: 1
                    border.color: field.activeFocus ? Theme.accent : Theme.border
                }
            }

            GhostButton {
                id: reveal
                checkable: true
                text: checked ? qsTr("Hide") : qsTr("Show")
            }
        }

        Text {
            id: saved
            text: qsTr("Saved.")
            color: Theme.success
            font.pixelSize: Theme.fontSmall
            opacity: 0

            function show() {
                fade.restart();
            }

            SequentialAnimation {
                id: fade
                NumberAnimation { target: saved; property: "opacity"; to: 1; duration: 120 }
                PauseAnimation { duration: 1400 }
                NumberAnimation { target: saved; property: "opacity"; to: 0; duration: 400 }
            }
        }
    }
}
