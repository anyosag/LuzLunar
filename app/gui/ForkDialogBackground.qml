import QtQuick
import QtQuick.Effects

// [fork] The panel behind dialogs on macOS: rounded, with a hairline border and a soft shadow, in
// the system colors. NavigableDialog uses it as its background.
Rectangle {
    property var dialog

    radius: 16
    color: dialog.palette.window
    border.width: 1
    border.color: Qt.rgba(dialog.palette.windowText.r, dialog.palette.windowText.g, dialog.palette.windowText.b, 0.14)

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.35)
        shadowBlur: 1.0
        shadowVerticalOffset: 8
    }
}
