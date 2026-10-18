import QtQuick

import ForkTheme 1.0

// [fork] A LuzLunar shortcut drawn as keycaps: Control, Option, Shift and key ("Q" shows ⌃⌥⇧Q).
// keys replaces the whole list, for anything else.
Row {
    id: keyRow

    property string key: "Q"
    property var keys: ["⌃", "⌥", "⇧", key]

    spacing: 4
    Accessible.ignored: true

    Repeater {
        model: keyRow.keys

        delegate: Rectangle {
            required property string modelData

            width: Math.max(24, keyLabel.implicitWidth + 10)
            height: 24
            radius: 6
            // The key's edge, which shows as a 2 pt rim along its bottom
            color: ForkTheme.lineStrong

            Rectangle {
                width: parent.width
                height: parent.height - 2
                topLeftRadius: 6
                topRightRadius: 6
                bottomLeftRadius: 4
                bottomRightRadius: 4
                color: ForkTheme.tile
            }

            Text {
                id: keyLabel
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: parent.modelData
                textFormat: Text.PlainText
                font.family: ForkTheme.uiFamily
                font.pixelSize: 12
                color: ForkTheme.text
            }
        }
    }
}
