// [fork] The ... menu of a PC card (carousel.md §6): the PC's name, then rows in groups, each with
// an icon, a label, an optional badge ("New", "Update") and a key hint. The first row marked `hi`
// is the card's main action (Return) and stays highlighted blue; Up/Down/hover move a highlight over
// the others, Return runs the row, Escape closes. The page places it and covers the rest of the
// window with a catcher while it is open.
//
// sections: [[{ id, label, icon (SVG path), fill (bool), key, badge, warm, hi, danger }]]
import QtQuick
import ForkTheme

FocusScope {
    id: menu

    property string title: ""
    property var sections: []
    signal activated(string id)
    signal dismissed()

    width: 288
    height: panel.height

    // The flat list of rows, for the highlight
    readonly property var flat: {
        var out = []
        for (var s = 0; s < sections.length; s++) {
            for (var i = 0; i < sections[s].length; i++) {
                out.push(sections[s][i])
            }
        }
        return out
    }
    property int active: -1

    onVisibleChanged: if (visible) active = -1

    function _move(delta) {
        if (flat.length === 0) return
        var start = active < 0 ? (delta > 0 ? -1 : flat.length) : active
        active = (start + delta + flat.length) % flat.length
    }
    function _defaultRow() {
        for (var i = 0; i < flat.length; i++) if (flat[i].hi) return i
        return 0
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Down) { _move(1); event.accepted = true }
        else if (event.key === Qt.Key_Up) { _move(-1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var r = flat[active >= 0 ? active : _defaultRow()]
            if (r) menu.activated(r.id)
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) { menu.dismissed(); event.accepted = true }
    }

    Rectangle {
        id: panel
        width: parent.width
        height: col.height + 14
        radius: 12
        color: ForkTheme.cv.menu
        border.width: 1
        border.color: ForkTheme.cv.lineStrong
        Accessible.role: Accessible.PopupMenu
        Accessible.name: menu.title

        // Soft shadow under the panel (0 18px 50px)
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 18
            anchors.margins: -6
            radius: 18
            color: ForkTheme.dark ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(20 / 255, 22 / 255, 40 / 255, 0.08)
        }

        Column {
            id: col
            x: 7; y: 7
            width: parent.width - 14

            Text {
                x: 10
                width: parent.width - 20
                height: 25
                topPadding: 6
                text: menu.title
                elide: Text.ElideRight
                font.family: ForkTheme.uiFamily
                font.pixelSize: 12
                font.weight: 600
                color: ForkTheme.cv.faint
            }

            Repeater {
                model: menu.sections
                delegate: Column {
                    id: sec
                    required property var modelData
                    required property int index
                    width: col.width

                    Item {
                        visible: sec.index > 0
                        width: parent.width
                        height: visible ? 11 : 0
                        Rectangle { x: 10; y: 5; width: parent.width - 20; height: 1; color: ForkTheme.cv.line }
                    }
                    Repeater {
                        model: sec.modelData
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property int flatIndex: {
                                var n = 0
                                for (var s = 0; s < sec.index; s++) n += menu.sections[s].length
                                return n + index
                            }
                            readonly property bool hi: modelData.hi === true
                            readonly property bool danger: modelData.danger === true
                            readonly property bool lit: !hi && menu.active === flatIndex
                            width: sec.width
                            height: 30
                            radius: 7
                            color: hi ? ForkTheme.cv.menuHi
                                      : (lit ? (ForkTheme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                            Accessible.role: Accessible.MenuItem
                            Accessible.name: modelData.label
                            Accessible.onPressAction: menu.activated(modelData.id)

                            ForkStoryGlyph {
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                path: row.modelData.icon
                                filled: row.modelData.fill === true
                                size: 16
                                color: row.hi ? "#FFFFFF" : (row.danger ? ForkTheme.st.red : ForkTheme.cv.muted)
                            }
                            Text {
                                x: 36
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, (badge.visible ? badge.x : keyText.x) - 10 - x)
                                text: row.modelData.label
                                elide: Text.ElideRight
                                font.family: ForkTheme.uiFamily
                                font.pixelSize: 13
                                color: row.hi ? "#FFFFFF" : (row.danger ? ForkTheme.st.red : ForkTheme.cv.text)
                            }
                            Text {
                                id: keyText
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.width - 10 - width
                                text: row.modelData.key || ""
                                font.family: ForkTheme.uiFamily
                                font.pixelSize: 12
                                opacity: 0.7
                                color: row.hi ? "#FFFFFF" : (row.danger ? ForkTheme.st.red : ForkTheme.cv.text)
                            }
                            Rectangle {
                                id: badge
                                visible: (row.modelData.badge || "") !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                x: keyText.x - 10 - width
                                width: badgeText.implicitWidth + 12
                                height: 17
                                radius: 6
                                color: row.hi ? Qt.rgba(1, 1, 1, 0.22)
                                              : (row.modelData.warm
                                                 ? (ForkTheme.dark ? Qt.rgba(255 / 255, 159 / 255, 10 / 255, 0.16) : Qt.rgba(168 / 255, 90 / 255, 0, 0.10))
                                                 : (ForkTheme.dark ? Qt.rgba(64 / 255, 156 / 255, 255 / 255, 0.16) : Qt.rgba(0, 98 / 255, 204 / 255, 0.09)))
                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: row.modelData.badge || ""
                                    font.family: ForkTheme.uiFamily
                                    font.pixelSize: 10.5
                                    font.weight: 700
                                    font.letterSpacing: 0.21
                                    color: row.hi ? "#FFFFFF" : (row.modelData.warm ? ForkTheme.st.orange : ForkTheme.st.blue)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: menu.active = row.flatIndex
                                onClicked: menu.activated(row.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
