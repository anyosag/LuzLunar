import QtQuick

// [fork] A card's standalone animation clock, used only when the page doesn't feed it a shared
// tick: counts up every 1100 ms (the canvas's zTick) while `running`.
Item {
    id: clock

    property bool running: true
    property int tick: 0
    visible: false
    width: 0
    height: 0

    Timer {
        interval: 1100
        repeat: true
        running: clock.running
        onTriggered: clock.tick++
    }
}
