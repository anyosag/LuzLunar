import QtQuick
import QtQuick.Shapes

import ForkTheme 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] Settings › Audio: the speaker layout (each card draws where the speakers sit around the
// listener) and whether the host PC's own speakers and LuzLunar's stream are muted.
Column {
    id: audioSection

    spacing: ForkTheme.gap

    // The speaker layouts. Each speaker is a dot at x and y, in percent of the diagram; sub is the
    // subwoofer, drawn as a rounded square.
    readonly property var layouts: [
        { "value": StreamingPreferences.AC_STEREO, "title": qsTr("Stereo"), "subtitle": qsTr("2 channels"),
          "speakers": [
              { "x": 22, "y": 20, "sub": false }, { "x": 78, "y": 20, "sub": false }
          ] },
        { "value": StreamingPreferences.AC_51_SURROUND, "title": qsTr("5.1 surround"), "subtitle": qsTr("6 channels"),
          "speakers": [
              { "x": 20, "y": 20, "sub": false }, { "x": 50, "y": 12, "sub": false }, { "x": 80, "y": 20, "sub": false },
              { "x": 66, "y": 30, "sub": true },
              { "x": 10, "y": 80, "sub": false }, { "x": 90, "y": 80, "sub": false }
          ] },
        { "value": StreamingPreferences.AC_71_SURROUND, "title": qsTr("7.1 surround"), "subtitle": qsTr("8 channels"),
          "speakers": [
              { "x": 20, "y": 20, "sub": false }, { "x": 50, "y": 12, "sub": false }, { "x": 80, "y": 20, "sub": false },
              { "x": 66, "y": 30, "sub": true },
              { "x": 8, "y": 58, "sub": false }, { "x": 92, "y": 58, "sub": false },
              { "x": 32, "y": 90, "sub": false }, { "x": 68, "y": 90, "sub": false }
          ] }
    ]

    // ---- Speakers -------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Speakers")

        Flow {
            id: layoutFlow
            width: parent.width
            spacing: 10

            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (200 + spacing)))
            // Cards at least 200 wide; three of them sit together at the left, as wide as the
            // fourth would be, and don't stretch across the card
            readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

            Repeater {
                model: audioSection.layouts

                delegate: ForkOptionCard {
                    id: layoutCard
                    required property var modelData

                    width: layoutFlow.cardWidth
                    title: modelData.title
                    subtitle: modelData.subtitle
                    selected: StreamingPreferences.audioConfig === modelData.value
                    onClicked: StreamingPreferences.audioConfig = modelData.value

                    // The room from above: the listener in the middle, the speakers around them
                    Rectangle {
                        id: room
                        width: layoutCard.width - layoutCard.leftPadding - layoutCard.rightPadding
                        height: 112
                        radius: 10
                        color: ForkTheme.bg
                        border.color: ForkTheme.lineSoft
                        Accessible.ignored: true

                        // The listener, inside a dashed ring
                        Shape {
                            x: room.width * 0.5 - 14
                            y: room.height * 0.58 - 14
                            width: 28
                            height: 28
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: ForkTheme.trackEdge
                                strokeWidth: 1.5
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [3, 2.5]
                                fillColor: "transparent"
                                startX: 0.75; startY: 14
                                PathArc { x: 27.25; y: 14; radiusX: 13.25; radiusY: 13.25 }
                                PathArc { x: 0.75; y: 14; radiusX: 13.25; radiusY: 13.25 }
                            }
                        }

                        Rectangle {
                            x: room.width * 0.5 - 4
                            y: room.height * 0.58 - 4
                            width: 8
                            height: 8
                            radius: 4
                            color: ForkTheme.text2
                        }

                        Repeater {
                            model: layoutCard.modelData.speakers

                            delegate: Rectangle {
                                required property var modelData

                                x: room.width * modelData.x / 100 - 6
                                y: room.height * modelData.y / 100 - 6
                                width: 12
                                height: 12
                                radius: modelData.sub ? 3 : 6
                                color: layoutCard.selected ? ForkTheme.accent : ForkTheme.trackEdge
                            }
                        }
                    }
                }
            }
        }

        ForkText {
            width: parent.width
            kind: "help"
            font.pixelSize: 13
            text: qsTr("Surround needs speakers or headphones set up for it in Audio MIDI Setup. Stereo is right for the built-in speakers and most headphones.")
        }
    }

    // ---- Muting ---------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Muting")
        // The title sits close above the rows, which draw their own padding, and the card is 8
        // shorter below them (the design's rows cards)
        spacing: 8
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Mute host PC speakers while streaming")
                help: qsTr("You must restart any game currently in progress for this setting to take effect")
                checked: !StreamingPreferences.playAudioOnHost
                onToggled: (on) => StreamingPreferences.playAudioOnHost = !on
            }

            ForkSwitchRow {
                visible: SystemProperties.hasDesktopEnvironment
                label: qsTr("Mute audio stream when LuzLunar is not the active window")
                help: qsTr("Mutes LuzLunar's audio when you switch to another app or click on a different window.")
                checked: StreamingPreferences.muteOnFocusLoss
                onToggled: (on) => StreamingPreferences.muteOnFocusLoss = on
            }
        }
    }
}
