import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import AspectRatios 1.0

// A stream size typed in, for the "Custom" entry of Settings' resolution list and the stream
// profile dialog's "Custom…". Open it with openFor(). When it's accepted, chosenWidth and
// chosenHeight are the size to use.
NavigableDialog {
    id: customResolutionDialog

    // The aspect ratio "Keep aspect ratio" holds, set by openFor()
    property real keptRatio: 0

    // The size to use once accepted: what was typed, made even
    readonly property var chosen: AspectRatios.normalize(parseInt(widthField.text), parseInt(heightField.text))
    readonly property int chosenWidth: chosen.width
    readonly property int chosenHeight: chosen.height

    // Both sizes are within 256 to 8192
    readonly property bool inputValid: widthField.acceptableInput && heightField.acceptableInput

    title: qsTr("Custom resolution")
    standardButtons: Dialog.Ok | Dialog.Cancel

    // width and height are the starting size. ratio is the aspect ratio to hold (the picker's
    // chosen one), or 0 for the starting size's own.
    function openFor(width, height, ratio) {
        keptRatio = ratio > 0 ? ratio : (height > 0 ? width / height : 16 / 9)
        widthField.text = "" + width
        heightField.text = "" + height
        keepAspectBox.checked = true
        open()
    }

    function updateOkButton() {
        if (standardButton(Dialog.Ok)) {
            standardButton(Dialog.Ok).enabled = inputValid
        }
    }

    onInputValidChanged: updateOkButton()

    onOpened: {
        // Force keyboard focus on the textbox so keyboard navigation works
        widthField.forceActiveFocus()
        widthField.selectAll()
        updateOkButton()
    }

    // Accepts with the Return key, unless the sizes are out of range
    function acceptIfValid() {
        if (inputValid) {
            accept()
        }
    }

    ColumnLayout {
        spacing: 10

        Label {
            Layout.maximumWidth: 320
            text: qsTr("Apollo creates a virtual display at exactly this size, so any width and height from 256 to 8192 works, in any aspect ratio. Sizes that your Mac or the PC can't handle may cause streaming errors.")
            font.pointSize: 9
            wrapMode: Label.WordWrap
        }

        RowLayout {
            spacing: 8

            TextField {
                id: widthField
                Layout.preferredWidth: 90
                maximumLength: 4
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 256; top: 8192 }
                color: acceptableInput || !text ? palette.text : "#FF453A"
                focus: true

                // textEdited only follows typing, so the other field's update doesn't loop back
                onTextEdited: {
                    if (keepAspectBox.checked && acceptableInput) {
                        var linked = AspectRatios.linkedHeight(parseInt(text), customResolutionDialog.keptRatio)
                        if (linked > 0) {
                            heightField.text = "" + linked
                        }
                    }
                }

                Keys.onReturnPressed: customResolutionDialog.acceptIfValid()
                Keys.onEnterPressed: customResolutionDialog.acceptIfValid()
            }

            Label {
                text: "×"
                font.bold: true
            }

            TextField {
                id: heightField
                Layout.preferredWidth: 90
                maximumLength: 4
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 256; top: 8192 }
                color: acceptableInput || !text ? palette.text : "#FF453A"

                onTextEdited: {
                    if (keepAspectBox.checked && acceptableInput) {
                        var linked = AspectRatios.linkedWidth(parseInt(text), customResolutionDialog.keptRatio)
                        if (linked > 0) {
                            widthField.text = "" + linked
                        }
                    }
                }

                Keys.onReturnPressed: customResolutionDialog.acceptIfValid()
                Keys.onEnterPressed: customResolutionDialog.acceptIfValid()
            }
        }

        CheckBox {
            id: keepAspectBox
            text: qsTr("Keep aspect ratio")
            checked: true
        }

        // The ratio of what's typed, like "3440 × 1440 · 21:9". Both lines keep their place when
        // empty, so the dialog doesn't change size while typing.
        Label {
            Layout.maximumWidth: 320
            text: customResolutionDialog.inputValid ?
                      qsTr("%1 × %2 · %3").arg(parseInt(widthField.text)).arg(parseInt(heightField.text))
                          .arg(AspectRatios.ratioLabel(parseInt(widthField.text), parseInt(heightField.text))) : "\u00a0"
            font.bold: true
            wrapMode: Label.WordWrap
        }

        // Odd sizes are rounded down when accepted
        Label {
            Layout.maximumWidth: 320
            text: customResolutionDialog.inputValid && customResolutionDialog.chosen.rounded ?
                      qsTr("Sizes must be even, so %1 × %2 will be used.").arg(customResolutionDialog.chosenWidth).arg(customResolutionDialog.chosenHeight) : "\u00a0"
            font.pointSize: 9
            wrapMode: Label.WordWrap
        }
    }
}
