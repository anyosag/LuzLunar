import QtQuick 2.0
import QtQuick.Controls 2.2

import ForkTheme 1.0 // [fork]

MenuItem {
    id: menuItem // [fork]

    // [fork] An SF Symbol before the text, and red text for an item that removes or quits something
    property string symbol: ""
    property bool destructive: false

    // [fork] The redesign's look: the symbol in an 18 pt slot and the text, a check mark on the
    // right when a checkable item is on (instead of the style's check box), and a raised row
    // under the pointer or keyboard
    leftPadding: 10
    rightPadding: 10
    font.pixelSize: 14
    indicator: Item {}

    contentItem: Item {
        implicitWidth: itemRow.implicitWidth + (menuItem.checkable ? 30 : 0)
        implicitHeight: Math.max(itemRow.implicitHeight, 22)

        readonly property color tint: menuItem.destructive ? ForkTheme.danger
                                    : menuItem.enabled ? ForkTheme.text : ForkTheme.faint

        Row {
            id: itemRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: menuItem.symbol !== ""
                width: 18
                height: 18

                ForkSymbol {
                    anchors.centerIn: parent
                    symbol: menuItem.symbol
                    size: 16
                    color: menuItem.destructive ? ForkTheme.danger : ForkTheme.muted
                    opacity: menuItem.enabled ? 1 : 0.6
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: menuItem.text
                textFormat: Text.PlainText
                font: menuItem.font
                color: parent.parent.tint
            }
        }

        ForkSymbol {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: menuItem.checkable && menuItem.checked
            symbol: "checkmark"
            size: 13
            color: ForkTheme.accentInk
        }
    }

    background: Rectangle {
        implicitWidth: 230
        implicitHeight: 40
        radius: 8
        color: menuItem.highlighted && menuItem.enabled ? ForkTheme.raised : "transparent"
    }

    // Ensure focus can't be given to an invisible item
    enabled: visible
    height: visible ? implicitHeight : 0
    focusPolicy: visible ? Qt.TabFocus : Qt.NoFocus

    onTriggered: {
        // We must close the context menu first or
        // it can steal focus from any dialogs that
        // onTriggered may spawn.
        menu.close()
    }

    Keys.onReturnPressed: {
        triggered()
    }

    Keys.onEnterPressed: {
        triggered()
    }

    Keys.onEscapePressed: {
        menu.close()
    }
}
