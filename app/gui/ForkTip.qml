import QtQuick

import ForkTheme 1.0

// [fork] A hint in a quiet box: keycaps (key, or keys for another combination), an SF Symbol or a
// short gold lead-in like "e.g.", then a sentence. With none of them it's just the sentence.
Rectangle {
    id: tip

    property string text: ""
    property string key: ""
    property var keys: []
    property string symbol: ""
    property color symbolColor: ForkTheme.muted
    // A short word before the sentence, in gold mono ("e.g.")
    property string lead: ""

    // 12 above and below, 14 at the sides
    implicitWidth: row.implicitWidth + 28
    implicitHeight: Math.max(row.implicitHeight, 24) + 24
    radius: ForkTheme.radiusTile
    color: ForkTheme.bar
    border.color: ForkTheme.lineSoft

    Accessible.role: Accessible.StaticText
    Accessible.name: text

    Row {
        id: row
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 28
        spacing: 12

        ForkKeys {
            id: caps
            visible: tip.key !== "" || tip.keys.length > 0
            anchors.verticalCenter: parent.verticalCenter
            key: tip.key
            keys: tip.keys.length > 0 ? tip.keys : ["⌃", "⌥", "⇧", tip.key]
        }

        ForkSymbol {
            id: icon
            visible: tip.symbol !== "" && !caps.visible
            anchors.verticalCenter: parent.verticalCenter
            symbol: tip.symbol
            color: tip.symbolColor
        }

        ForkText {
            id: leadText
            visible: tip.lead !== "" && !caps.visible && !icon.visible
            anchors.verticalCenter: parent.verticalCenter
            kind: "mono"
            color: ForkTheme.accentInk
            text: tip.lead
        }

        ForkText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (caps.visible ? caps.width + parent.spacing : 0) - (icon.visible ? icon.width + parent.spacing : 0)
                   - (leadText.visible ? leadText.width + parent.spacing : 0)
            kind: "body"
            color: ForkTheme.text2
            text: tip.text
        }
    }
}
