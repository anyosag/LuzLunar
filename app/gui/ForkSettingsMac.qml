import QtQuick
import QtQuick.Shapes

import ClientHardware 1.0
import ForkPreferences 1.0
import ForkTheme 1.0
import SystemProperties 1.0

// [fork] Settings › This Mac: the chip, each display's shape and the hardware video decoders that
// the warnings about stream settings are checked against (what ForkThisMacGroupBox lists for
// upstream's page), how the Mac's screen is described to Apollo hosts, and this Mac's disk as a
// drive on the PC (ForkMacDriveCard). The hardware shown is read from ClientHardware; "Check
// again" reads it again.
Column {
    id: macSection

    spacing: ForkTheme.gap

    // "Check again" sits in the page title's row (ForkSettingsView shows a section's headerAction
    // beside the title)
    property Component headerAction: Component {
        ForkButton {
            symbol: "arrow.clockwise"
            text: qsTr("Check again")
            onClicked: macSection.checkAgain()
        }
    }

    // What ClientHardware reports, as one string to compare
    function snapshot() {
        return JSON.stringify([ClientHardware.chip, ClientHardware.gpu, ClientHardware.decoders, ClientHardware.displays])
    }

    // Reads the hardware again and says so, and whether it found anything new
    function checkAgain() {
        var before = snapshot()
        ClientHardware.refresh()
        if (window.forkToast) {
            window.forkToast(snapshot() === before ? qsTr("Checked this Mac again: nothing changed")
                                                    : qsTr("Checked this Mac again"))
        }
    }

    // "Up to 120 Hz · HDR up to 1600 nits · Display P3 · 30.2×19.6 cm · camera notch"
    function describe(display) {
        var parts = []
        if (display.maxRefresh > 0) {
            parts.push(qsTr("Up to %1 Hz").arg(display.maxRefresh))
        }
        if (display.hdr) {
            parts.push(display.hdrPeak > 0 ? qsTr("HDR up to %1 nits").arg(display.hdrPeak) : qsTr("HDR"))
        }
        if (display.p3) {
            parts.push(qsTr("Display P3"))
        }
        if (display.widthMm > 0 && display.heightMm > 0) {
            parts.push(qsTr("%1×%2 cm").arg((display.widthMm / 10).toFixed(1)).arg((display.heightMm / 10).toFixed(1)))
        }
        if (display.hasNotch) {
            parts.push(qsTr("camera notch"))
        }
        return parts.join(" · ")
    }

    // ---- Chip -------------------------------------------------------------------------------

    ForkCard {
        Item {
            width: parent.width
            height: Math.max(chipTile.height, chipTexts.implicitHeight)

            Rectangle {
                id: chipTile
                anchors.verticalCenter: parent.verticalCenter
                width: 72
                height: 72
                radius: 18
                color: ForkTheme.raised
                Accessible.ignored: true

                ForkSymbol {
                    anchors.centerIn: parent
                    symbol: "cpu"
                    size: 36
                    color: ForkTheme.accentInk
                }
            }

            Column {
                id: chipTexts
                anchors.left: chipTile.right
                anchors.leftMargin: 24
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                ForkText {
                    kind: "eyebrow"
                    text: qsTr("Chip")
                }

                ForkText {
                    width: parent.width
                    kind: "titleSm"
                    pixelSize: 30
                    elide: Text.ElideRight
                    text: ClientHardware.chip !== "" ? ClientHardware.chip : qsTr("Unknown")
                }

                // The chip is the GPU on Apple Silicon, so this only shows for a separate one
                ForkText {
                    width: parent.width
                    visible: ClientHardware.gpu !== "" && ClientHardware.gpu !== ClientHardware.chip
                    kind: "help"
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    text: qsTr("Graphics: %1").arg(ClientHardware.gpu)
                }
            }
        }
    }

    // ---- Displays ---------------------------------------------------------------------------

    Repeater {
        model: ClientHardware.displays

        delegate: ForkCard {
            id: displayCard

            required property var modelData

            // Which shape the diagram highlights, "full" or "below". Only a way to look: it
            // changes no setting.
            property string shape: "below"

            readonly property bool notched: modelData.hasNotch === true
            readonly property bool fullShown: !notched || shape === "full"

            readonly property real panelRatio: modelData.nativeWidth > 0 && modelData.nativeHeight > 0
                                               ? modelData.nativeWidth / modelData.nativeHeight : 1.6

            // The share of the panel's height taken by the notch's strip
            readonly property real stripFraction: notched && modelData.nativeHeight > 0
                                                  ? Math.max(0, (modelData.nativeHeight - modelData.safeHeight) / modelData.nativeHeight) : 0

            readonly property string fullSize: modelData.nativeWidth + "×" + modelData.nativeHeight
            readonly property string belowSize: modelData.safeWidth + "×" + modelData.safeHeight

            Column {
                width: parent.width
                spacing: 4

                ForkText {
                    kind: "eyebrow"
                    text: qsTr("Display")
                    Accessible.role: Accessible.Heading
                }

                ForkText {
                    width: parent.width
                    kind: "heading"
                    font.pixelSize: 17
                    elide: Text.ElideRight
                    text: displayCard.modelData.name
                }

                ForkText {
                    width: parent.width
                    visible: text !== ""
                    kind: "help"
                    font.pixelSize: 13
                    text: macSection.describe(displayCard.modelData)
                }
            }

            // The panel's picture beside the two shapes to look at (below it when there's no room)
            Item {
                id: shapeArea
                width: parent.width

                readonly property real gapBeside: 40
                readonly property real gapBelow: 24
                readonly property bool beside: width >= panel.width + gapBeside + 240

                height: beside ? Math.max(panel.height, optionColumn.implicitHeight)
                               : panel.height + gapBelow + optionColumn.implicitHeight

                // The panel, with the strip below the notch and the notch itself: 340 wide at the
                // display's native shape
                Rectangle {
                    id: panel
                    width: Math.min(340, shapeArea.width)
                    height: width / displayCard.panelRatio
                    anchors.verticalCenter: shapeArea.beside ? parent.verticalCenter : undefined
                    radius: 10
                    color: ForkTheme.bar
                    border.width: 2
                    border.color: displayCard.fullShown ? ForkTheme.selEdge : ForkTheme.lineStrong
                    Accessible.ignored: true

                    Item {
                        id: panelInner
                        anchors.fill: parent
                        anchors.margins: panel.border.width

                        // The area below the notch; with the strip chosen it's picked out in
                        // the selection's colors and its top edge is dashed
                        Rectangle {
                            visible: displayCard.notched
                            y: panelInner.height * displayCard.stripFraction
                            width: parent.width
                            height: parent.height - y
                            bottomLeftRadius: panel.radius - panel.border.width
                            bottomRightRadius: panel.radius - panel.border.width
                            color: displayCard.fullShown ? ForkTheme.raised : ForkTheme.sel

                            Shape {
                                visible: !displayCard.fullShown
                                width: parent.width
                                height: 1
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    strokeColor: ForkTheme.selEdge
                                    strokeWidth: 1
                                    strokeStyle: ShapePath.DashLine
                                    dashPattern: [3, 3]
                                    fillColor: "transparent"
                                    startX: 0
                                    startY: 0.5
                                    PathLine { x: panelInner.width; y: 0.5 }
                                }
                            }
                        }

                        // The notch is black on every display
                        Rectangle {
                            visible: displayCard.notched
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.14
                            height: parent.height * displayCard.stripFraction
                            bottomLeftRadius: 6
                            bottomRightRadius: 6
                            color: "#000000"
                        }

                        ForkText {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            kind: "mono"
                            text: displayCard.fullShown ? displayCard.fullSize : displayCard.belowSize
                        }

                        ForkText {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            kind: "mono"
                            color: ForkTheme.accentInk
                            text: displayCard.fullShown ? displayCard.modelData.fullRatio : displayCard.modelData.belowNotchRatio
                        }
                    }
                }

                Column {
                    id: optionColumn
                    x: shapeArea.beside ? panel.width + shapeArea.gapBeside : 0
                    y: shapeArea.beside ? (shapeArea.height - height) / 2 : panel.height + shapeArea.gapBelow
                    width: shapeArea.width - x
                    spacing: 10

                    ForkOptionCard {
                        width: parent.width
                        height: Math.max(60, implicitHeight)
                        visible: displayCard.notched
                        compact: true
                        title: qsTr("Full panel, with the notch area")
                        subtitle: qsTr("%1 · %2").arg(displayCard.fullSize).arg(displayCard.modelData.fullRatio)
                        selected: displayCard.shape === "full"
                        onClicked: displayCard.shape = "full"
                    }

                    ForkOptionCard {
                        width: parent.width
                        height: Math.max(60, implicitHeight)
                        visible: displayCard.notched
                        compact: true
                        title: qsTr("Below the notch")
                        subtitle: qsTr("%1 · %2").arg(displayCard.belowSize).arg(displayCard.modelData.belowNotchRatio)
                        selected: displayCard.shape === "below"
                        onClicked: displayCard.shape = "below"
                    }

                    // Without a notch there's one shape
                    ForkText {
                        width: parent.width
                        visible: !displayCard.notched
                        kind: "mono"
                        font.pixelSize: 14
                        color: ForkTheme.text2
                        text: qsTr("%1 · %2").arg(displayCard.fullSize).arg(displayCard.modelData.fullRatio)
                    }
                }
            }

            ForkText {
                width: parent.width
                visible: displayCard.notched
                kind: "help"
                text: qsTr("Both shapes appear in Display › Aspect ratio. Streams below the notch leave the strip free for the notch bar.")
            }
        }
    }

    // ---- Hardware decoding ------------------------------------------------------------------

    ForkCard {
        title: qsTr("Hardware decoding")

        Flow {
            id: decoderFlow
            width: parent.width
            spacing: 10

            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (150 + spacing)))
            readonly property real tileWidth: (width - (columns - 1) * spacing) / columns

            // The tallest tile's height, so the tiles are all as tall as it (a note can wrap)
            readonly property real tallest: {
                var most = 0
                for (var i = 0; i < decoderRepeater.count; i++) {
                    var item = decoderRepeater.itemAt(i)
                    if (item) {
                        most = Math.max(most, item.needed)
                    }
                }
                return most
            }

            Repeater {
                id: decoderRepeater
                model: [
                    { "key": "h264", "name": "H.264", "note": qsTr("Up to 4096 pixels on a side") },
                    { "key": "hevc", "name": "HEVC", "note": qsTr("The usual choice") },
                    { "key": "hevcMain10", "name": "HEVC Main10", "note": qsTr("For HDR") },
                    { "key": "av1", "name": "AV1", "note": qsTr("The most efficient") }
                ]

                delegate: Rectangle {
                    id: decoderTile

                    required property var modelData

                    // Read through ClientHardware so the tile follows "Check again"
                    readonly property bool hardware: ClientHardware.decoders[modelData.key] === true

                    // The room this tile's text needs
                    readonly property real needed: decoderColumn.implicitHeight + 28

                    width: decoderFlow.tileWidth
                    height: Math.max(needed, decoderFlow.tallest)
                    radius: ForkTheme.radiusTile
                    color: ForkTheme.bar
                    border.color: ForkTheme.lineSoft

                    Accessible.role: Accessible.StaticText
                    Accessible.name: qsTr("%1: %2. %3").arg(modelData.name)
                                                       .arg(hardware ? qsTr("Hardware") : qsTr("Software only"))
                                                       .arg(modelData.note)

                    Column {
                        id: decoderColumn
                        x: 14
                        y: 14
                        width: parent.width - 28
                        spacing: 8

                        Row {
                            spacing: 6

                            ForkSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: decoderTile.hardware
                                symbol: "checkmark"
                                size: 14
                                color: ForkTheme.ok
                                Accessible.ignored: true
                            }

                            ForkText {
                                kind: "help"
                                font.weight: Font.DemiBold
                                color: decoderTile.hardware ? ForkTheme.ok : ForkTheme.muted
                                text: decoderTile.hardware ? qsTr("Hardware") : qsTr("Software only")
                                Accessible.ignored: true
                            }
                        }

                        ForkText {
                            width: parent.width
                            kind: "mono"
                            font.pixelSize: 16
                            elide: Text.ElideRight
                            text: decoderTile.modelData.name
                            Accessible.ignored: true
                        }

                        ForkText {
                            width: parent.width
                            kind: "help"
                            text: decoderTile.modelData.note
                            Accessible.ignored: true
                        }
                    }
                }
            }
        }

        ForkText {
            width: parent.width
            kind: "help"
            text: qsTr("Settings warns you when a choice doesn't fit this Mac, such as a codec it can only decode in software.")
        }
    }

    // ---- Screen info for Apollo -------------------------------------------------------------

    ForkCard {
        visible: SystemProperties.isDarwin
        title: qsTr("Screen info for Apollo")
        spacing: 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Describe this Mac's screen to Apollo hosts")
                help: qsTr("Each stream tells the host this screen's size, colors, HDR brightness and shapes, so the virtual display Apollo creates with the LuzVDA driver matches it: Windows picks a fitting scale and aims HDR at what this screen can show. Other hosts ignore it.")
                checked: ForkPreferences.describeDisplay
                onToggled: (on) => ForkPreferences.describeDisplay = on
            }
        }

        Column {
            visible: ForkPreferences.describeDisplay
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("HDR peak brightness")
            }

            ForkSegmented {
                // Nits for each segment; 0 lets LuzLunar work it out from the screen
                readonly property var peaks: [0, 400, 600, 1000, 1600]

                accessibleName: qsTr("HDR peak brightness")
                options: [
                    { "value": 0, "label": qsTr("Automatic") },
                    { "value": 400, "label": qsTr("400 nits") },
                    { "value": 600, "label": qsTr("600 nits") },
                    { "value": 1000, "label": qsTr("1000 nits") },
                    { "value": 1600, "label": qsTr("1600 nits") }
                ]
                // A value that isn't one of these shows as Automatic, as upstream's list does
                value: peaks.indexOf(ForkPreferences.hdrPeakOverride) >= 0 ? ForkPreferences.hdrPeakOverride : 0
                onActivated: (value) => ForkPreferences.hdrPeakOverride = value
            }
        }

        // Sent whether or not the screen is described
        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                label: qsTr("Make this Mac the PC's main display")
                help: qsTr("In Apollo's Virtual Display app, Windows makes this Mac's screen its main display, with the taskbar and new windows, and keeps the PC's monitors on beside it. It stays the main display until you quit the app, even after you disconnect, so quit it before someone uses the PC. Other apps and hosts ignore it.")
                checked: ForkPreferences.hostPrimaryDisplay
                onToggled: (on) => ForkPreferences.hostPrimaryDisplay = on
            }
        }
    }

    // ---- This Mac on the PC -----------------------------------------------------------------

    ForkMacDriveCard {
        visible: SystemProperties.isDarwin
    }
}
