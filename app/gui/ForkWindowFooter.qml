// [fork] The window's 36 px footer bar (sky-chrome.md §6): "This Mac", its display, the codecs it
// decodes in hardware, and LuzLunar's version at the right. The data is ClientHardware's (what
// ForkThisMacStrip shows) and the fork's build id. `opaque` is the first-run page's variant:
// the plain bar colour, no display icon and the codecs as one line of text.
import QtQuick

import ClientHardware 1.0
import ForkPreferences 1.0
import ForkTheme 1.0

Item {
    id: root

    property Item skySource: null
    property bool opaque: false

    // The built-in display (else the first one)
    readonly property var display: {
        var displays = ClientHardware.displays
        for (var i = 0; i < displays.length; i++) {
            if (displays[i].isBuiltin) {
                return displays[i]
            }
        }
        return displays.length > 0 ? displays[0] : null
    }

    // "Built-in display · 3024×1890": the safe size below the notch
    property string displayText: {
        var d = display
        if (!d) {
            return ""
        }
        var w = d.safeWidth > 0 ? d.safeWidth : d.nativeWidth
        var h = d.safeHeight > 0 ? d.safeHeight : d.nativeHeight
        return (d.isBuiltin ? qsTr("Built-in display") : d.name) + " · " + w + "×" + h
    }

    property var codecs: {
        var decoders = ClientHardware.decoders
        var list = []
        if (decoders.h264) list.push("H.264")
        if (decoders.hevc) list.push("HEVC")
        if (decoders.hevcMain10) list.push(qsTr("HEVC 10-bit"))
        if (decoders.av1) list.push("AV1")
        return list
    }

    property string versionText: qsTr("LuzLunar %1").arg(ForkPreferences.buildId)

    height: 36
    implicitHeight: 36

    Accessible.role: Accessible.StaticText
    Accessible.name: displayText + (codecs.length > 0 ? ", " + qsTr("Hardware decode") + " " + codecs.join(", ") : "") + ", " + versionText

    ForkWindowGlass {
        anchors.fill: parent
        skySource: root.skySource
        sourceY: root.y
        edge: "bottom"
        opaque: root.opaque
    }

    Rectangle {
        width: parent.width
        height: 1
        color: ForkTheme.cv.line
    }

    Row {
        x: 20
        y: 1 + (parent.height - 1 - height) / 2
        height: 17
        spacing: 16

        ForkCanvasText {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("This Mac")
            color: ForkTheme.cv.faint
            px: 10.5
            weight: Font.Bold
            tracking: 0.84
            upper: true
        }

        Row {
            visible: root.displayText !== ""
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            ForkPathIcon {
                visible: !root.opaque
                anchors.verticalCenter: parent.verticalCenter
                name: "display"
                size: 14
                color: ForkTheme.cv.muted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.displayText
                color: ForkTheme.cv.muted
                font.family: ForkTheme.uiFamily
                font.pixelSize: 12
                textFormat: Text.PlainText
            }
        }

        // Hardware decode, with a chip per codec
        Row {
            visible: root.codecs.length > 0 && !root.opaque
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Hardware decode")
                color: ForkTheme.cv.muted
                font.family: ForkTheme.uiFamily
                font.pixelSize: 12
                textFormat: Text.PlainText
            }

            Repeater {
                model: root.codecs

                Rectangle {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: chip.implicitWidth + 12
                    height: chip.implicitHeight + 4
                    radius: 5
                    color: ForkTheme.cv.chip

                    Text {
                        id: chip
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: ForkTheme.cv.text2
                        font.family: ForkTheme.monoFamily
                        font.pixelSize: 11
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        // First run: one line of text
        Text {
            visible: root.codecs.length > 0 && root.opaque
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Hardware decode: %1").arg(root.codecs.join(", "))
            color: ForkTheme.cv.muted
            font.family: ForkTheme.uiFamily
            font.pixelSize: 12
            textFormat: Text.PlainText
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 20
        y: 1 + (parent.height - 1 - height) / 2
        text: root.versionText
        color: ForkTheme.cv.muted
        font.family: ForkTheme.uiFamily
        font.pixelSize: 12
        textFormat: Text.PlainText
    }
}
