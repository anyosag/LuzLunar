import QtQuick

import ForkTheme 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] Settings › Gamepads: the face button layout, how gamepads connect and behave, and where
// to read about mapping a gamepad that LuzLunar doesn't recognize. Upstream's own gamepad mapper
// isn't implemented in this fork, so it points to the Moonlight wiki instead.
Column {
    id: gamepadsSection

    spacing: ForkTheme.gap

    // ---- Button layout --------------------------------------------------------------------

    ForkCard {
        title: qsTr("Button layout")

        Flow {
            id: layoutFlow
            width: parent.width
            spacing: 10

            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (270 + spacing)))
            readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

            // The tallest card, so the cards are all as tall as it (their texts wrap differently)
            readonly property real tallest: {
                var most = 0
                for (var i = 0; i < layoutRepeater.count; i++) {
                    var item = layoutRepeater.itemAt(i)
                    if (item) {
                        most = Math.max(most, item.implicitHeight)
                    }
                }
                return most
            }

            Repeater {
                id: layoutRepeater
                // faces are the buttons at the top, right, bottom and left of the pad
                model: [
                    { "swap": false, "title": qsTr("Xbox layout"),
                      "subtitle": qsTr("A at the bottom, B on the right. What most PC games expect."),
                      "faces": ["Y", "B", "A", "X"] },
                    { "swap": true, "title": qsTr("Nintendo layout"),
                      "subtitle": qsTr("Swaps A with B and X with Y, so A sits on the right."),
                      "faces": ["X", "A", "B", "Y"] }
                ]

                delegate: ForkOptionCard {
                    id: layoutCard
                    required property var modelData

                    // Where each face button sits in the 104 pt pad, top left first
                    readonly property var spots: [Qt.point(36, 6), Qt.point(66, 36), Qt.point(36, 66), Qt.point(6, 36)]

                    width: layoutFlow.cardWidth
                    height: Math.max(implicitHeight, layoutFlow.tallest)
                    horizontal: true
                    // 16 around the pad, and 20 between it and the text
                    leftPadding: 16
                    topPadding: 16
                    title: modelData.title
                    subtitle: modelData.subtitle
                    selected: StreamingPreferences.swapFaceButtons === modelData.swap
                    onClicked: StreamingPreferences.swapFaceButtons = modelData.swap

                    // The pad with its four face buttons
                    Item {
                        width: 108
                        height: 104

                        Rectangle {
                            width: 104
                            height: 104
                            radius: 52
                            color: ForkTheme.bg
                            border.color: ForkTheme.lineSoft
                            Accessible.ignored: true

                            Repeater {
                                model: layoutCard.modelData.faces

                                delegate: Rectangle {
                                    id: face
                                    required property string modelData
                                    required property int index

                                    // The A button stands out
                                    readonly property bool isA: modelData === "A"

                                    x: layoutCard.spots[index].x
                                    y: layoutCard.spots[index].y
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: isA ? (layoutCard.selected ? ForkTheme.accent : ForkTheme.text2) : ForkTheme.tile

                                    ForkText {
                                        anchors.centerIn: parent
                                        kind: "label"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: face.isA ? (layoutCard.selected ? ForkTheme.textOnAccent : ForkTheme.bg) : ForkTheme.text
                                        text: face.modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Behavior -------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Behavior")
        // The title sits close above the rows, which draw their own padding, and the card is 8
        // shorter below them (the design's rows cards)
        spacing: 8
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Force gamepad #1 always connected")
                help: qsTr("Forces a single gamepad to always stay connected to the host, even if no gamepads are actually connected to this PC.") + " " +
                      qsTr("Only enable this option when streaming a game that doesn't support gamepads being connected after startup.")
                checked: !StreamingPreferences.multiController
                onToggled: (on) => StreamingPreferences.multiController = !on
            }

            ForkSwitchRow {
                label: qsTr("Enable mouse control with gamepads by holding the 'Start' button")
                checked: StreamingPreferences.gamepadMouse
                onToggled: (on) => StreamingPreferences.gamepadMouse = on
            }

            ForkSwitchRow {
                visible: SystemProperties.hasDesktopEnvironment
                label: qsTr("Process gamepad input when LuzLunar is in the background")
                help: qsTr("Allows LuzLunar to capture gamepad inputs even if it's not the current window in focus")
                checked: StreamingPreferences.backgroundGamepad
                onToggled: (on) => StreamingPreferences.backgroundGamepad = on
            }
        }
    }

    // ---- Mapping --------------------------------------------------------------------------

    ForkCard {
        quiet: true

        Flow {
            id: mappingFlow
            width: parent.width
            spacing: 16

            Row {
                id: mappingText
                width: mappingButtonBox.visible ? Math.max(Math.min(300, mappingFlow.width),
                                                           mappingFlow.width - mappingButtonBox.width - mappingFlow.spacing)
                                                : mappingFlow.width
                spacing: 14

                Rectangle {
                    width: 44
                    height: 44
                    radius: 12
                    color: ForkTheme.raised
                    Accessible.ignored: true

                    ForkSymbol {
                        anchors.centerIn: parent
                        symbol: "gamecontroller"
                        size: 22
                        color: ForkTheme.accentInk
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44 - parent.spacing
                    spacing: 4

                    ForkText {
                        width: parent.width
                        kind: "heading"
                        text: qsTr("Buttons come out wrong?")
                    }

                    ForkText {
                        width: parent.width
                        kind: "help"
                        text: qsTr("A gamepad without a mapping needs one before LuzLunar can use it.")
                    }
                }
            }

            Item {
                id: mappingButtonBox
                visible: SystemProperties.hasBrowser
                width: mappingButton.width
                height: mappingText.height

                ForkButton {
                    id: mappingButton
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "accent"
                    text: qsTr("Gamepad mapping help")
                    onClicked: Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping")
                }
            }
        }
    }
}
