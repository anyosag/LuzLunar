// [fork] One control of the window header (sky-chrome.md §5.5 to §5.7, §5.10): an icon and/or a
// label on a rounded fill, with an optional 1 px border. Pills (Add PC, Your PCs), the capsule's
// round tools (Help, Settings) and the View-as segments are all this, set with different
// geometry. Keyboard focus shows a gold ring (the canvas defines none; the app's focus colour).
import QtQuick
import QtQuick.Controls

import ForkTheme 1.0

AbstractButton {
    id: root

    property string iconName: ""
    property real iconSize: 16
    property real iconStroke: -1
    property color iconColor: ForkTheme.cv.text
    property color textColor: ForkTheme.cv.text
    property real fontSize: 13
    property int fontWeight: Font.Medium
    property real radius: 15
    property color fillColor: "transparent"
    property color borderColor: "transparent"
    property real borderWidth: 1
    property real leftPad: 0
    property real rightPad: 0
    property real gap: 6
    // A soft 1 px drop under a selected light segment
    property bool lift: false
    property real contentWidth: -1
    property real contentHeight: 30

    readonly property bool hasLabel: text !== ""

    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true
    hoverEnabled: true
    implicitHeight: contentHeight
    implicitWidth: contentWidth >= 0 ? contentWidth
                                     : leftPad + rightPad + (iconName !== "" ? iconSize : 0)
                                       + (hasLabel ? labelText.implicitWidth + (iconName !== "" ? gap : 0) : 0)
    height: implicitHeight
    width: implicitWidth

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.checkable: checkable
    Accessible.checked: checked
    Accessible.onPressAction: root.clicked()

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
    Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
    Keys.onLeftPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)

    background: Item {
        Rectangle {
            visible: root.lift
            y: 1
            width: parent.width
            height: parent.height
            radius: root.radius
            color: Qt.rgba(0, 0, 0, 0.12)
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: root.fillColor
            border.width: root.borderWidth
            border.color: root.borderColor
        }

        // Hover and press, as a veil on the fill (the canvas has none)
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: ForkTheme.dark ? "#FFFFFF" : "#000000"
            opacity: root.down ? 0.10 : (root.hovered ? 0.05 : 0)
        }

        Rectangle {
            visible: root.visualFocus
            anchors.fill: parent
            anchors.margins: -2
            radius: root.radius + 2
            color: "transparent"
            border.width: 2
            border.color: ForkTheme.cv.gold
        }
    }

    contentItem: Item {
        ForkPathIcon {
            visible: root.iconName !== ""
            x: root.contentWidth >= 0 && !root.hasLabel ? (parent.width - root.iconSize) / 2 : root.leftPad
            y: (parent.height - root.iconSize) / 2
            name: root.iconName
            size: root.iconSize
            color: root.iconColor
            strokeWidth: root.iconStroke
        }

        Text {
            id: labelText
            visible: root.hasLabel
            x: root.leftPad + (root.iconName !== "" ? root.iconSize + root.gap : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.textColor
            font.family: ForkTheme.uiFamily
            font.pixelSize: root.fontSize
            font.weight: root.fontWeight
            textFormat: Text.PlainText
        }
    }
}
