import QtQuick

import ForkTheme 1.0
import QtQuick.Templates as T

// [fork] A segmented control: one choice among a few. options is a list of { value, label }
// (and optionally enabled: false); value is the chosen one, compared with ===. It emits
// activated(value) and leaves value to the caller's binding:
//
//   ForkSegmented {
//       options: [{ value: 30, label: "30" }, { value: 60, label: "60" }]
//       value: StreamingPreferences.fps
//       onActivated: (v) => StreamingPreferences.fps = v
//   }
//
// mono sets the labels in SF Mono, for numbers.
Rectangle {
    id: seg

    property var options: []
    property var value
    property bool mono: false
    property string accessibleName: ""

    signal activated(var value)

    implicitWidth: row.implicitWidth + 10
    implicitHeight: 50
    radius: 14
    color: ForkTheme.seg
    border.color: ForkTheme.lineSoft
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.Grouping
    Accessible.name: accessibleName

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: seg.options

            delegate: T.Button {
                id: segment
                required property var modelData

                readonly property bool selected: modelData.value === seg.value

                implicitHeight: 40
                implicitWidth: Math.max(seg.mono ? 56 : 0, label.implicitWidth + 28)
                enabled: modelData.enabled !== false
                hoverEnabled: true
                focusPolicy: Qt.TabFocus

                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: selected
                Accessible.name: modelData.label

                onClicked: seg.activated(modelData.value)

                contentItem: Text {
                    id: label
                    text: segment.modelData.label
                    textFormat: Text.PlainText
                    font.family: seg.mono ? ForkTheme.monoFamily : ForkTheme.uiFamily
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: segment.selected || segment.hovered ? ForkTheme.text : ForkTheme.muted
                    opacity: segment.enabled ? 1 : 0.5
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Item {
                    // The selected segment's small shadow, 1 pt below it
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 1
                        anchors.bottomMargin: -1
                        visible: segment.selected
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.16)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: segment.selected ? ForkTheme.segOn : "transparent"
                        border.width: segment.visualFocus ? 2 : 0
                        border.color: ForkTheme.selEdge
                    }
                }
            }
        }
    }
}
