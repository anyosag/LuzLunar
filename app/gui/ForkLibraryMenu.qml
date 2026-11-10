import QtQuick
import QtQuick.Effects

import ForkTheme 1.0

// [fork] An app's menu on the All apps page (the design's 248 wide panel): the first row is always
// the blue default, the rest plain; disabled rows are faded and do nothing. Up and Down move the
// blue row for the keyboard, Return does it and Escape closes the menu.
//
// items: [{label, icon, filled (bool), hi, key, check, checked, disabled, danger} | {sep: true}]
FocusScope {
    id: menu

    property string appName: ""
    property var items: []
    property int current: 0 // the blue row (an index into the actions, separators excluded)
    signal triggered(int index)
    signal closeRequested()

    readonly property var actions: items.filter(function(item) { return !item.sep })
    readonly property real contentHeight: {
        var h = 2 + 12
        for (var i = 0; i < items.length; i++) {
            h += items[i].sep ? 11 : 30
        }
        return h
    }

    width: 248
    height: contentHeight
    Accessible.role: Accessible.PopupMenu
    Accessible.name: appName

    function move(by) {
        var n = actions.length
        for (var step = 1; step <= n; step++) {
            var i = (current + by * step + n * step) % n
            if (!actions[i].disabled) {
                current = i
                return
            }
        }
    }

    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onEscapePressed: closeRequested()
    Keys.onReturnPressed: {
        if (actions[current] && !actions[current].disabled) {
            triggered(current)
        }
    }
    Keys.onEnterPressed: Keys.returnPressed(event)

    // The shadow, then the panel
    RectangularShadow {
        anchors.fill: parent
        radius: 12
        offset: Qt.vector2d(0, 18)
        blur: 50
        color: ForkTheme.dark ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(20 / 255, 22 / 255, 40 / 255, 0.2)
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: ForkTheme.cv.menu
        border.width: 1
        border.color: ForkTheme.cv.lineStrong

        Column {
            x: 7
            y: 7
            width: parent.width - 14

            Repeater {
                model: menu.items

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property int actionIndex: {
                        var n = 0
                        for (var i = 0; i < index; i++) {
                            if (!menu.items[i].sep) {
                                n++
                            }
                        }
                        return n
                    }
                    readonly property bool hi: !modelData.sep && actionIndex === menu.current
                    readonly property color ink: hi ? "#FFFFFF" : modelData.danger ? ForkTheme.st.red : ForkTheme.cv.text
                    readonly property color iconInk: hi ? "#FFFFFF" : modelData.danger ? ForkTheme.st.red : ForkTheme.cv.muted

                    width: parent.width
                    height: modelData.sep ? 11 : 30

                    Rectangle {
                        visible: !!row.modelData.sep
                        x: 10
                        y: 5
                        width: parent.width - 20
                        height: 1
                        color: ForkTheme.cv.line
                    }

                    Rectangle {
                        visible: !row.modelData.sep
                        anchors.fill: parent
                        radius: 7
                        color: row.hi ? ForkTheme.cv.menuHi : "transparent"
                        opacity: row.modelData.disabled ? 0.4 : 1

                        ForkLibraryIcon {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            name: row.modelData.icon || ""
                            size: 16
                            color: row.iconInk
                            strokeWidth: 1.8
                            filled: row.modelData.filled ? 1 : 0
                        }

                        ForkCanvasText {
                            x: 36
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 36 - 10 - (row.modelData.check && row.modelData.checked ? 24 : 0) - (row.modelData.key ? 22 : 0)
                            text: row.modelData.label || ""
                            elide: Text.ElideRight
                            color: row.ink
                            px: 13
                        }

                        ForkLibraryIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width - 10 - 14 - (row.modelData.key ? 22 : 0)
                            visible: !!(row.modelData.check && row.modelData.checked)
                            name: "check"
                            size: 14
                            color: row.ink
                        }

                        ForkCanvasText {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width - 10 - width
                            visible: !!row.modelData.key
                            text: row.modelData.key || ""
                            opacity: 0.7
                            color: row.ink
                            px: 12
                        }

                        Accessible.role: row.modelData.check ? Accessible.CheckBox : Accessible.MenuItem
                        Accessible.name: row.modelData.label || ""
                        Accessible.checked: !!row.modelData.checked
                        Accessible.onPressAction: if (!row.modelData.disabled) menu.triggered(row.actionIndex)

                        MouseArea {
                            anchors.fill: parent
                            enabled: !row.modelData.disabled
                            onClicked: menu.triggered(row.actionIndex)
                        }
                    }
                }
            }
        }
    }
}
