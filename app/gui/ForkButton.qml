import QtQuick

import ForkTheme 1.0
import QtQuick.Templates as T

// [fork] A LuzLunar button. kind picks its look:
//   primary   gold fill, the main action of a card ("Show apps", "Resume")
//   strong    a fill in the text color ("Pair with this PC")
//   accent    a gold outline ("Wake PC")
//   default   a thin outline
//   quiet     no outline until hovered (toolbar-like and icon-only buttons)
//   danger    a red outline ("Remove")
//   link      gold text only, underlined on hover
// symbol is an optional SF Symbol before the text; with no text the button is square. Keyboard
// focus draws a gold ring just outside the button.
T.Button {
    id: control

    property string kind: "default"
    property string symbol: ""
    property real symbolSize: 16

    // The text and symbol color; set it to override the kind's (on box art, say)
    property color foreground: kind === "primary" ? ForkTheme.textOnAccent
                              : kind === "strong" ? ForkTheme.bg
                              : kind === "accent" || kind === "link" ? ForkTheme.accentInk
                              : kind === "danger" ? ForkTheme.danger
                              : kind === "quiet" && text === "" && !hovered ? ForkTheme.text2
                              : ForkTheme.text

    implicitHeight: kind === "link" ? 32 : ForkTheme.controlHeight
    implicitWidth: text === "" ? implicitHeight : Math.max(implicitContentWidth + leftPadding + rightPadding, implicitHeight)
    leftPadding: text === "" || kind === "link" ? 2 : 16
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    opacity: enabled ? 1 : 0.6

    font.family: ForkTheme.uiFamily
    font.pixelSize: kind === "link" ? 13 : 14
    font.weight: kind === "primary" || kind === "strong" || kind === "accent" ? Font.DemiBold : Font.Medium
    font.underline: kind === "link" && hovered

    Accessible.name: text !== "" ? text : (Accessible.description || symbol)

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8

            ForkSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.symbol !== ""
                symbol: control.symbol
                size: control.symbolSize
                color: control.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.text !== ""
                text: control.text
                textFormat: Text.PlainText
                font: control.font
                color: control.foreground
                elide: Text.ElideRight
            }
        }
    }

    background: Item {
        implicitHeight: control.implicitHeight

        Rectangle {
            anchors.fill: parent
            radius: ForkTheme.radiusControl
            color: {
                if (control.kind === "primary") {
                    return control.down ? Qt.darker(ForkTheme.accent, 1.06)
                                        : (control.hovered ? Qt.lighter(ForkTheme.accent, 1.06) : ForkTheme.accent)
                }
                if (control.kind === "strong") {
                    return control.down ? Qt.darker(ForkTheme.text, 1.12)
                                        : (control.hovered ? Qt.darker(ForkTheme.text, 1.06) : ForkTheme.text)
                }
                if (control.kind === "link") {
                    return "transparent"
                }
                return control.down ? ForkTheme.lineSoft : (control.hovered ? ForkTheme.raised : "transparent")
            }
            border.width: control.kind === "default" || control.kind === "accent" || control.kind === "danger" ? 1 : 0
            border.color: control.kind === "accent" ? ForkTheme.selEdge
                        : control.kind === "danger" ? ForkTheme.dangerLine
                        : ForkTheme.line
        }

        // The focus ring, 2 pt outside the button
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
