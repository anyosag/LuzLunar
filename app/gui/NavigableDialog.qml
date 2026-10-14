import QtQuick 2.0
import QtQuick.Controls 2.5

Dialog {
    id: navigableDialog // [fork]
    modal: true
    anchors.centerIn: Overlay.overlay

    // [fork] A rounded panel with a shadow instead of the native macOS style's plain frame
    background: ForkDialogBackground {
        dialog: navigableDialog
    }
    padding: 20

    // [fork] The native style's title and button rows paint their own square-cornered panels,
    // which cover the rounded background's corners
    Component.onCompleted: {
        if (header && header.background) {
            header.background.visible = false
        }
        if (footer && footer.background) {
            footer.background.visible = false
        }
    }

    onClosed: {
        // We must force focus back to the last item. If we don't,
        // gamepad and keyboard navigation will break after a
        // dialog appears.
        stackView.forceActiveFocus()
    }
}
