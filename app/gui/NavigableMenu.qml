import QtQuick
import QtQuick.Controls // [fork] versionless, for popupType (Qt 6.8)

import ForkTheme 1.0 // [fork]

Menu {
    property var initiator

    // [fork] Keep menus in the main window (Popup.Item). Gamepad navigation sends its key events
    // to the main window, so a menu in its own window (Popup.Window) or a native one wouldn't get them.
    popupType: Popup.Item

    // [fork] A rounded panel in the theme, with the design's shadow
    padding: 6
    background: ForkPopupBackground {
        implicitWidth: 230
        implicitHeight: 40
    }

    onOpened: {
        // If the initiating object currently has keyboard focus,
        // give focus to the first visible and enabled menu item
        if (initiator.focus) {
            for (var i = 0; i < count; i++) {
                var item = itemAt(i)
                if (item.visible && item.enabled) {
                    item.forceActiveFocus(Qt.TabFocusReason)
                    break
                }
            }
        }
    }
}
