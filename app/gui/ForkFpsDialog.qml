import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// [fork] A frame rate typed in, for Settings › Display's "Custom…". Open it with openFor();
// when it's accepted, chosenFps is the rate to use.
NavigableDialog {
    id: fpsDialog

    readonly property int chosenFps: parseInt(fpsField.text)

    title: qsTr("Custom frame rate")
    standardButtons: Dialog.Ok | Dialog.Cancel

    function openFor(fps) {
        fpsField.text = "" + fps
        open()
    }

    function updateOkButton() {
        if (standardButton(Dialog.Ok)) {
            standardButton(Dialog.Ok).enabled = fpsField.acceptableInput
        }
    }

    onOpened: {
        // Force keyboard focus on the textbox so keyboard navigation works
        fpsField.forceActiveFocus()
        fpsField.selectAll()
        updateOkButton()
    }

    ColumnLayout {
        spacing: 10

        Label {
            text: qsTr("Enter a custom frame rate:")
            font.bold: true
        }

        ForkTextField {
            id: fpsField
            Layout.preferredWidth: 120
            maximumLength: 4
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 10; top: 9999 }

            onTextChanged: fpsDialog.updateOkButton()
            Keys.onReturnPressed: {
                if (acceptableInput) {
                    fpsDialog.accept()
                }
            }
            Keys.onEnterPressed: {
                if (acceptableInput) {
                    fpsDialog.accept()
                }
            }
        }
    }
}
