import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

ToolButton {
    property string iconSource
    // [fork] SF Symbol name, used on macOS through the system icon theme; iconSource is the fallback
    property string symbolName

    activeFocusOnTab: true

    // [fork] Toolbar-sized, tinted icons for the native macOS style
    // (upstream sizes the icon to the Material background for TV readability)
    icon.name: symbolName
    icon.source: iconSource
    icon.width: 20
    icon.height: 20
    icon.color: palette.buttonText
    display: AbstractButton.IconOnly

    Layout.preferredHeight: 34
    Layout.preferredWidth: 38

    Keys.onReturnPressed: {
        clicked()
    }

    Keys.onEnterPressed: {
        clicked()
    }

    Keys.onRightPressed: {
        nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
    }

    Keys.onLeftPressed: {
        nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
    }
}
