import QtQuick 2.9
import QtQuick.Controls 2.2

import ClientHardware 1.0
import SystemProperties 1.0

// "This Mac" in SettingsView: the chip, displays and hardware video decoders that the warnings
// about stream settings are checked against.
GroupBox {
    id: thisMacGroupBox
    padding: 12
    title: qsTr("This Mac")
    font.pointSize: 12
    visible: SystemProperties.isDarwin

    // One line per display, like "Built-in Retina Display: 3024×1964 (1.54:1), 3024×1890 below the notch (16:10), up to 120 Hz, HDR"
    function describe(display) {
        var text = qsTr("%1: %2×%3 (%4)").arg(display.name).arg(display.nativeWidth).arg(display.nativeHeight).arg(display.fullRatio)
        if (display.hasNotch) {
            text += qsTr(", %1×%2 below the notch (%3)").arg(display.safeWidth).arg(display.safeHeight).arg(display.belowNotchRatio)
        }
        if (display.maxRefresh > 0) {
            text += qsTr(", up to %1 Hz").arg(display.maxRefresh)
        }
        if (display.hdr) {
            text += qsTr(", HDR")
        }
        return text
    }

    Column {
        anchors.fill: parent
        spacing: 5

        Label {
            width: parent.width
            text: ClientHardware.summary
            font.pointSize: 12
            wrapMode: Text.Wrap
        }

        Repeater {
            model: ClientHardware.displays

            delegate: Label {
                width: parent.width
                text: thisMacGroupBox.describe(modelData)
                font.pointSize: 9
                wrapMode: Text.Wrap
            }
        }

        // The chip is the GPU on Apple Silicon, so this only shows for a separate one
        Label {
            width: parent.width
            visible: ClientHardware.gpu !== "" && ClientHardware.gpu !== ClientHardware.chip
            text: qsTr("Graphics: %1").arg(ClientHardware.gpu)
            font.pointSize: 9
            wrapMode: Text.Wrap
        }
    }
}
