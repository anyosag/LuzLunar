import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Controls.impl 2.15

import ClientHardware 1.0
import SfSymbols 1.0
import StreamingPreferences 1.0

// Advice about stream settings that this Mac's hardware can't handle well, such as a codec it has
// no decoder for. Hidden when there's nothing to say. It checks the global settings unless a
// caller sets its own values (the stream profile dialog does).
Column {
    id: hardwareWarnings

    property int streamWidth: StreamingPreferences.width
    property int streamHeight: StreamingPreferences.height
    property int streamFps: StreamingPreferences.fps
    property int codecConfig: StreamingPreferences.videoCodecConfig
    property bool hdr: StreamingPreferences.enableHdr

    readonly property var warnings: {
        // Not used, but read so the warnings are checked again when the displays change
        ClientHardware.displays
        return ClientHardware.warningsFor(streamWidth, streamHeight, streamFps, codecConfig, hdr)
    }

    visible: warnings.length > 0
    spacing: 4

    Repeater {
        model: hardwareWarnings.warnings

        delegate: Row {
            width: hardwareWarnings.width
            spacing: 6

            IconImage {
                id: warningIcon
                y: 1
                source: SfSymbols.available ? SfSymbols.url("exclamationmark.triangle.fill")
                                            : "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg"
                color: "#FF9F0A"
                // Drawn at 14 pt from a 2x image, so it's sharp on Retina
                width: 14
                height: 14
                sourceSize {
                    width: 28
                    height: 28
                }
            }

            Label {
                width: parent.width - warningIcon.width - parent.spacing
                text: modelData
                font.pointSize: 9
                wrapMode: Text.Wrap
            }
        }
    }
}
