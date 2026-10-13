import QtQuick 2.0
import QtQuick.Controls 2.5

import SystemProperties 1.0

Dialog {
    id: navigableDialog // [fork]
    modal: true
    anchors.centerIn: Overlay.overlay

    // [fork] On macOS, a rounded panel with a shadow instead of the native style's plain frame
    Component.onCompleted: {
        if (SystemProperties.isDarwin) {
            background = Qt.createComponent("ForkDialogBackground.qml").createObject(navigableDialog, { "dialog": navigableDialog })
            padding = 20
        }
    }

    onClosed: {
        // We must force focus back to the last item. If we don't,
        // gamepad and keyboard navigation will break after a
        // dialog appears.
        stackView.forceActiveFocus()
    }
}
