// [fork] One card's place on the Your PCs stage (carousel.md §3.3-3.6): a 560 x 540 box that the
// stage moves, scales, turns toward the focused card (perspective 1600) and dims, with the springy
// and standard curves of the canvas. A card that wraps round jumps and only fades. Cards that aren't
// focused are one big "Show <name>" button. The card itself is `sourceComponent`, loaded inside.
import QtQuick
import QtQuick.Effects
import ForkTheme

Item {
    id: slot

    property var stage
    property int slotIndex: 0
    property bool isAdd: false
    property string slotName: ""
    // The PC's row of the model (the delegate's `model`); null for the Add a PC card
    property var rowModel: null
    property Component sourceComponent

    readonly property var tgt: stage ? stage.targetOf(slotIndex, hovered) : ({ x: 0, y: 0, s: 1, o: 1, rot: 0, sat: 1, z: 1, focused: true, jump: false })
    readonly property bool hovered: stage ? stage.hoverIndex === slotIndex : false
    readonly property bool focused: tgt.focused
    readonly property alias card: loader.item

    // What is drawn now (animated towards tgt)
    property real curX: 0
    property real curY: 0
    property real curScale: 1
    property real curAngle: 0
    property real curOpacity: 1
    property real curSat: 1
    property bool jumpNow: true
    property bool focusNow: false
    property bool _ready: false
    readonly property bool _anim: _ready && stage && stage.animate

    function _apply() {
        jumpNow = tgt.jump || !_anim
        focusNow = tgt.focused
        curX = tgt.x
        curY = tgt.y
        curScale = tgt.s
        curAngle = tgt.rot
        curOpacity = tgt.o
        curSat = tgt.sat
    }
    onTgtChanged: _apply()
    Component.onCompleted: {
        _apply()
        _ready = true
    }

    width: 560
    height: 540
    x: curX
    y: curY
    z: tgt.z
    scale: curScale
    transformOrigin: Item.Center
    visible: curOpacity > 0.003
    transform: Rotation {
        origin.x: 280
        origin.y: 270
        axis: Qt.vector3d(0, 1, 0)
        angle: slot.curAngle
        distanceToPlane: 1600
    }

    readonly property var _ease: [0.25, 0.1, 0.25, 1, 1, 1]
    readonly property var _spring: [0.22, 1.22, 0.36, 1, 1, 1]
    readonly property var _standard: [0.2, 0.8, 0.2, 1, 1, 1]

    Behavior on curX { enabled: slot._anim && !slot.jumpNow; NumberAnimation { duration: slot.focusNow ? 640 : 520; easing.type: Easing.Bezier; easing.bezierCurve: slot.focusNow ? slot._spring : slot._standard } }
    Behavior on curY { enabled: slot._anim && !slot.jumpNow; NumberAnimation { duration: slot.focusNow ? 640 : 520; easing.type: Easing.Bezier; easing.bezierCurve: slot.focusNow ? slot._spring : slot._standard } }
    Behavior on curScale { enabled: slot._anim && !slot.jumpNow; NumberAnimation { duration: slot.focusNow ? 640 : 520; easing.type: Easing.Bezier; easing.bezierCurve: slot.focusNow ? slot._spring : slot._standard } }
    Behavior on curAngle { enabled: slot._anim && !slot.jumpNow; NumberAnimation { duration: slot.focusNow ? 640 : 520; easing.type: Easing.Bezier; easing.bezierCurve: slot.focusNow ? slot._spring : slot._standard } }
    Behavior on curOpacity { enabled: slot._anim; NumberAnimation { duration: slot.jumpNow ? 300 : 320; easing.type: Easing.Bezier; easing.bezierCurve: slot._ease } }
    Behavior on curSat { enabled: slot._anim && !slot.jumpNow; NumberAnimation { duration: 320; easing.type: Easing.Bezier; easing.bezierCurve: slot._ease } }

    // One group (a layer with room for the card's shadow and ring around it), so overlapping parts
    // don't show through while dimmed, and saturate(0.55) on the side cards
    Item {
        id: group
        x: -140
        y: -100
        width: 840
        height: 800
        opacity: slot.curOpacity
        layer.enabled: slot.curOpacity < 1 || slot.curSat < 1 || slot.curScale !== 1 || slot.curAngle !== 0
        layer.smooth: true
        layer.mipmap: true
        layer.effect: MultiEffect {
            saturation: slot.curSat - 1
        }

        Loader {
            id: loader
            x: 140
            y: 100
            width: 560
            height: 540
            sourceComponent: slot.sourceComponent
            onLoaded: {
                if (item.hasOwnProperty("m")) item.m = Qt.binding(function () { return slot.rowModel })
                if (item.hasOwnProperty("slot")) item.slot = slot
            }
        }
    }

    // Keyboard focus ring (the app's gold), a little outside the card
    Rectangle {
        visible: slot.focused && slot.stage && slot.stage.keyFocusRing
        x: -6; y: -6; width: parent.width + 12; height: parent.height + 12
        radius: 30
        color: "transparent"
        border.width: 2
        border.color: ForkTheme.selEdge
        z: 90
        Accessible.ignored: true
    }

    HoverHandler {
        id: hover
        enabled: slot.visible && slot.stage && slot.stage.hoverEnabled
        onHoveredChanged: {
            if (!slot.stage) return
            if (hovered) slot.stage.hoverIndex = slot.slotIndex
            else if (slot.stage.hoverIndex === slot.slotIndex) slot.stage.hoverIndex = -1
        }
    }

    // A card that isn't in focus is one button: clicking it brings it to the front
    MouseArea {
        id: pickArea
        anchors.fill: parent
        z: 100
        enabled: !slot.focused && slot.curOpacity > 0.01
        visible: enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: slot.stage.pick(slot.slotIndex)
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Show %1").arg(slot.slotName)
        Accessible.onPressAction: slot.stage.pick(slot.slotIndex)
    }
}
