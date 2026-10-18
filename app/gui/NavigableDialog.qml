import QtQuick 2.0
import QtQuick.Controls 2.5

import ForkTheme 1.0 // [fork]

Dialog {
    id: navigableDialog // [fork]
    modal: true
    anchors.centerIn: Overlay.overlay

    // [fork] Set for a dialog whose confirming button removes or quits something: that button is
    // red (danger) instead of gold
    property bool destructive: false

    // [fork] A rounded panel with a shadow instead of the native macOS style's plain frame, over
    // the design's scrim
    background: ForkDialogBackground {
        dialog: navigableDialog
    }
    padding: 24
    topPadding: title !== "" ? 16 : 24
    spacing: 0
    Overlay.modal: Rectangle {
        color: ForkTheme.scrim
    }

    // [fork] The title and buttons in LuzLunar's look, instead of the style's rows
    header: Label {
        text: navigableDialog.title
        visible: text !== ""
        textFormat: Text.PlainText // a title can hold an app name from the host
        font.family: ForkTheme.uiFamily
        font.pixelSize: 24
        font.bold: true
        font.letterSpacing: -0.24
        color: ForkTheme.text
        elide: Label.ElideRight
        padding: 24
        bottomPadding: 0
    }

    footer: DialogButtonBox {
        visible: count > 0
        alignment: Qt.AlignRight
        buttonLayout: DialogButtonBox.MacLayout // Cancel, then the confirming button at the right
        spacing: 8
        padding: 24
        topPadding: 4
        background: Item {}

        delegate: ForkButton {
            kind: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole || DialogButtonBox.buttonRole === DialogButtonBox.YesRole
                  ? (navigableDialog.destructive ? "danger" : "primary") : "default"
            implicitWidth: Math.max(88, implicitContentWidth + leftPadding + rightPadding)

            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
        }
    }

    // [fork] The native style's title and button rows paint their own square-cornered panels,
    // which cover the rounded background's corners
    Component.onCompleted: {
        if (header && header.background) {
            header.background.visible = false
        }
        if (footer && footer.background) {
            footer.background.visible = false
        }

        // [fork] The style's title row is a Label, and a title can hold an app name from the host
        if (header && header.textFormat !== undefined) {
            header.textFormat = Text.PlainText
        }
    }

    onClosed: {
        // We must force focus back to the last item. If we don't,
        // gamepad and keyboard navigation will break after a
        // dialog appears.
        stackView.forceActiveFocus()
    }
}
