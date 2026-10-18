import QtQuick

import ForkTheme 1.0

// [fork] A setting that's on or off: its name, an optional explanation and tag, and a switch.
// Clicking anywhere on the row flips it. It emits toggled() with the new value and doesn't
// change checked itself, so bind checked to the setting:
//
//   ForkSwitchRow {
//       label: qsTr("V-Sync")
//       help: qsTr("Off lowers latency below a frame, but the picture can tear.")
//       checked: StreamingPreferences.enableVsync
//       onToggled: (on) => StreamingPreferences.enableVsync = on
//   }
//
// showDivider draws the line above the row; turn it off for the first row in a card.
Item {
    id: row

    property string label: ""
    property string help: ""
    property string tag: ""
    property bool checked: false
    property bool showDivider: true

    signal toggled(bool checked)

    width: parent ? parent.width : 400
    implicitHeight: Math.max(texts.implicitHeight, toggle.implicitHeight) + 24
    opacity: enabled ? 1 : 0.5

    function flip() {
        if (row.enabled) {
            row.toggled(!row.checked)
        }
    }

    Rectangle {
        visible: row.showDivider
        width: parent.width
        height: 1
        color: ForkTheme.lineSoft
    }

    TapHandler {
        onTapped: row.flip()
    }

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: toggle.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Row {
            width: parent.width
            spacing: 6

            ForkText {
                id: labelText
                kind: "label"
                text: row.label
                width: Math.min(implicitWidth, parent.width - (tagChip.visible ? tagChip.width + parent.spacing : 0))
                elide: Text.ElideRight
            }

            Rectangle {
                id: tagChip
                visible: row.tag !== ""
                anchors.verticalCenter: labelText.verticalCenter
                width: tagText.implicitWidth + 14
                height: 19
                radius: 6
                color: ForkTheme.warnBg
                border.color: ForkTheme.warnLine

                ForkText {
                    id: tagText
                    anchors.centerIn: parent
                    text: row.tag
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: ForkTheme.warnText
                }
            }
        }

        ForkText {
            width: parent.width
            visible: row.help !== ""
            kind: "help"
            font.pixelSize: 13
            text: row.help
        }
    }

    ForkSwitch {
        id: toggle
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: row.checked
        enabled: row.enabled
        Accessible.name: row.label
        Accessible.description: row.help
        onClicked: row.flip()
    }
}
