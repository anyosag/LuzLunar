import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

import SfSymbols 1.0 // [fork]
import WindowChrome 1.0 // [fork]

ToolButton {
    property string iconSource
    // [fork] SF Symbol name, drawn through the image://sfsymbol provider (icon.name can't reach
    // SF Symbols); iconSource is the fallback, e.g. for Discord, which has no symbol
    property string symbolName

    activeFocusOnTab: true

    // [fork] While the native toolbar shows these buttons, VoiceOver should only announce those
    Accessible.ignored: WindowChrome.active

    // [fork] Toolbar-sized, tinted icons for the native macOS style
    // (upstream sizes the icon to the Material background for TV readability)
    icon.source: SfSymbols.available && symbolName !== "" ? SfSymbols.url(symbolName) : iconSource
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
