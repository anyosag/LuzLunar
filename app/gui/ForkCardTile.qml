import QtQuick
import QtQuick.Effects
import ForkTheme 1.0

// [fork] An app tile of the big card: a 3:4 cover with a rounded corner, or the "All apps" collage
// of three fanned covers. The running tile has a blue ring and a breathing glow and a Running badge;
// an asleep PC's tiles are dimmed and carry a badge. `ph` is the shared tick's phase (0 or 1).
Item {
    id: tile

    property string name: ""
    property url cover: ""
    property bool collage: false
    // Three covers for the collage, top (center) one first: [top, left, right]
    property var fan: []
    property string allNote: ""
    property bool running: false
    property bool sleepy: false
    property string badge: "moon"          // moon | power
    property color sky: "#17163F"
    property int ph: 0
    property string accessibleName: name
    property bool interactive: true

    readonly property bool hovered: hover.hovered && interactive

    signal clicked()

    implicitWidth: 119
    implicitHeight: width * 4 / 3
    height: implicitHeight

    readonly property bool dark: ForkTheme.dark

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: tile.clicked()

    Item {
        id: lift
        anchors.fill: parent
        y: 0
        transform: Translate { y: tile.hovered ? -4 : 0; Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } } }
        scale: tile.hovered ? 1.03 : 1
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }

        // Drop shadows: resting, and lifted while pointed at
        RectangularShadow {
            anchors.fill: face
            offset.y: 8
            blur: 18
            radius: 12
            color: tile.dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.14)
            opacity: tile.hovered ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 260 } }
        }
        RectangularShadow {
            anchors.fill: face
            offset.y: 14
            blur: 28
            radius: 12
            color: tile.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.22)
            opacity: tile.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260 } }
        }

        // The running tile's breathing glow and 2 px ring
        RectangularShadow {
            anchors.fill: face
            visible: tile.running
            radius: 12
            blur: tile.ph ? 26 : 12
            color: Qt.rgba(64 / 255, 156 / 255, 1, tile.ph ? 0.55 : 0.28)
            Behavior on blur { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
            Behavior on color { ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
        }
        Rectangle {
            visible: tile.running
            x: -2; y: -2; width: parent.width + 4; height: parent.height + 4
            radius: 14
            color: "transparent"
            border.width: 2
            border.color: "#409CFF"
        }

        ForkCardClip {
            id: face
            anchors.fill: parent
            radius: 12
            background: tile.sky
            dim: tile.sleepy && !tile.hovered ? 1 : 0
            Behavior on dim { NumberAnimation { duration: 260 } }

            // The hairline, under the art: it only shows on the collage
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
            }

            Image {
                visible: !tile.collage
                anchors.fill: parent
                source: tile.collage ? "" : tile.cover
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
            }

            // The collage: three covers fanned from their bottom centers, wider when pointed at
            Repeater {
                model: tile.collage ? 3 : 0
                delegate: Item {
                    id: fc
                    required property int index
                    // bottom (left), middle (right), top (center)
                    readonly property var spec: [[-26, -14, 1], [26, 14, 2], [0, 0, 0]][index]
                    readonly property real k: tile.hovered ? 1.3 : 1
                    property real kk: k
                    Behavior on kk { NumberAnimation { duration: 320; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
                    x: (tile.width - 52) / 2
                    y: 20
                    width: 52
                    height: 69
                    transform: [
                        Rotation { origin.x: 26; origin.y: 69; angle: fc.spec[1] * fc.kk },
                        Translate { x: fc.spec[0] * fc.kk }
                    ]
                    RectangularShadow {
                        anchors.fill: parent
                        offset.y: 6; blur: 14; radius: 6
                        color: Qt.rgba(0, 0, 0, 0.45)
                    }
                    ForkCardClip {
                        anchors.fill: parent
                        radius: 6
                        Image {
                            anchors.fill: parent
                            source: tile.fan[fc.spec[2]] || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            mipmap: true
                        }
                    }
                }
            }
            Column {
                visible: tile.collage
                x: 10
                width: parent.width - 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                spacing: 1
                ForkCanvasText {
                    width: parent.width
                    text: "All apps"
                    color: "white"
                    elide: Text.ElideRight
                    px: 13; weight: 700
                    lineHeightPx: 17
                }
                ForkCanvasText {
                    width: parent.width
                    text: tile.allNote
                    color: "white"
                    opacity: 0.72
                    elide: Text.ElideRight
                    px: 11; weight: 400
                    lineHeightPx: 14
                }
            }

            // Running badge
            Rectangle {
                visible: tile.running
                x: 8; y: 8
                height: 20
                width: badgeRow.implicitWidth + 14
                radius: 10
                color: "#0A6CDB"
                Row {
                    id: badgeRow
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: "white"
                        opacity: tile.ph ? 0.35 : 1
                        Behavior on opacity { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
                    }
                    ForkCanvasText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Running"
                        color: "white"
                        px: 10.5; weight: 700
                    }
                }
            }

            // Sleepy badge: a moon (asleep) or a power glyph (off)
            Item {
                visible: tile.sleepy
                x: parent.width - 30; y: 8
                width: 22; height: 22
                RectangularShadow {
                    anchors.fill: parent
                    offset.y: 2; blur: 6; radius: 11
                    color: Qt.rgba(0, 0, 0, 0.35)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: tile.badge === "power" ? "#636366" : "#9B45D9"
                }
                ForkCardIcon {
                    anchors.centerIn: parent
                    path: tile.badge === "power" ? "M12 3.5v8M7.05 6.55a7 7 0 1 0 9.9 0" : "M15 4.2a7.8 7.8 0 1 0 4.8 13.1A6.6 6.6 0 0 1 15 4.2z"
                    size: tile.badge === "power" ? 12 : 12
                    color: "white"
                    filled: tile.badge !== "power"
                    stroked: tile.badge === "power"
                    strokeWidth: 2.2
                }
            }
        }
    }

    HoverHandler {
        id: hover
        enabled: tile.interactive
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: tile.interactive
        onTapped: tile.clicked()
    }
}
