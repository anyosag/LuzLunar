import QtQuick

import ClientHardware 1.0
import ForkTheme 1.0

// [fork] One line about this Mac under Your PCs: its chip, its built-in display and the codecs it
// decodes in hardware (from ClientHardware, which Settings › This Mac shows in full)
Rectangle {
    id: strip

    readonly property var display: {
        var displays = ClientHardware.displays
        for (var i = 0; i < displays.length; i++) {
            if (displays[i].isBuiltin) {
                return displays[i]
            }
        }
        return displays.length > 0 ? displays[0] : null
    }

    readonly property var hardwareCodecs: {
        var decoders = ClientHardware.decoders
        var list = []
        if (decoders.h264) list.push("H.264")
        if (decoders.hevc) list.push("HEVC")
        if (decoders.hevcMain10) list.push(qsTr("HEVC 10-bit"))
        if (decoders.av1) list.push("AV1")
        return list
    }

    implicitHeight: flow.implicitHeight + 28
    radius: ForkTheme.radiusCard
    color: ForkTheme.bar
    border.color: ForkTheme.lineSoft
    visible: ClientHardware.chip !== ""

    Accessible.role: Accessible.StaticText
    Accessible.name: ClientHardware.summary

    Flow {
        id: flow
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 40
        spacing: 26

        ForkText {
            height: 22
            verticalAlignment: Text.AlignVCenter
            kind: "eyebrow"
            text: qsTr("This Mac")
        }

        Row {
            height: 22
            spacing: 8

            ForkSymbol {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "cpu"
                size: 15
                color: ForkTheme.muted
            }

            ForkText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "body"
                wrapMode: Text.NoWrap
                text: ClientHardware.chip
            }
        }

        Row {
            visible: strip.display !== null
            height: 22
            spacing: 8

            ForkSymbol {
                anchors.verticalCenter: parent.verticalCenter
                symbol: strip.display && strip.display.isBuiltin ? "laptopcomputer" : "display"
                size: 15
                color: ForkTheme.muted
            }

            ForkText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "body"
                wrapMode: Text.NoWrap
                text: {
                    var d = strip.display
                    if (!d) {
                        return ""
                    }
                    var parts = [d.nativeWidth + "×" + d.nativeHeight]
                    if (d.maxRefresh > 0) {
                        parts.push(qsTr("%1 Hz").arg(d.maxRefresh))
                    }
                    if (d.hasNotch) {
                        parts.push(qsTr("notch"))
                    }
                    return d.name + " · " + parts.join(" · ")
                }
            }
        }

        Row {
            visible: strip.hardwareCodecs.length > 0
            height: 22
            spacing: 6

            ForkText {
                anchors.verticalCenter: parent.verticalCenter
                kind: "body"
                color: ForkTheme.muted
                wrapMode: Text.NoWrap
                rightPadding: 4
                text: qsTr("Hardware decode")
            }

            Repeater {
                model: strip.hardwareCodecs

                delegate: Rectangle {
                    required property string modelData

                    anchors.verticalCenter: parent.verticalCenter
                    width: codecLabel.implicitWidth + 16
                    height: 22
                    radius: 6
                    color: ForkTheme.raised

                    ForkText {
                        id: codecLabel
                        anchors.centerIn: parent
                        kind: "mono"
                        text: parent.modelData
                    }
                }
            }
        }
    }
}
