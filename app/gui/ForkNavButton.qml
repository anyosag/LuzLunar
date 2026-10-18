import QtQuick

import ForkTheme 1.0
import QtQuick.Templates as T

// [fork] A section in the Settings sidebar: an SF Symbol and a name; current fills it
T.Button {
    id: control

    property string symbol: ""
    property bool current: false

    implicitHeight: ForkTheme.controlHeight
    implicitWidth: 220
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.selected: current

    contentItem: Row {
        spacing: 12

        // The symbol takes the text's color, like the design's line icons
        ForkSymbol {
            anchors.verticalCenter: parent.verticalCenter
            symbol: control.symbol
            size: 18
            color: control.current || control.hovered ? ForkTheme.text : ForkTheme.muted
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 30
            text: control.text
            textFormat: Text.PlainText
            font.family: ForkTheme.uiFamily
            font.pixelSize: 14
            font.weight: Font.Medium
            color: control.current || control.hovered ? ForkTheme.text : ForkTheme.muted
            elide: Text.ElideRight
        }
    }

    background: Rectangle {
        radius: ForkTheme.radiusControl
        color: control.current ? ForkTheme.sel : (control.hovered ? ForkTheme.surface : "transparent")

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            visible: control.visualFocus
            radius: ForkTheme.radiusControl + 4
            color: "transparent"
            border.width: 2
            border.color: ForkTheme.selEdge
        }
    }
}
