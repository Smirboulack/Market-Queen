import QtQuick
import QtQuick.Layouts
import MarketQueen

// What the next click on Generate is going to cost.
//
// The caller passes the same request map the pipeline receives, so the figures
// always describe the form as it stands. Everything is an estimate and says so:
// a model whose price we do not know is counted separately rather than folded
// into the total as zero.
Rectangle {
    id: root

    property var request: ({})

    readonly property var breakdown: App.pricing.estimate(request)
    readonly property var lines: breakdown.lines !== undefined ? breakdown.lines : []
    readonly property int unknownCount: breakdown.unknownCount !== undefined
                                        ? breakdown.unknownCount : 0

    // "2026-08-08" in the catalogue, in the reader's own date format.
    readonly property string checkedOn: {
        const raw = App.pricing.updated;
        if (raw === "")
            return "";
        const date = new Date(raw);
        return isNaN(date.getTime())
            ? raw : date.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 24
    radius: Theme.radius
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: qsTr("Estimated cost")
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            Text {
                //: %1 is a date like "8 Aug 2026"
                text: qsTr("prices %1").arg(root.checkedOn)
                visible: root.checkedOn !== ""
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall
            }
        }

        Repeater {
            model: root.lines

            RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: Format.stepLabel(modelData.step)
                    color: Theme.textDim
                    font.pixelSize: Theme.fontSmall
                }

                Text {
                    text: Format.unitsLabel(modelData.units, modelData.unit)
                    visible: text !== ""
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: modelData.known ? Format.estimated(modelData.amount) : qsTr("?")
                    color: modelData.known ? Theme.text : Theme.textFaint
                    font.pixelSize: Theme.fontSmall
                    font.family: "monospace"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: 1
            color: Theme.border
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: qsTr("Total")
                color: Theme.text
                font.pixelSize: Theme.fontSmall
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            Text {
                text: Format.estimated(root.breakdown.total)
                color: Theme.text
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
                font.family: "monospace"
            }
        }

        // Never silently under-report: if a model has no published price, the
        // total above is only part of the bill and has to say so.
        Text {
            Layout.fillWidth: true
            //: %1 is a count of models
            text: qsTr("+ %1 model(s) with no published price").arg(root.unknownCount)
            visible: root.unknownCount > 0
            color: Theme.warning
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("An estimate, not a bill. Each provider charges you directly.")
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            wrapMode: Text.WordWrap
        }
    }
}
