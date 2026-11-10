// [fork] The Your PCs stage (carousel.md §3, §4): the PCs and the Add a PC card as 560 x 540 cards,
// the focused one in the middle at full size and its neighbours turned toward it, smaller and dimmed;
// the row loops. In the grid view every card is shown at 276 wide in rows. Prev/next arrows sit at
// the edges. This item holds the geometry; the page owns the state (focused slot, direction,
// hover, settled/revealed) and the card (`pcCard`, `addCard`: Components with `property var m`
// (the model row) and `property var slot`).
import QtQuick
import ForkTheme

Item {
    id: stageRoot

    property var pcModel: null
    property Component pcCard
    property Component addCard

    property int index: 0
    property int prevIndex: -1
    property int dir: 0
    property int prevDir: 0
    property int hoverIndex: -1
    property string view: "carousel"
    property bool settled: true
    property bool revealed: true
    property bool animate: !ForkTheme.reduceMotion
    // Keyboard focus is on the page: a ring around the focused card (the app's gold, not the PC's)
    property bool keyFocusRing: false
    // More than two rows of cards in the grid scroll with the wheel
    property real gridScroll: 0
    readonly property int gridRows: Math.ceil(n / gridCols)
    readonly property real gridContent: 10 + gridRows * 266.14 + (gridRows - 1) * 16
    readonly property real gridMax: Math.max(0, gridContent - height + 6)
    clip: grid && gridMax > 0

    readonly property int pcCount: pcRepeater.count
    readonly property int n: pcCount + 1
    readonly property bool loop: n > 2
    readonly property bool grid: view === "grid"
    readonly property real cw: 560
    readonly property real ch: 540
    readonly property real side: 0.58

    // Counts up when cards are made or removed, so bindings that read the rows refresh
    property int itemsRevision: 0

    signal pick(int slot)
    signal step(int delta)

    height: 556

    function offsetOf(i, at, d) {
        if (!loop) return i - at
        var off = (((i - at) % n) + n) % n
        if (off > n / 2 || (off === n / 2 && d > 0)) off -= n
        return off
    }

    readonly property int gridCols: Math.max(1, Math.floor((width - 128 + 16) / 292))
    readonly property real gridLeft: (width - (gridCols * 292 - 16)) / 2

    // Where slot i is, and how it looks, now
    function targetOf(i, hovered) {
        var off = offsetOf(i, index, dir)
        var a = Math.abs(off)
        var focused = off === 0
        var isAdd = i === pcCount
        var jump = loop && !grid && prevIndex >= 0 && Math.abs(off - offsetOf(i, prevIndex, prevDir)) > 1
        var cx, cy, s, o, z, sat = 1, rot = 0, lift = 0
        if (grid) {
            s = 276 / cw
            var col = i % gridCols
            var row = Math.floor(i / gridCols)
            cx = gridLeft + col * 292 + 138
            cy = 10 + row * (ch * s + 16) + (ch * s) / 2 - gridScroll
            o = 1
            z = focused ? 5 : 1
            lift = hovered ? -4 : 0
        } else {
            s = a === 0 ? 1 : (a === 1 ? side : 0.5)
            var near = cw / 2 + 26 + (cw * side) / 2
            var c = a === 0 ? 0 : (a === 1 ? near : near + 320 * (a - 1))
            cx = width / 2 + (off < 0 ? -c : c)
            cy = 8 + ch / 2
            o = a === 0 ? 1 : (a === 1 ? 0.5 : 0)
            sat = a === 0 ? 1 : 0.55
            z = 10 - a
            rot = off === 0 ? 0 : (off < 0 ? 14 : -14)
            if (isAdd && o > 0) {
                o = Math.max(o, 0.8)
                sat = 1
            }
            if (hovered && o > 0) {
                if (focused) lift = -6
                else o = Math.min(1, o + 0.2)
            }
        }
        return { x: cx - cw / 2, y: cy - ch / 2 + lift, s: s, o: o, rot: rot, sat: sat, z: z,
                 focused: focused, jump: jump, cx: cx, cy: cy, off: off }
    }

    // The place and size of the focused card, for the menu and the All apps origin (no hover lift)
    function geoOf(i) {
        var t = targetOf(i, false)
        return { cx: t.cx, cy: t.cy, s: t.s }
    }

    function slotAt(i) {
        return i === pcCount ? addSlot : pcRepeater.itemAt(i)
    }

    // Keeps the focused card in view in the grid
    onIndexChanged: {
        if (!grid || gridMax <= 0) return
        var top = 10 + Math.floor(index / gridCols) * (ch * 276 / cw + 16)
        var h = ch * 276 / cw
        if (top - gridScroll < 6) gridScroll = Math.max(0, top - 10)
        else if (top + h - gridScroll > height - 6) gridScroll = Math.min(gridMax, top + h - height + 10)
    }
    onGridChanged: gridScroll = 0
    Behavior on gridScroll { enabled: stageRoot.animate; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    WheelHandler {
        enabled: stageRoot.grid && stageRoot.gridMax > 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            stageRoot.gridScroll = Math.max(0, Math.min(stageRoot.gridMax, stageRoot.gridScroll - event.angleDelta.y / 2))
        }
    }

    Repeater {
        id: pcRepeater
        model: stageRoot.pcModel
        onItemAdded: stageRoot.itemsRevision++
        onItemRemoved: stageRoot.itemsRevision++
        delegate: ForkPcStageSlot {
            required property var model
            required property int index
            stage: stageRoot
            slotIndex: index
            slotName: model.name
            rowModel: model
            sourceComponent: stageRoot.pcCard
        }
    }
    ForkPcStageSlot {
        id: addSlot
        stage: stageRoot
        slotIndex: stageRoot.pcCount
        isAdd: true
        slotName: qsTr("Add a PC")
        sourceComponent: stageRoot.addCard
    }

    // Prev / next arrows (carousel only)
    Repeater {
        model: 2
        delegate: Rectangle {
            id: arrow
            required property int index
            readonly property bool isPrev: index === 0
            readonly property bool disabled: !stageRoot.loop && (isPrev ? stageRoot.index <= 0 : stageRoot.index >= stageRoot.n - 1)
            visible: !stageRoot.grid
            z: 20
            y: 258
            x: isPrev ? 24 : stageRoot.width - 24 - 40
            width: 40; height: 40; radius: 20
            color: ForkTheme.dark ? Qt.rgba(30 / 255, 34 / 255, 48 / 255, 0.92) : Qt.rgba(1, 1, 1, 0.95)
            border.width: 1
            border.color: ForkTheme.cv.line
            opacity: disabled ? 0.35 : 1
            Accessible.role: Accessible.Button
            Accessible.name: isPrev ? qsTr("Previous PC") : qsTr("Next PC")
            Accessible.onPressAction: if (!disabled) stageRoot.step(isPrev ? -1 : 1)

            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.topMargin: 6
                anchors.margins: -5
                radius: 25
                color: ForkTheme.dark ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.05)
            }
            ForkPathIcon {
                anchors.centerIn: parent
                size: 18
                strokeWidth: 2.2
                color: ForkTheme.cv.text
                name: arrow.isPrev ? "chevronLeft" : "chevronRight"
            }
            MouseArea {
                anchors.fill: parent
                enabled: !arrow.disabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: stageRoot.step(arrow.isPrev ? -1 : 1)
            }
        }
    }
}
