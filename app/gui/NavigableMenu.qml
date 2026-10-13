import QtQuick
import QtQuick.Controls // [fork] versionless, for popupType (Qt 6.8)

Menu {
    property var initiator

    // [fork] The native macOS style defaults to native popup menus, which don't receive the key
    // events that gamepad navigation sends, so keep menus as in-window popups.
    popupType: Popup.Window

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
