import QtQuick

import ForkTheme 1.0
import QtQuick.Templates as T

// [fork] A text field in the theme. invalid outlines it in red; mono sets it in SF Mono (for
// addresses and numbers). Keyboard focus draws a gold ring just outside it.
T.TextField {
    id: control

    property bool invalid: false
    property bool mono: false

    implicitWidth: 220
    implicitHeight: ForkTheme.controlHeight
    leftPadding: 12
    rightPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    font.family: mono ? ForkTheme.monoFamily : ForkTheme.uiFamily
    font.pixelSize: 14
    color: ForkTheme.text
    placeholderTextColor: ForkTheme.faint
    selectionColor: ForkTheme.accent
    selectedTextColor: ForkTheme.textOnAccent
    selectByMouse: true

    background: Rectangle {
        radius: ForkTheme.radiusControl
        color: ForkTheme.bar
        border.width: 1
        border.color: control.invalid ? ForkTheme.danger : ForkTheme.line

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            visible: control.activeFocus
            radius: ForkTheme.radiusControl + 4
            color: "transparent"
            border.width: 2
            border.color: control.invalid ? ForkTheme.danger : ForkTheme.selEdge
        }
    }

    // The placeholder, which Templates doesn't draw
    Text {
        x: control.leftPadding
        width: control.width - control.leftPadding - control.rightPadding
        height: control.height
        verticalAlignment: Text.AlignVCenter
        visible: control.text === "" && !control.preeditText
        text: control.placeholderText
        textFormat: Text.PlainText
        font: control.font
        color: control.placeholderTextColor
        elide: Text.ElideRight
    }
}
