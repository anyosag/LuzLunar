import QtQuick

import ForkTheme 1.0

// [fork] One of the All apps band's buttons (Resume, Quit, Wake PC) and the dialog's: a label with
// an optional icon on a fill, with the design's measures. Keyboard focus draws a ring; the design
// has no hover or press look.
FocusScope {
    id: button

    property string text: ""
    property string iconName: ""
    property real iconSize: 15
    property int iconFilled: -1
    property int iconStroked: -1
    property real iconStrokeWidth: 0
    property color fill: "transparent"
    property color ink: "#FFFFFF"
    property color borderColor: "transparent"
    property real borderWidth: 0
    property real radius: 11
    property real fontSize: 13.5
    property int fontWeight: 650
    property real padLeft: 13
    property real padRight: 16
    property real gap: 7
    property alias fullWidth: button.stretch
    property bool stretch: false
    signal clicked()

    implicitHeight: 40
    implicitWidth: padLeft + (iconName !== "" ? iconSize + gap : 0) + label.implicitWidth + padRight
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: button.clicked()

    Rectangle {
        anchors.fill: parent
        radius: button.radius
        color: button.fill
        border.width: button.borderWidth
        border.color: button.borderColor
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: button.stretch ? (button.width - width) / 2 : button.padLeft
        spacing: button.gap

        ForkLibraryIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.iconName !== ""
            name: button.iconName
            size: button.iconSize
            color: button.ink
            filled: button.iconFilled
            stroked: button.iconStroked
            strokeWidth: button.iconStrokeWidth
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.ink
            font.family: ForkTheme.uiFamily
            font.pixelSize: button.fontSize
            font.weight: button.fontWeight
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: button.radius + 3
        color: "transparent"
        border.width: 2
        border.color: ForkTheme.cv.menuHi
        visible: button.visualFocus
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()
}
