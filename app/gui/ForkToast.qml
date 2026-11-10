import QtQuick
import QtQuick.Effects

import ForkTheme 1.0

// [fork] The canvas's toast (carousel.md §7): one pill at a time, 36 high, with a short line of
// text, that shows and hides at once. main.qml puts it in the overlay, 54 above the window's bottom
// (18 above the footer), and exposes it as window.forkToast(text, ms). A new toast replaces the one
// showing and restarts the timer; ms (default 2200) is how long it stays.
Item {
    id: toasts

    property string text: ""
    readonly property bool showing: text !== ""

    implicitWidth: pill.width
    implicitHeight: pill.height
    width: implicitWidth
    height: implicitHeight
    visible: showing

    function show(message, ms) {
        if (message === "" || message === undefined) {
            return
        }
        text = message
        hideTimer.interval = ms !== undefined && ms > 0 ? ms : 2200
        hideTimer.restart()
    }

    function hide() {
        hideTimer.stop()
        text = ""
    }

    Timer {
        id: hideTimer
        interval: 2200
        onTriggered: toasts.text = ""
    }

    Accessible.role: Accessible.AlertMessage
    Accessible.name: text

    Rectangle {
        id: pill
        // At most the window's width less a gutter; the line never wraps (it elides)
        width: Math.min(label.implicitWidth + 36, toasts.parent ? toasts.parent.width - 32 : 520)
        height: 36
        radius: 18
        color: ForkTheme.dark ? "#F2F3F7" : "#1D1D1F"
        visible: false

        ForkCanvasText {
            id: label
            anchors.centerIn: parent
            width: pill.width - 36
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: toasts.text
            px: 13
            weight: Font.DemiBold
            color: ForkTheme.dark ? "#0D0F17" : "#FFFFFF"
        }
    }

    // 0 10px 30px rgba(0,0,0,0.3) under the pill
    MultiEffect {
        anchors.fill: pill
        source: pill
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.3
        shadowBlur: 1.0
        shadowVerticalOffset: 10
    }
}
