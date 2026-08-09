import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import MarketQueen

// What the ad is made of, always visible, always current.
//
// This is what replaces "fill the form and hope": every step leaves something
// here, so the context of the previous steps never leaves the screen, and each
// block doubles as a way back to the step that produced it.
Rectangle {
    id: root

    readonly property var project: App.project

    Layout.preferredWidth: 320
    Layout.minimumWidth: 320
    Layout.maximumWidth: 320
    color: Theme.surface

    Rectangle {
        width: 1
        height: parent.height
        color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLarge
        spacing: Theme.gap

        Text {
            text: qsTr("YOUR AD")
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.gap

                // ------------------------------------------------- product
                RecapBlock {
                    title: qsTr("Product")
                    stepIndex: 0
                    filled: root.project.stepStates[0] !== undefined
                            && root.project.stepStates[0].valid
                    placeholder: qsTr("Not set yet")

                    Text {
                        Layout.fillWidth: true
                        text: root.project.product.name !== undefined
                              ? root.project.product.name : ""
                        color: Theme.text
                        font.pixelSize: Theme.fontBody
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.project.product.audience !== undefined
                              ? root.project.product.audience : ""
                        visible: text !== ""
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    // Reference images, as thumbnails: the point of collecting
                    // several is being able to see them all at a glance.
                    Flow {
                        Layout.fillWidth: true
                        spacing: 5
                        visible: repeater.count > 0

                        Repeater {
                            id: repeater
                            model: root.project.product.images !== undefined
                                   ? root.project.product.images : []

                            Rectangle {
                                id: thumb

                                required property string modelData
                                required property int index

                                width: 44
                                height: 44
                                radius: Theme.radiusSmall
                                color: Theme.surfaceAlt
                                // The primary reference is outlined here too,
                                // so the two views never disagree about which
                                // picture the models will actually get.
                                border.width: thumb.index === 0 ? 2 : 1
                                border.color: thumb.index === 0 ? Theme.accent : Theme.border
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: thumb.index === 0 ? 2 : 1
                                    source: App.toFileUrl(thumb.modelData)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                }
                            }
                        }
                    }
                }

                // --------------------------------------------------- actor
                RecapBlock {
                    title: qsTr("Actor")
                    stepIndex: 1
                    filled: root.project.actor.portraitPath !== undefined
                            && root.project.actor.portraitPath !== ""
                    placeholder: qsTr("No one cast yet")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 64
                            radius: Theme.radiusSmall
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: Theme.border
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: root.project.actor.portraitPath !== undefined
                                        ? App.toFileUrl(root.project.actor.portraitPath) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.project.actor.name !== undefined
                                      && root.project.actor.name !== ""
                                      ? root.project.actor.name : qsTr("Not saved")
                                color: Theme.text
                                font.pixelSize: Theme.fontSmall
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.project.actor.brief !== undefined
                                      ? root.project.actor.brief : ""
                                color: Theme.textDim
                                font.pixelSize: Theme.fontSmall
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.project.actor.decor !== undefined
                              ? root.project.actor.decor : ""
                        visible: text !== ""
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                // -------------------------------------------------- script
                RecapBlock {
                    title: qsTr("Script")
                    stepIndex: 1
                    filled: root.project.scenes.count > 0
                    placeholder: qsTr("Nothing written yet")

                    Text {
                        Layout.fillWidth: true
                        //: %1 is a duration in seconds, e.g. "13.5 s"
                        text: qsTr("%1 s spoken").arg(root.project.spokenSeconds.toFixed(1))
                        color: Theme.text
                        font.pixelSize: Theme.fontBody
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.project.spokenScript()
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ------------------------------------------------------------ cost
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }

        EstimateCard {
            request: root.project.request
            visible: root.project.complete && !App.pipeline.running
                     && App.pipeline.outputFile === ""
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("The estimate appears once the three steps are filled in.")
            visible: !root.project.complete
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }
    }
}
