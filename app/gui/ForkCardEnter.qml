import QtQuick

// [fork] Wraps a part of a card for the first-open entrance: hidden (opacity 0, 12 px down) until
// `shown`, then it fades in over 360 ms and rises over 480 ms after `delay`. Once `revealed` there
// is no transition at all. Sizes itself to its content.
Item {
    id: enter

    property bool shown: true
    property bool revealed: true
    property int delay: 0
    default property alias content: holder.data

    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height
    width: implicitWidth
    height: implicitHeight

    opacity: shown ? 1 : 0
    Behavior on opacity {
        enabled: !enter.revealed
        SequentialAnimation {
            PauseAnimation { duration: enter.delay }
            NumberAnimation { duration: 360; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
        }
    }

    Item {
        id: holder
        y: enter.shown ? 0 : 12
        Behavior on y {
            enabled: !enter.revealed
            SequentialAnimation {
                PauseAnimation { duration: enter.delay }
                NumberAnimation { duration: 480; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
            }
        }
    }
}
