import QtQuick
import QtQuick.Shapes

import ForkPreferences 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0

// [fork] Settings › Mouse & trackpad: whether the stream holds the pointer (games) or lets it
// cross in and out like any window (remote desktop), the mouse button and scrolling options, and
// what the Mac trackpad is in a stream (Mac trackpad, Windows touchpad or Mac mouse).
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

        // The PC's pointer in its Windows shape, drawn here with no stream delay (app/fork/forkcursor.*)
        ForkSwitchRow {
            label: qsTr("Draw the PC's pointer on this Mac")
            help: qsTr("In remote desktop and Mac trackpad modes, the PC's pointer moves with no stream delay, in its own Windows shape. Needs LuzLunar's Apollo on the PC; otherwise, and in games, the PC draws it in the picture.")
            checked: ForkPreferences.drawPcPointer
            onToggled: (on) => ForkPreferences.drawPcPointer = on
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

    // ---- Trackpad -------------------------------------------------------------------------

    // Trackpad passthrough (app/fork/forktrackpadpassthrough.cpp). Each app can choose otherwise in
    // its Stream Settings.
    ForkCard {
        id: trackpadCard
        title: qsTr("Trackpad")
        spacing: 8
        height: implicitHeight - 8

        readonly property int mode: StreamingPreferences.trackpadMode

        Column {
            width: parent.width
            spacing: 10

            ForkSegmented {
                accessibleName: qsTr("Trackpad")
                options: [
                    { "value": StreamingPreferences.TM_MAC_TRACKPAD, "label": qsTr("Mac trackpad") },
                    { "value": StreamingPreferences.TM_WINDOWS_TOUCHPAD, "label": qsTr("Windows touchpad") },
                    { "value": StreamingPreferences.TM_MAC_MOUSE, "label": qsTr("Mac mouse") }
                ]
                value: trackpadCard.mode
                onActivated: (value) => StreamingPreferences.trackpadMode = value
            }

            ForkText {
                width: parent.width
                kind: "body"
                color: ForkTheme.text2
                wrapMode: Text.WordWrap
                text: trackpadCard.mode === StreamingPreferences.TM_MAC_TRACKPAD
                      ? qsTr("macOS points, clicks and scrolls, with its own speed, palm rejection and momentum, so the trackpad feels as it does on this Mac. Three- and four-finger swipes and pinches go to Windows as touchpad gestures. While the stream runs, Apollo turns Windows' pointer acceleration off so it doesn't add to macOS's. Needs LuzLunar's Apollo on Windows 11.")
                      : trackpadCard.mode === StreamingPreferences.TM_WINDOWS_TOUCHPAD
                      ? qsTr("Windows gets every finger, except palms and resting thumbs, and makes its own pointer, taps, scrolling and gestures, with its touchpad settings. Needs LuzLunar's Apollo on Windows 11.")
                      : qsTr("The trackpad is a mouse, as in Moonlight: macOS's pointer and clicks, scrolling a notch at a time, and no Windows gestures.")
            }

            ForkText {
                width: parent.width
                visible: trackpadCard.mode !== StreamingPreferences.TM_MAC_MOUSE
                kind: "help"
                wrapMode: Text.WordWrap
                text: qsTr("The stream captures the pointer, and macOS's trackpad gestures wait while the stream is in front. Apps can choose otherwise in Stream Settings.")
            }
        }

        // How far Windows scrolls for the fingers' scrolling, in Mac trackpad mode
        Column {
            width: parent.width
            visible: trackpadCard.mode === StreamingPreferences.TM_MAC_TRACKPAD
            topPadding: 6
            spacing: 8

            Item {
                width: parent.width
                height: scrollSpeedLabel.implicitHeight

                ForkText {
                    id: scrollSpeedLabel
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Scroll speed")
                }

                ForkText {
                    anchors.right: parent.right
                    kind: "mono"
                    font.pixelSize: 14
                    color: ForkTheme.accentInk
                    text: qsTr("%1×").arg(ForkPreferences.trackpadScrollSpeed.toFixed(2))
                }
            }

            ForkSlider {
                id: scrollSpeedSlider
                width: parent.width
                from: 0.25
                to: 3
                stepSize: 0.05
                Accessible.name: qsTr("Scroll speed")

                onMoved: ForkPreferences.trackpadScrollSpeed = Math.round(value * 20) / 20

                Binding on value {
                    value: ForkPreferences.trackpadScrollSpeed
                    when: !scrollSpeedSlider.pressed
                }
            }

            Item {
                width: parent.width
                height: Math.max(scrollSpeedHelp.implicitHeight, scrollSpeedDefault.implicitHeight)

                ForkText {
                    id: scrollSpeedHelp
                    anchors.left: parent.left
                    anchors.right: scrollSpeedDefault.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "help"
                    wrapMode: Text.WordWrap
                    text: qsTr("Raise it if Windows scrolls less than your fingers move, lower it if more")
                }

                ForkButton {
                    id: scrollSpeedDefault
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "link"
                    visible: ForkPreferences.trackpadScrollSpeed !== 1
                    text: qsTr("Use default (1×)")
                    onClicked: ForkPreferences.trackpadScrollSpeed = 1
                }
            }
        }

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                label: qsTr("Also pause Notification Center's swipe and three-finger drag")
                help: qsTr("Switched off in System Settings while the stream is in front, and back on when it isn't, or the next time LuzLunar opens if it quit unexpectedly.")
                checked: ForkPreferences.trackpadPauseMacSettings
                onToggled: (on) => ForkPreferences.trackpadPauseMacSettings = on
            }

            // macOS only lets LuzLunar hold back its gestures with the Accessibility permission
            Item {
                id: accessibilityRow

                property bool trusted: ForkPreferences.accessibilityTrusted()

                width: parent.width
                implicitHeight: Math.max(accessibilityTexts.implicitHeight, accessibilityButton.implicitHeight) + 24

                // The permission is granted in System Settings, so look again while the page is open
                Timer {
                    interval: 2000
                    repeat: true
                    running: accessibilityRow.visible && !accessibilityRow.trusted
                    onTriggered: accessibilityRow.trusted = ForkPreferences.accessibilityTrusted()
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: ForkTheme.lineSoft
                }

                Column {
                    id: accessibilityTexts
                    anchors.left: parent.left
                    anchors.right: accessibilityButton.visible ? accessibilityButton.left : parent.right
                    anchors.rightMargin: accessibilityButton.visible ? 16 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    ForkText {
                        width: parent.width
                        kind: "label"
                        text: accessibilityRow.trusted ? qsTr("Accessibility: allowed") : qsTr("Accessibility: not allowed")
                    }

                    ForkText {
                        width: parent.width
                        kind: "help"
                        wrapMode: Text.WordWrap
                        text: accessibilityRow.trusted
                              ? qsTr("Spaces, Mission Control and the other system swipes stay with the stream while it's in front.")
                              : qsTr("Without it, the trackpad still goes to Windows, but a three- or four-finger swipe can switch Spaces on this Mac. If LuzLunar is already on the list, remove it and add it again.")
                    }
                }

                ForkButton {
                    id: accessibilityButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !accessibilityRow.trusted
                    text: qsTr("Open Privacy & Security")
                    onClicked: ForkPreferences.requestAccessibility()
                }
            }
        }
    }
}
