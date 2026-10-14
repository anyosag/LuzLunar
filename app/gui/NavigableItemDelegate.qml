import QtQuick 2.15
import QtQuick.Templates 2.15 as T

// [fork] A rounded card in the system colors instead of Material's ItemDelegate. Built on the
// Templates base because the native macOS style can't be customized.
T.ItemDelegate {
    id: delegate

    property GridView grid
    // Views with rounded artwork set this to the artwork's radius plus its inset, so the corners nest
    property real cornerRadius: 14

    hoverEnabled: true
    highlighted: grid.activeFocus && grid.currentItem === this

    background: Rectangle {
        radius: delegate.cornerRadius
        color: {
            var tint = delegate.highlighted ? delegate.palette.highlight : delegate.palette.windowText
            var alpha = delegate.highlighted ? 0.22 : (delegate.down ? 0.14 : (delegate.hovered ? 0.07 : 0.0))
            return Qt.rgba(tint.r, tint.g, tint.b, alpha)
        }
        border.width: delegate.visualFocus || delegate.highlighted ? 2 : 0
        border.color: delegate.palette.highlight

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    Keys.onLeftPressed: {
        grid.moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        grid.moveCurrentIndexRight()
    }
    Keys.onDownPressed: {
        grid.moveCurrentIndexDown()
    }
    Keys.onUpPressed: {
        grid.moveCurrentIndexUp()

        // If we've reached the top of the grid, move focus to the toolbar
        if (grid.currentItem === this) {
            nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }
    }
    Keys.onReturnPressed: {
        clicked()
    }
    Keys.onEnterPressed: {
        clicked()
    }
}
