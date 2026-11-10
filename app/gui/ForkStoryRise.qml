// [fork] A part of the Your PCs heading that rises in once: it starts `dy` below and invisible, and
// after `delay` ms fades in over 500 ms (ease) while moving up over 640 ms (the standard curve).
// carousel.md §2.4. With `active` already true at creation, or Reduce Motion, it shows at once.
import QtQuick
import ForkTheme

Item {
    id: rise

    property bool active: false
    property int delay: 0
    property real dy: 8
    default property alias content: holder.data

    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height

    Item {
        id: holder
        y: rise.dy
        opacity: 0
        width: parent.width
        height: parent.height
    }

    readonly property bool _instant: ForkTheme.reduceMotion

    function _show() {
        if (_instant) {
            anim.stop()
            holder.opacity = 1
            holder.y = 0
        } else {
            anim.restart()
        }
    }
    onActiveChanged: if (active) _show()
    Component.onCompleted: if (active) _show()

    SequentialAnimation {
        id: anim
        PauseAnimation { duration: rise.delay }
        ParallelAnimation {
            NumberAnimation {
                target: holder; property: "opacity"; from: 0; to: 1; duration: 500
                easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1]
            }
            NumberAnimation {
                target: holder; property: "y"; from: rise.dy; to: 0; duration: 640
                easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1]
            }
        }
    }
}
