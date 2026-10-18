import QtQuick

import ForkTheme 1.0

// [fork] Short confirmations at the bottom of the window ("Renamed to Office PC"). main.qml puts
// one in the overlay and exposes it as window.forkToast(text). Each toast rises in, stays a few
// seconds and goes; several stack with the newest at the bottom.
Column {
    id: toasts

    spacing: 8

    function show(text) {
        if (text === "") {
            return
        }
        toastModel.append({ "text": text })
        if (toastModel.count > 3) {
            toastModel.remove(0)
        }
    }

    ListModel {
        id: toastModel
    }

    Repeater {
        model: toastModel

        delegate: Rectangle {
            id: toast
            required property int index
            required property string text

            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(toastText.implicitWidth + 32, toasts.parent ? toasts.parent.width - 32 : 520)
            height: toastText.implicitHeight + 20
            radius: 12
            color: ForkTheme.toastBg

            Accessible.role: Accessible.AlertMessage
            Accessible.name: text

            Text {
                id: toastText
                anchors.centerIn: parent
                width: parent.width - 32
                text: toast.text
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: ForkTheme.uiFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                color: ForkTheme.toastText
            }

            // Rises 8 pt as it fades in
            opacity: 0
            transform: Translate { id: rise; y: ForkTheme.reduceMotion ? 0 : 8 }
            Component.onCompleted: appear.start()
            ParallelAnimation {
                id: appear
                NumberAnimation { target: toast; property: "opacity"; to: 1; duration: ForkTheme.reduceMotion ? 0 : 250; easing.type: Easing.OutCubic }
                NumberAnimation { target: rise; property: "y"; to: 0; duration: ForkTheme.reduceMotion ? 0 : 250; easing.type: Easing.OutCubic }
            }

            Timer {
                running: true
                interval: 3600
                onTriggered: toastModel.remove(toast.index)
            }
        }
    }
}
