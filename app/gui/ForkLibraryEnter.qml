import QtQuick

import ForkTheme 1.0

// [fork] The All apps page's entrance for a part of the band or the title row: it fades in and rises
// 10 points after `delay` ms when `entered` turns on (instantly once `settled`, or with Reduce
// Motion). Give it a size; its children sit inside.
Item {
    id: enter

    property bool entered: true
    property bool settled: true
    property int delay: 0
    default property alias content: holder.data

    opacity: entered ? 1 : 0

    Behavior on opacity {
        enabled: !enter.settled && !ForkTheme.reduceMotion
        SequentialAnimation {
            PauseAnimation { duration: enter.delay }
            NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
        }
    }

    Item {
        id: holder
        width: parent.width
        height: parent.height
        y: enter.entered ? 0 : 10

        Behavior on y {
            enabled: !enter.settled && !ForkTheme.reduceMotion
            SequentialAnimation {
                PauseAnimation { duration: enter.delay }
                NumberAnimation { duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
            }
        }
    }
}
