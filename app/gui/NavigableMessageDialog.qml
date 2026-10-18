import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Controls.impl 2.15 // [fork] IconImage
import QtQuick.Layouts 1.2

import ForkTheme 1.0 // [fork]

NavigableDialog {
    id: dialog

    property alias text: dialogLabel.dialogText
    property alias showSpinner: dialogSpinner.visible
    property alias imageSrc: dialogImage.source

    property string helpText
    property string helpUrl : "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"
    property string helpTextSeparator : " "
    // [fork] The design's confirmations have a title and no icon
    property bool forkShowIcon: true

    onOpened: {
        // Force keyboard focus on the label so keyboard navigation works
        if (dialogButtonBox.count > 0) {
            dialogButtonBox.itemAt(dialogButtonBox.count - 1).forceActiveFocus(Qt.TabFocus)
        }
    }

    RowLayout {
        spacing: 10

        ForkBusyIndicator { // [fork] was BusyIndicator
            id: dialogSpinner
            visible: false
            running: visible
        }

        // [fork] Tinted in the text color: the icons are white-only SVGs, invisible in light mode (was Image)
        IconImage {
            id: dialogImage
            color: dialog.palette.windowText
            source: (standardButtons & Dialog.Yes) ?
                        "qrc:/res/baseline-help_outline-24px.svg" :
                        "qrc:/res/baseline-error_outline-24px.svg"
            sourceSize {
                // The icon should be square so use the height as the width too
                width: 50
                height: 50
            }
            visible: !showSpinner && dialog.forkShowIcon // [fork] was !showSpinner
        }

        Label {
            property string dialogText

            id: dialogLabel
            text: dialogText + ((helpText && (standardButtons & Dialog.Help)) ? (helpTextSeparator + helpText) : "")
            textFormat: Text.PlainText // [fork] the text can hold host names and host errors, never markup
            font.pixelSize: 14 // [fork] the design's dialog text
            color: ForkTheme.text2 // [fork]
            lineHeightMode: Text.FixedHeight // [fork]
            lineHeight: 21 // [fork]
            wrapMode: Text.Wrap
            elide: Label.ElideRight

            // Cap the width so the dialog doesn't grow horizontally forever. This
            // will cause word wrap to kick in.
            Layout.maximumWidth: 400
            Layout.maximumHeight: 400
        }
    }

    footer: DialogButtonBox {
        id: dialogButtonBox
        standardButtons: dialog.standardButtons
        alignment: Qt.AlignRight // [fork] the redesign's dialog buttons
        buttonLayout: DialogButtonBox.MacLayout // [fork] Cancel, then the confirming button at the right
        spacing: 8 // [fork]
        padding: 24 // [fork]
        topPadding: 4 // [fork]
        background: Item {} // [fork]

        delegate: ForkButton { // [fork] was Button { flat: true }
            kind: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole || DialogButtonBox.buttonRole === DialogButtonBox.YesRole
                  ? (dialog.destructive ? "danger" : "primary") : "default"
            implicitWidth: Math.max(88, implicitContentWidth + leftPadding + rightPadding)

            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
            Keys.onLeftPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }

        onHelpRequested: {
            Qt.openUrlExternally(helpUrl)
            close()
        }
    }
}
