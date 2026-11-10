// [fork] "Pick a PC": one chip per PC (and Add a PC) in the PC's own color, the selected one a
// pill, and, in the autoplay demo, a divider and the Pause demo button (carousel.md §3.9, §5).
import QtQuick
import QtQuick.Controls
import ForkTheme

Item {
    id: nav

    // [{ name, dot }]: dot is a color
    property var chips: []
    property int current: 0
    property bool showDemo: false
    property bool demoOn: false
    signal picked(int index)
    signal toggleDemo()
    // A PC chip was dragged from place `from` to place `to` (never the Add a PC chip)
    signal reorder(int from, int to)

    // ---- dragging a chip sideways. dragFrom/dragTo are -1 when idle; after a drop they stay set
    // (dragActive false) until `chips` has the new order, so the chips don't snap back first.
    property int dragFrom: -1
    property int dragTo: -1
    property bool dragActive: false
    property real dragX: 0
    property real _grabDx: 0
    property string _dragName: ""
    // The width this row may use. When every chip with its name doesn't fit, the PC chips that
    // aren't selected shrink to their dot (compact); decided while no drag is going on.
    property real availableWidth: parent ? parent.width - 128 : 1e9
    property var fullWidths: []
    readonly property real fullTotal: {
        var w = 0
        for (var i = 0; i < chips.length; i++) w += (fullWidths[i] || 0) + (i > 0 ? 6 : 0)
        if (showDemo) w += 6 + 13 + 6 + demoBtn.width
        return w
    }
    readonly property bool compactWanted: fullTotal > availableWidth
    property bool compact: false
    onCompactWantedChanged: if (dragFrom < 0) compact = compactWanted
    // Each chip's width, by place (as drawn now)
    property var widths: []
    readonly property int pcChips: Math.max(0, chips.length - 1)
    readonly property real chipsWidth: {
        var w = 0
        for (var i = 0; i < chips.length; i++) w += (widths[i] || 0) + (i > 0 ? 6 : 0)
        return w
    }

    function setFullWidth(i, w) {
        if (fullWidths[i] === w) return
        var a = fullWidths.slice()
        a[i] = w
        fullWidths = a
    }
    function setWidth(i, w) {
        if (widths[i] === w) return
        var a = widths.slice()
        a[i] = w
        widths = a
    }
    function visualIndex(i) {
        if (dragFrom < 0 || dragTo < 0 || i >= pcChips) return i
        if (i === dragFrom) return dragTo
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo) return i - 1
        if (dragTo < dragFrom && i >= dragTo && i < dragFrom) return i + 1
        return i
    }
    // Where the chip at place i sits, with the dragged chip moved to its target place
    function xOf(i) {
        var v = visualIndex(i)
        var x = 0
        for (var j = 0; j < chips.length; j++) {
            if (visualIndex(j) < v) x += (widths[j] || 0) + 6
        }
        return x
    }
    function beginDrag(i, scenePress) {
        if (i < 0 || i >= pcChips) return
        pendingClear.stop()
        var p = chipHost.mapFromItem(null, scenePress.x, scenePress.y)
        _grabDx = p.x - xOf(i)
        _dragName = chips[i].name
        dragFrom = i
        dragTo = i
        dragX = xOf(i)
        dragActive = true
    }
    function moveDrag(i, sceneNow) {
        if (!dragActive || dragFrom !== i) return
        var p = chipHost.mapFromItem(null, sceneNow.x, sceneNow.y)
        var wd = widths[i] || 0
        var last = 0
        for (var j = 0; j < pcChips; j++) last += (widths[j] || 0) + (j > 0 ? 6 : 0)
        dragX = Math.max(0, Math.min(last - wd, p.x - _grabDx))
        // The place whose chips (without the dragged one) are left of the dragged chip's middle
        var mid = dragX + wd / 2
        var pos = 0
        var t = 0
        for (var k = 0; k < pcChips; k++) {
            if (k === i) continue
            var w = widths[k] || 0
            if (mid > pos + w / 2) t++
            pos += w + 6
        }
        dragTo = t
    }
    function endDrag(i) {
        if (!dragActive || dragFrom !== i) return
        dragActive = false
        if (dragTo !== dragFrom) {
            pendingClear.restart()
            reorder(dragFrom, dragTo)
        } else {
            clearDrag()
        }
    }
    function clearDrag() {
        pendingClear.stop()
        dragFrom = -1
        dragTo = -1
        dragActive = false
        compact = compactWanted
    }
    Timer {
        id: pendingClear
        interval: 700
        onTriggered: nav.clearDrag()
    }
    onChipsChanged: {
        if (dragActive || dragFrom < 0) return
        var c = chips[dragTo]
        if (c && c.name === _dragName) clearDrag()
    }

    Component.onCompleted: compact = compactWanted

    implicitHeight: 28
    implicitWidth: chipHost.width
    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Pick a PC")

    Item {
        id: chipHost
        anchors.horizontalCenter: parent.horizontalCenter
        width: nav.chipsWidth + (nav.showDemo ? 6 + 13 + 6 + demoBtn.width : 0)
        height: 28

        Repeater {
            model: nav.chips
            delegate: Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool sel: index === nav.current
                readonly property bool isPc: index < nav.pcChips
                readonly property bool dragging: nav.dragActive && nav.dragFrom === index
                readonly property bool small: nav.compact && isPc && !sel
                readonly property real fullW: 39 + Math.min(label.implicitWidth, 160)
                width: small ? 28 : fullW
                Behavior on width { enabled: !ForkTheme.reduceMotion; NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
                onFullWChanged: nav.setFullWidth(index, fullW)
                height: 28
                radius: 14
                x: dragging ? nav.dragX : nav.xOf(index)
                z: nav.dragFrom === index ? 10 : 0
                color: sel ? ForkTheme.cv.surface : "transparent"
                border.width: 1
                border.color: sel ? ForkTheme.cv.lineStrong : "transparent"
                onWidthChanged: nav.setWidth(index, width)
                Component.onCompleted: { nav.setWidth(index, width); nav.setFullWidth(index, fullW) }
                Behavior on x { enabled: !ForkTheme.reduceMotion && !chip.dragging; NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
                Behavior on color { enabled: !ForkTheme.reduceMotion; ColorAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                Behavior on border.color { enabled: !ForkTheme.reduceMotion; ColorAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }

                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                Accessible.checked: sel
                Accessible.onPressAction: nav.picked(index)

                Row {
                    id: chipRow
                    x: chip.small ? (chip.width - width) / 2 : 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: chip.modelData.dot
                        Accessible.ignored: true
                    }
                    ForkCanvasText {
                        id: label
                        visible: !chip.small
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.name
                        px: 12.5
                        weight: chip.sel ? 600 : 500
                        color: chip.sel ? ForkTheme.cv.text : ForkTheme.cv.muted
                        width: Math.min(implicitWidth, 160)
                        elide: Text.ElideRight
                        Behavior on color { enabled: !ForkTheme.reduceMotion; ColorAnimation { duration: 250 } }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: chip.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    onClicked: nav.picked(chip.index)
                }
                HoverHandler { id: chipHover }
                ToolTip.visible: chip.small && chipHover.hovered && !chip.dragging
                ToolTip.text: modelData.name
                ToolTip.delay: 400
                // Past the drag threshold the chip follows the pointer; a plain click still picks
                DragHandler {
                    target: null
                    enabled: chip.isPc && nav.pcChips > 1
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.ClosedHandCursor
                    onActiveChanged: {
                        if (active) {
                            nav.beginDrag(chip.index, centroid.scenePressPosition)
                            nav.moveDrag(chip.index, centroid.scenePosition)
                        } else {
                            nav.endDrag(chip.index)
                        }
                    }
                    onCentroidChanged: if (active) nav.moveDrag(chip.index, centroid.scenePosition)
                }
            }
        }

        Rectangle {
            visible: nav.showDemo
            x: nav.chipsWidth + 6
            anchors.verticalCenter: parent.verticalCenter
            width: 13; height: 18
            color: "transparent"
            Rectangle { x: 6; width: 1; height: 18; color: ForkTheme.cv.lineStrong }
            Accessible.ignored: true
        }

        Rectangle {
            id: demoBtn
            visible: nav.showDemo
            x: nav.chipsWidth + 6 + 13 + 6
            height: 28
            width: demoRow.width + 22
            radius: 14
            color: ForkTheme.cv.chip
            border.width: 1
            border.color: ForkTheme.cv.line
            Accessible.role: Accessible.CheckBox
            Accessible.name: nav.demoOn ? qsTr("Pause demo") : qsTr("Play demo")
            Accessible.checked: nav.demoOn
            Accessible.onPressAction: nav.toggleDemo()
            Row {
                id: demoRow
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                ForkPathIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: nav.demoOn ? "pause" : "play"
                    size: 14
                    strokeWidth: 2.2
                    filled: !nav.demoOn
                    color: ForkTheme.cv.text2
                }
                ForkCanvasText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: nav.demoOn ? qsTr("Pause demo") : qsTr("Play demo")
                    px: 12.5
                    weight: 500
                    color: ForkTheme.cv.text2
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nav.toggleDemo() }
        }
    }
}
