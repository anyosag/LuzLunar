import QtQuick

import WindowChrome 1.0

// [fork] Shows main.qml's toolbar buttons in a native macOS toolbar, whose buttons are Liquid Glass
// on macOS 26. Clicking a native button clicks its QML button, so each keeps its upstream behavior,
// shortcuts included. The QML button with keyboard focus is highlighted natively. Where the native
// toolbar isn't available, active stays false and the QML toolbar stays.
Item {
    id: root

    property var targetWindow

    // Each entry: { id, button, symbol (SF Symbol name), label, toolTip, visible, navigational, focused,
    // labeled (shows the label beside the symbol) }
    property var items: []

    // Hidden while a stream starts or ends, like the QML toolbar
    property bool shown: true

    property string title: ""
    property string subtitle: ""

    readonly property bool active: WindowChrome.active

    function sync() {
        WindowChrome.setToolbarItems(items.map(function(item) {
            return {
                "id": item.id,
                "symbol": item.symbol,
                "label": item.label,
                "toolTip": item.toolTip || "",
                "visible": item.visible !== false,
                "navigational": item.navigational === true,
                "labeled": item.labeled === true,
                "focused": item.focused === true
            }
        }))
    }

    onItemsChanged: sync()
    onShownChanged: WindowChrome.setToolbarVisible(shown)
    onSubtitleChanged: WindowChrome.setSubtitle(subtitle)

    Component.onCompleted: {
        WindowChrome.setToolbarVisible(shown)
        WindowChrome.setSubtitle(subtitle)
        sync()
        WindowChrome.attach(targetWindow)
    }

    // The window title sits beside the native toolbar's buttons
    Binding {
        target: root.targetWindow
        property: "title"
        value: root.title
        when: root.active
    }

    Connections {
        target: WindowChrome

        function onTriggered(id) {
            for (var i = 0; i < root.items.length; i++) {
                if (root.items[i].id === id) {
                    root.items[i].button.clicked()
                    return
                }
            }
        }
    }
}
