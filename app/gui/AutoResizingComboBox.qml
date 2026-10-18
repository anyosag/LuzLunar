import QtQuick 2.9
import QtQuick.Controls // [fork] versionless, for popupType (Qt 6.8)

import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import ForkTheme 1.0 // [fork]

// https://stackoverflow.com/questions/45029968/how-do-i-set-the-combobox-width-to-fit-the-largest-item
ComboBox {
    id: comboBox // [fork]
    property int textWidth
    // [fork] The native macOS style may have no separate indicator item
    property int desiredWidth : leftPadding + textWidth + (indicator ? indicator.width : 0) + rightPadding
    property int maximumWidth : parent.width

    implicitWidth: desiredWidth < maximumWidth ? desiredWidth : maximumWidth

    // [fork] The macOS style opens the list in its own window, which doesn't get the key events
    // that gamepad navigation sends to the main window. Keep it in-window, like upstream's Material.
    popup.popupType: Popup.Item

    // [fork] LuzLunar's look (ForkTheme): a rounded field with a chevron, and a rounded list
    // like the menus
    implicitHeight: ForkTheme.controlHeight
    leftPadding: 12
    rightPadding: 36
    hoverEnabled: true
    font.pixelSize: 14

    background: Rectangle {
        radius: ForkTheme.radiusControl
        color: comboBox.down ? ForkTheme.lineSoft : (comboBox.hovered ? ForkTheme.raised : ForkTheme.bar)
        border.width: 1
        border.color: ForkTheme.line

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            visible: comboBox.visualFocus
            radius: ForkTheme.radiusControl + 4
            color: "transparent"
            border.width: 2
            border.color: ForkTheme.selEdge
        }
    }

    contentItem: Text {
        text: comboBox.displayText
        textFormat: Text.PlainText
        font: comboBox.font
        color: ForkTheme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: ForkSymbol {
        x: comboBox.width - width - 12
        y: (comboBox.height - height) / 2
        symbol: "chevron.up.chevron.down"
        size: 12
        color: ForkTheme.muted
    }

    delegate: ItemDelegate {
        id: comboItem
        required property int index

        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: 40
        leftPadding: 10
        rightPadding: 30
        highlighted: comboBox.highlightedIndex === index
        hoverEnabled: true

        contentItem: Text {
            text: comboBox.textAt(comboItem.index)
            textFormat: Text.PlainText
            font: comboBox.font
            color: ForkTheme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        // The chosen item has a check mark; the one under the pointer or keyboard is raised
        background: Rectangle {
            radius: 8
            color: comboItem.highlighted || comboItem.hovered ? ForkTheme.raised : "transparent"

            ForkSymbol {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: comboBox.currentIndex === comboItem.index
                symbol: "checkmark"
                size: 13
                color: ForkTheme.accentInk
            }
        }
    }

    popup.padding: 6
    popup.background: ForkPopupBackground {}

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
