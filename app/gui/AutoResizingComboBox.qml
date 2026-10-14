import QtQuick 2.9
import QtQuick.Controls // [fork] versionless, for popupType (Qt 6.8)

import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0

// https://stackoverflow.com/questions/45029968/how-do-i-set-the-combobox-width-to-fit-the-largest-item
ComboBox {
    property int textWidth
    // [fork] The native macOS style may have no separate indicator item
    property int desiredWidth : leftPadding + textWidth + (indicator ? indicator.width : 0) + rightPadding
    property int maximumWidth : parent.width

    implicitWidth: desiredWidth < maximumWidth ? desiredWidth : maximumWidth

    // [fork] The macOS style opens the list in its own window, which doesn't get the key events
    // that gamepad navigation sends to the main window. Keep it in-window, like upstream's Material.
    popup.popupType: Popup.Item

    TextMetrics {
        id: popupMetrics
    }

    TextMetrics {
        id: textMetrics
    }

    function recalculateWidth() {
        textMetrics.font = font
        popupMetrics.font = popup.font
        textWidth = 0
        for (var i = 0; i < count; i++){
            textMetrics.text = textAt(i)
            popupMetrics.text = textAt(i)
            textWidth = Math.max(textMetrics.width, textWidth)
            textWidth = Math.max(popupMetrics.width, textWidth)
        }
    }

    // We call this every time the options change (and init)
    // so we can adjust the combo box width here too
    onActivated: recalculateWidth()

    popup.onAboutToShow: {
        // Switch to normal navigation for combo boxes
        SdlGamepadKeyNavigation.setUiNavMode(false)

        // Override the popup color to improve contrast with the overridden
        // Material 2 background color set in main.qml.
        // [fork] Only with the Material style (not on macOS, which uses the native style)
        if (SystemProperties.usesMaterial3Theme && !SystemProperties.isDarwin && popup.background) {
            popup.background.color = "#424242"
        }
    }

    popup.onAboutToHide: {
        SdlGamepadKeyNavigation.setUiNavMode(true)
    }

    Keys.onLeftPressed: {
        decrementCurrentIndex()
    }

    Keys.onRightPressed: {
        incrementCurrentIndex()
    }
}
