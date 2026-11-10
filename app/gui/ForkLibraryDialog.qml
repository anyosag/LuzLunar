import QtQuick
import QtQuick.Controls
import QtQuick.Effects

import ForkTheme 1.0

// [fork] The All apps page's alert (quit the running app, or quit it to start another): a 300 wide
// box centered in the window over a scrim, with the app's art, a title, a sentence and stacked
// buttons, the confirming one first. Escape and the Cancel button close it.
Popup {
    id: dialog

    property string title: ""
    property string body: ""
    property string confirmText: ""
    property color confirmFill: "#D93A33"
    // The app the alert is about: its box art (or a drawn cover when it has none)
    property string appName: ""
    property string boxart: ""
    property string colorKey: ""
    property color skyColor: "#17163F"
    signal confirmed()

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    padding: 0
    width: 300
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle {
        color: ForkTheme.dark ? Qt.rgba(5 / 255, 7 / 255, 15 / 255, 0.45) : Qt.rgba(30 / 255, 32 / 255, 48 / 255, 0.18)
    }

    enter: Transition {}
    exit: Transition {}

    background: Item {
        RectangularShadow {
            anchors.fill: parent
            radius: 16
            offset: Qt.vector2d(0, 24)
            blur: 70
            color: ForkTheme.dark ? Qt.rgba(0, 0, 0, 0.65) : Qt.rgba(20 / 255, 22 / 255, 40 / 255, 0.25)
        }
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: ForkTheme.cv.menu
            border.width: 1
            border.color: ForkTheme.cv.lineStrong
        }
    }

    contentItem: Column {
        Accessible.role: Accessible.AlertMessage
        Accessible.name: dialog.title
        Accessible.description: dialog.body
        topPadding: 22
        bottomPadding: 16
        leftPadding: 16
        rightPadding: 16
        spacing: 8

        // The app's art, 54 × 72
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 54
            height: 72 + 6

            RectangularShadow {
                x: 0; y: 0; width: 54; height: 72
                radius: 9
                offset: Qt.vector2d(0, 8)
                blur: 18
                color: Qt.rgba(0, 0, 0, 0.35)
            }

            Item {
                id: art
                width: 54
                height: 72
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Rectangle { anchors.fill: parent; color: dialog.skyColor }
                ForkAppCover {
                    anchors.fill: parent
                    visible: image.status !== Image.Ready || image.isPlaceholder
                    kind: "dialog"
                    name: dialog.appName
                    colorKey: dialog.colorKey
                    radius: 0
                }
                Image {
                    id: image
                    property bool isPlaceholder: sourceSize.width === 200 && sourceSize.height === 266
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: dialog.boxart
                    opacity: isPlaceholder ? 0 : 1
                }
            }

            Rectangle {
                id: artMask
                width: 54; height: 72; radius: 9
                visible: false
                layer.enabled: true
            }
        }

        ForkCanvasText {
            width: 268
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: dialog.title
            color: ForkTheme.cv.text
            px: 14.5
            weight: 700
            lineHeightPx: 19
        }

        ForkCanvasText {
            width: 268
            bottomPadding: 8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: dialog.body
            color: ForkTheme.cv.text2
            px: 12.5
            lineHeightPx: 17
        }

        ForkLibraryButton {
            width: 268
            implicitHeight: 34
            height: 34
            stretch: true
            radius: 9
            fontSize: 13
            fontWeight: 600
            text: dialog.confirmText
            fill: dialog.confirmFill
            ink: "#FFFFFF"
            onClicked: {
                dialog.close()
                dialog.confirmed()
            }
        }

        ForkLibraryButton {
            width: 268
            height: 34
            stretch: true
            radius: 9
            fontSize: 13
            fontWeight: 600
            text: qsTr("Cancel")
            fill: ForkTheme.cv.chip
            ink: ForkTheme.cv.text
            borderColor: ForkTheme.cv.line
            borderWidth: 1
            onClicked: dialog.close()
        }
    }
}
