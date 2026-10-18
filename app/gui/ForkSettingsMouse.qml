import QtQuick
import QtQuick.Shapes

import ForkTheme 1.0
import StreamingPreferences 1.0

// [fork] Settings › Mouse & trackpad: whether the stream holds the pointer (games) or lets it
// cross in and out like any window (remote desktop), and the mouse button and scrolling options.
// Upstream's "Use touchscreen as a virtual trackpad" (absoluteTouchMode) is left out on purpose:
// Macs have no touchscreen, so the setting could never do anything here.
Column {
    id: mouseSection

    spacing: ForkTheme.gap

    // ---- Pointer --------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Pointer")

        Flow {
            id: pointerFlow
            width: parent.width
            spacing: 10

            // Cards at least 260 wide: with two of them in a wide card, they sit at the left as wide as a
            // third would be
            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (260 + spacing)))
            readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

            Repeater {
                model: [
                    { "absolute": false, "title": qsTr("Games"),
                      "subtitle": qsTr("Holds the pointer inside the stream, so games can turn the camera as you move.") },
                    { "absolute": true, "title": qsTr("Remote desktop"),
                      "subtitle": qsTr("The pointer moves in and out of the stream like any window. Most games won't work this way.") }
                ]

                delegate: ForkOptionCard {
                    id: pointerCard
                    required property var modelData

                    // The color of what the picture is about: the held crosshair, or the pointer on its way
                    readonly property color mark: selected ? ForkTheme.selEdge : ForkTheme.faint

                    width: pointerFlow.cardWidth
                    title: modelData.title
                    subtitle: modelData.subtitle
                    selected: StreamingPreferences.absoluteMouseMode === modelData.absolute
                    onClicked: StreamingPreferences.absoluteMouseMode = modelData.absolute

                    // A screen as wide as the card, with the 240x120 picture in the middle of it
                    Rectangle {
                        id: screen
                        width: pointerCard.width - pointerCard.leftPadding - pointerCard.rightPadding
                        height: 120
                        radius: 10
                        color: ForkTheme.bg
                        border.color: ForkTheme.lineSoft
                        Accessible.ignored: true

                        Item {
                            anchors.centerIn: parent
                            width: 240
                            height: 120

                            // Games: a window with a crosshair in it, and a chip that says the pointer is held
                            Item {
                                visible: !pointerCard.modelData.absolute
                                anchors.fill: parent

                                Rectangle {
                                    x: 40
                                    y: 16
                                    width: 160
                                    height: 88
                                    radius: 8
                                    color: ForkTheme.tile
                                    border.color: ForkTheme.lineStrong
                                }

                                // The crosshair, centered at 120, 60
                                Rectangle {
                                    x: 105
                                    y: 45
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: "transparent"
                                    border.width: 2
                                    border.color: pointerCard.mark
                                }

                                Repeater {
                                    // The four ticks: left, top, width, height
                                    model: [[119, 38, 2, 10], [119, 72, 2, 10], [98, 59, 10, 2], [132, 59, 10, 2]]

                                    delegate: Rectangle {
                                        required property var modelData

                                        x: modelData[0]
                                        y: modelData[1]
                                        width: modelData[2]
                                        height: modelData[3]
                                        radius: 1
                                        color: pointerCard.mark
                                    }
                                }

                                Rectangle {
                                    x: 190 - width
                                    y: 24
                                    width: heldRow.implicitWidth + 16
                                    height: 20
                                    radius: 10
                                    color: ForkTheme.bg

                                    Row {
                                        id: heldRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        ForkSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            symbol: "lock.fill"
                                            size: 10
                                            color: ForkTheme.text2
                                        }

                                        ForkText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            font.pixelSize: 9
                                            color: ForkTheme.text2
                                            text: qsTr("held")
                                        }
                                    }
                                }
                            }

                            // Remote desktop: a big window and a small one, and the pointer crossing from one to the other
                            Item {
                                visible: pointerCard.modelData.absolute
                                anchors.fill: parent

                                Rectangle {
                                    x: 24
                                    y: 16
                                    width: 140
                                    height: 88
                                    radius: 8
                                    color: ForkTheme.tile
                                    border.color: ForkTheme.lineStrong
                                }

                                Rectangle {
                                    x: 176
                                    y: 40
                                    width: 48
                                    height: 52
                                    radius: 6
                                    color: ForkTheme.raised
                                    border.color: ForkTheme.lineStrong
                                }

                                Shape {
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer

                                    // Where the pointer is going
                                    ShapePath {
                                        strokeColor: pointerCard.mark
                                        strokeWidth: 1.6
                                        strokeStyle: ShapePath.DashLine
                                        dashPattern: [2, 2.5]
                                        capStyle: ShapePath.RoundCap
                                        fillColor: "transparent"
                                        startX: 120; startY: 56
                                        PathCubic { control1X: 140; control1Y: 50; control2X: 160; control2Y: 52; x: 186; y: 64 }
                                    }

                                    // The pointer, an arrow with a thin outline in the screen's color
                                    ShapePath {
                                        strokeColor: ForkTheme.bg
                                        strokeWidth: 1.2
                                        joinStyle: ShapePath.RoundJoin
                                        fillColor: pointerCard.mark
                                        startX: 186; startY: 58
                                        PathLine { x: 186; y: 80 }
                                        PathLine { x: 192; y: 74 }
                                        PathLine { x: 196; y: 83 }
                                        PathLine { x: 200; y: 81 }
                                        PathLine { x: 196; y: 72 }
                                        PathLine { x: 204; y: 72 }
                                        PathLine { x: 186; y: 58 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Flow {
            id: tipFlow
            width: parent.width
            spacing: 10

            readonly property int columns: width >= 2 * 300 + spacing ? 2 : 1
            readonly property real tipWidth: (width - (columns - 1) * spacing) / columns
            // Tips side by side share the taller one's height
            readonly property real tipHeight: Math.max(pointerTipZ.implicitHeight, pointerTipM.visible ? pointerTipM.implicitHeight : 0)

            ForkTip {
                id: pointerTipZ
                height: tipFlow.columns > 1 ? tipFlow.tipHeight : implicitHeight
                width: tipFlow.tipWidth
                key: "Z"
                text: qsTr("Control-Option-Shift-Z lets go of a held pointer")
            }

            ForkTip {
                id: pointerTipM
                height: tipFlow.columns > 1 ? tipFlow.tipHeight : implicitHeight
                width: tipFlow.tipWidth
                key: "M"
                text: qsTr("Control-Option-Shift-M switches between the two while streaming")
            }
        }
    }

    // ---- Buttons & scrolling --------------------------------------------------------------

    ForkCard {
        title: qsTr("Buttons & scrolling")
        // The title sits close above the rows, which draw their own padding, and the card is 8
        // shorter below them (the design's rows cards)
        spacing: 8
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Swap left and right mouse buttons")
                help: qsTr("For a left-handed mouse setup on the PC.")
                checked: StreamingPreferences.swapMouseButtons
                onToggled: (on) => StreamingPreferences.swapMouseButtons = on
            }

            ForkSwitchRow {
                label: qsTr("Reverse mouse scrolling direction")
                help: qsTr("Turn this on if scrolling on the PC feels backwards next to this Mac.")
                checked: StreamingPreferences.reverseScrollDirection
                onToggled: (on) => StreamingPreferences.reverseScrollDirection = on
            }
        }
    }
}
