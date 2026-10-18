import QtQuick

import ClientHardware 1.0
import ForkTheme 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

// [fork] Settings › Video: how the stream is decoded and drawn on this Mac (codec, decoder,
// renderer), and the two settings that trade picture quality for bandwidth (full color, the
// bitrate limit). Each forced codec's card says whether this Mac decodes it in hardware, from
// ClientHardware. A saved codec or renderer that none of the cards stands for (the deprecated
// HEVC HDR codec, say) shows Automatic selected but isn't rewritten until the user picks one.
Column {
    id: videoSection

    spacing: ForkTheme.gap

    // ---- Codec ----------------------------------------------------------------------------

    // The cards, in order. decoder is the key in ClientHardware.decoders ("" for Automatic).
    readonly property var codecs: [
        { "value": StreamingPreferences.VCC_AUTO, "decoder": "",
          "title": qsTr("Automatic"),
          "subtitle": qsTr("Picks the best codec this Mac and the PC both support.") },
        { "value": StreamingPreferences.VCC_FORCE_H264, "decoder": "h264",
          "title": qsTr("H.264"),
          "subtitle": qsTr("Works with every host and GPU. Needs the most bitrate.") },
        { "value": StreamingPreferences.VCC_FORCE_HEVC, "decoder": "hevc",
          "title": qsTr("HEVC (H.265)"),
          "subtitle": qsTr("Sharper at the same bitrate, and carries HDR.") },
        { "value": StreamingPreferences.VCC_FORCE_AV1, "decoder": "av1",
          "title": qsTr("AV1"),
          "subtitle": qsTr("The most efficient. Needs Sunshine or Apollo and a recent GPU.") }
    ]

    // Which codecs this Mac decodes in hardware: h264, hevc, hevcMain10 and av1
    readonly property var hardwareDecoders: ClientHardware.decoders

    // The codec whose card is selected: the saved one, or Automatic when no card stands for it
    readonly property int shownCodec: {
        var saved = StreamingPreferences.videoCodecConfig
        if (saved === StreamingPreferences.VCC_FORCE_H264 || saved === StreamingPreferences.VCC_FORCE_HEVC
                || saved === StreamingPreferences.VCC_FORCE_AV1) {
            return saved
        }
        return StreamingPreferences.VCC_AUTO
    }

    // The renderer the drop-down shows, chosen the same way
    readonly property int shownRenderer: {
        var saved = StreamingPreferences.rendererSelection
        if (saved === StreamingPreferences.RS_METAL || saved === StreamingPreferences.RS_VULKAN
                || saved === StreamingPreferences.RS_AVSBDL) {
            return saved
        }
        return StreamingPreferences.RS_AUTO
    }

    // The drop-down's choices, and the position of the one shown
    readonly property var rendererOptions: [
        { "value": StreamingPreferences.RS_AUTO, "label": qsTr("Automatic (Recommended)") },
        { "value": StreamingPreferences.RS_METAL, "label": "Metal" },
        { "value": StreamingPreferences.RS_VULKAN, "label": "Vulkan" },
        { "value": StreamingPreferences.RS_AVSBDL, "label": "AVSampleBufferDisplayLayer" }
    ]

    readonly property int rendererIndex: {
        for (var i = 0; i < rendererOptions.length; i++) {
            if (rendererOptions[i].value === shownRenderer) {
                return i
            }
        }
        return 0
    }

    // ---- Decoding -------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Decoding")

        Column {
            width: parent.width
            spacing: 10

            ForkText {
                kind: "label"
                font.weight: Font.DemiBold
                text: qsTr("Video codec")
            }

            Flow {
                id: codecFlow
                width: parent.width
                spacing: 10

                readonly property int columns: Math.min(4, Math.max(1, Math.floor((width + spacing) / (200 + spacing))))
                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                // The tallest card, so the cards are all as tall as it (their subtitles wrap differently)
                readonly property real tallest: {
                    var most = 0
                    for (var i = 0; i < codecRepeater.count; i++) {
                        var item = codecRepeater.itemAt(i)
                        if (item) {
                            most = Math.max(most, item.implicitHeight)
                        }
                    }
                    return most
                }

                Repeater {
                    id: codecRepeater
                    model: videoSection.codecs

                    delegate: ForkOptionCard {
                        id: codecCard
                        required property var modelData

                        readonly property bool automatic: modelData.decoder === ""
                        readonly property bool hardware: !automatic && videoSection.hardwareDecoders[modelData.decoder] === true
                        readonly property string statusText: {
                            if (automatic) {
                                return qsTr("Recommended")
                            }
                            if (!hardware) {
                                return qsTr("No hardware decoder")
                            }
                            if (modelData.decoder === "hevc" && videoSection.hardwareDecoders.hevcMain10 === true) {
                                return qsTr("Hardware decode · Main10")
                            }
                            return qsTr("Hardware decode")
                        }

                        width: codecFlow.cardWidth
                        height: Math.max(implicitHeight, codecFlow.tallest)
                        title: modelData.title
                        subtitle: modelData.subtitle
                        selected: videoSection.shownCodec === modelData.value
                        onClicked: StreamingPreferences.videoCodecConfig = modelData.value
                        Accessible.description: modelData.subtitle + " " + statusText

                        radio: true

                        // Whether this Mac decodes the codec in hardware, at the bottom of the card
                        below: Row {
                            height: 16
                            spacing: 6
                            Accessible.ignored: true

                            ForkSymbol {
                                visible: codecCard.automatic || codecCard.hardware
                                anchors.verticalCenter: parent.verticalCenter
                                symbol: "checkmark"
                                fallback: "qrc:/res/baseline-check_circle_outline-24px.svg"
                                size: 11
                                color: ForkTheme.ok
                            }

                            ForkText {
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "help"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: codecCard.automatic || codecCard.hardware ? ForkTheme.ok : ForkTheme.muted
                                text: codecCard.statusText
                            }
                        }
                    }
                }
            }
        }

        Flow {
            id: rendererFlow
            width: parent.width
            spacing: 32

            Column {
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Video decoder")
                }

                ForkSegmented {
                    accessibleName: qsTr("Video decoder")
                    options: [
                        { "value": StreamingPreferences.VDS_AUTO, "label": qsTr("Automatic") },
                        { "value": StreamingPreferences.VDS_FORCE_HARDWARE, "label": qsTr("Hardware") },
                        { "value": StreamingPreferences.VDS_FORCE_SOFTWARE, "label": qsTr("Software") }
                    ]
                    value: StreamingPreferences.videoDecoderSelection
                    onActivated: (value) => StreamingPreferences.videoDecoderSelection = value
                }
            }

            Column {
                visible: SystemProperties.isDarwin
                // The drop-down is at most 320 wide
                width: Math.min(320, rendererFlow.width)
                spacing: 10

                ForkText {
                    kind: "label"
                    font.weight: Font.DemiBold
                    text: qsTr("Renderer")
                }

                AutoResizingComboBox {
                    width: parent.width
                    model: videoSection.rendererOptions
                    textRole: "label"
                    currentIndex: videoSection.rendererIndex
                    Accessible.name: qsTr("Renderer")
                    // The list has the right width without measuring it
                    onActivated: (index) => StreamingPreferences.rendererSelection = videoSection.rendererOptions[index].value
                }
            }
        }
    }

    // ---- Quality --------------------------------------------------------------------------

    ForkCard {
        title: qsTr("Quality")
        // The title sits close above the rows, which draw their own padding, and the card is 14
        // short below them (the design's rows cards)
        spacing: 8
        height: implicitHeight - 8

        Column {
            width: parent.width
            spacing: 0

            ForkSwitchRow {
                showDivider: false
                label: qsTr("Full color (YUV 4:4:4)")
                help: qsTr("Good for streaming desktop and text-heavy games, but not recommended for fast-paced games.")
                checked: StreamingPreferences.enableYUV444
                onToggled: (on) => {
                    StreamingPreferences.enableYUV444 = on
                    // The default bitrate depends on it, so a bitrate nobody set by hand follows
                    if (StreamingPreferences.autoAdjustBitrate) {
                        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                                                                  StreamingPreferences.height,
                                                                                                  StreamingPreferences.fps,
                                                                                                  StreamingPreferences.enableYUV444)
                    }
                }
            }

            ForkSwitchRow {
                label: qsTr("Unlock bitrate limit")
                tag: qsTr("Experimental")
                help: qsTr("This unlocks extremely high video bitrates for use with Sunshine hosts. It should only be used when streaming over an Ethernet LAN connection.")
                checked: StreamingPreferences.unlockBitrate
                onToggled: (on) => {
                    StreamingPreferences.unlockBitrate = on
                    // Locking the limit again brings a bitrate above it back down
                    StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, on ? 500000 : 150000)
                }
            }
        }
    }

    // ---- Warnings -------------------------------------------------------------------------

    ForkWarnBox {
        okText: qsTr("This Mac decodes these settings in hardware.")
        warnings: {
            // Read so the warnings are checked again when the displays change
            ClientHardware.displays
            return ClientHardware.warningsFor(StreamingPreferences.width, StreamingPreferences.height, StreamingPreferences.fps,
                                              StreamingPreferences.videoCodecConfig, StreamingPreferences.enableHdr)
        }
    }
}
