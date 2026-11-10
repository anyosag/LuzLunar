import QtQuick
import QtQuick.Effects
import ForkTheme 1.0

// [fork] A button of a PC card. kind "primary" is the filled one in the PC's color (hue), "quiet" has
// the line and chip look, "icon" is the square ⋯ button. `big` picks the big card's sizes (44 px
// tall, radius 12) or the small card's (36 px, radius 10).
Item {
    id: btn

    property string kind: "quiet"          // primary | quiet | icon
    property bool big: true
    property string text: ""
    property string iconName: ""
    property bool iconFilled: false
    property color iconColor: ForkTheme.cv.text2
    property real iconStrokeWidth: big ? 1.8 : 1.9
    property var hue: ForkTheme.hue("indigo")
    // A primary-sized button drawn in the quiet look ("Set Up Wake…", "Test Network")
    property bool quietLook: false
    property bool glowWhenHovered: false
    property bool fillWidth: false
    property bool dimmed: false
    property alias hovered: hover.hovered
    property string accessibleName: text

    signal clicked()

    readonly property bool filledLook: kind === "primary" && !quietLook
    readonly property real iconSize: kind === "icon" ? (big ? 18 : 16) : (kind === "primary" ? (big ? 17 : 15) : (big ? 16 : 15))
    readonly property color ink: filledLook ? hue.onFill : (kind === "icon" ? ForkTheme.cv.text2 : ForkTheme.cv.text)

    implicitHeight: big ? 44 : 36
    implicitWidth: kind === "icon" ? implicitHeight
                                   : row.implicitWidth + (kind === "primary" && big ? 40 : (big ? 28 : 0))
    height: implicitHeight
    opacity: dimmed ? 0.6 : 1
    layer.enabled: dimmed

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: if (enabled) btn.clicked()

    RectangularShadow {
        anchors.fill: face
        visible: opacity > 0
        opacity: btn.glowWhenHovered && btn.filledLook ? 1 : 0
        offset.y: 8
        blur: 22
        radius: face.radius
        color: Qt.alpha(btn.hue.fill, 0.4)
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: btn.big ? 12 : 10
        color: btn.filledLook ? btn.hue.fill : ForkTheme.cv.chip
        border.width: btn.filledLook ? 0 : 1
        border.color: ForkTheme.cv.line
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: btn.kind === "primary" ? (btn.big ? 8 : 7) : 7

        ForkPathIcon {
            visible: btn.iconName !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: btn.iconName
            size: btn.iconSize
            color: btn.kind === "quiet" || btn.kind === "icon" ? btn.iconColor : btn.ink
            filled: btn.iconFilled
            strokeWidth: btn.kind === "icon" ? 2.6 : (btn.kind === "primary" ? 1.9 : btn.iconStrokeWidth)
        }

        ForkCanvasText {
            visible: btn.kind !== "icon"
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.ink
            px: btn.kind === "primary" ? (btn.big ? 14.5 : 13) : (btn.big ? 13.5 : 13)
            weight: btn.kind === "primary" ? (btn.big ? 650 : 600) : (btn.big ? 500 : 600)
        }
    }

    HoverHandler {
        id: hover
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: btn.enabled
        onTapped: btn.clicked()
    }
}
