import QtQuick
import QtQuick.Effects

import ForkTheme 1.0

// [fork] One app of the All apps page, as in the design: the cover (box art, or a drawn one), a ring
// while it runs or is pointed at, the Running or sleepy badge, a veil with a play (or power) disc
// when pointed at, the name, the chips and the always-there More button, with its menu. Everything
// is presentational: AppView sets the properties and answers the signals.
Item {
    id: tile

    // The page: colors of the PC, the beat, whether the entrance has settled
    property color pcFill: "#5E5CE6"
    property color pcOnFill: "#FFFFFF"
    property color pcSky: "#17163F"
    property bool asleep: false
    property int ph: 0
    property bool settled: true
    property bool entered: true
    property int enterDelay: 0
    property bool highlighted: false // picked with the keyboard or a gamepad
    property var chipColors: function(tone) { return [ForkTheme.cv.raised, ForkTheme.cv.text2] }

    // The app
    property string appName: ""
    property string boxart: ""
    property bool appCollector: false
    property string colorKey: ""
    property bool running: false
    property bool hidden: false
    property var chips: []
    property int column: 0 // its column; the menu opens to the left from the fifth on
    property bool menuOpen: false
    property var menuItems: []
    property int menuCurrent: 0
    property string clickLabel: ""

    signal activated()
    signal menuToggled()
    signal menuRequested()
    signal menuTriggered(int index)
    signal menuClosed()

    readonly property bool hov: hover.hovered || highlighted || menuOpen
    readonly property bool lifted: hov && !menuOpen && settled && !ForkTheme.reduceMotion
    readonly property real coverH: width * 4 / 3
    readonly property bool fx: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool hasArt: art.status === Image.Ready && !art.isPlaceholder
    readonly property color runBlue: ForkTheme.dark ? "#409CFF" : "#0A6CDB"

    implicitHeight: coverH + 10 + 18 + (chipFlow.height > 0 ? 6 + chipFlow.height : 0)
    height: implicitHeight
    z: menuOpen ? 10 : (hov ? 2 : 1)
    opacity: entered ? 1 : 0

    Behavior on opacity {
        enabled: !tile.settled && !ForkTheme.reduceMotion
        SequentialAnimation {
            PauseAnimation { duration: tile.enterDelay }
            NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] }
        }
    }

    HoverHandler {
        id: hover
        enabled: tile.visible
    }

    // Enter slide, and the lift while pointed at
    Item {
        id: lift
        width: parent.width
        height: parent.height
        y: (tile.entered ? 0 : 16) + (tile.lifted ? -4 : 0)

        Behavior on y {
            enabled: !ForkTheme.reduceMotion
            SequentialAnimation {
                PauseAnimation { duration: tile.settled ? 0 : tile.enterDelay }
                NumberAnimation {
                    duration: tile.settled ? 260 : 600
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1]
                }
            }
        }

        // The cover and everything on it; a hidden app dims all of it
        Item {
            id: cover
            width: parent.width
            height: tile.coverH
            opacity: tile.hidden ? 0.45 : 1

            Behavior on opacity { NumberAnimation { duration: 240 } }

            // The shadow under the cover, and the running app's glow
            RectangularShadow {
                anchors.fill: parent
                radius: 14
                offset: Qt.vector2d(0, tile.hov ? 16 : 8)
                blur: tile.hov ? 30 : 18
                color: ForkTheme.dark ? Qt.rgba(0, 0, 0, tile.hov ? 0.55 : 0.4)
                                      : Qt.rgba(24 / 255, 26 / 255, 46 / 255, tile.hov ? 0.22 : 0.14)

                Behavior on offset { enabled: !ForkTheme.reduceMotion; PropertyAnimation { duration: 240 } }
                Behavior on blur { enabled: !ForkTheme.reduceMotion; NumberAnimation { duration: 240 } }
            }

            RectangularShadow {
                id: glow
                visible: tile.running
                property real p: tile.ph
                Behavior on p {
                    enabled: !ForkTheme.reduceMotion
                    NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] }
                }
                anchors.fill: parent
                radius: 16
                spread: 2
                blur: 12 + 14 * p
                color: Qt.rgba(64 / 255, 156 / 255, 1, 0.25 + 0.25 * p)
            }

            // The cover itself, cut to rounded corners (and dimmed while its PC sleeps)
            Item {
                id: filterItem
                anchors.fill: parent
                layer.enabled: tile.asleep && tile.fx
                layer.effect: MultiEffect {
                    saturation: tile.hov ? 0 : -0.2
                    brightness: tile.hov ? 0 : -0.1
                    Behavior on saturation { NumberAnimation { duration: 240 } }
                    Behavior on brightness { NumberAnimation { duration: 240 } }
                }

                Item {
                    id: clipItem
                    anchors.fill: parent
                    layer.enabled: tile.fx
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: coverMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: tile.pcSky
                    }

                    ForkAppCover {
                        anchors.fill: parent
                        visible: !tile.hasArt
                        name: tile.appName
                        colorKey: tile.colorKey
                        radius: 0
                    }

                    Image {
                        id: art
                        property bool isPlaceholder: false
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: tile.boxart
                        opacity: isPlaceholder ? 0 : 1

                        // The host's grey placeholder art has one of these sizes; the drawn cover stands in
                        onSourceSizeChanged: {
                            isPlaceholder = !tile.appCollector &&
                                ((sourceSize.width === 130 && sourceSize.height === 180) ||
                                 (sourceSize.width === 628 && sourceSize.height === 888) ||
                                 (sourceSize.width === 200 && sourceSize.height === 266))
                        }
                    }

                    // The edge just inside every cover
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.09)
                    }

                    // The running app's badge
                    Rectangle {
                        visible: tile.running && !tile.asleep
                        x: 8
                        y: 8
                        height: 20
                        width: runRow.implicitWidth + 14
                        radius: 10
                        color: "#0A6CDB"

                        Row {
                            id: runRow
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Rectangle {
                                id: runDot
                                property real p: tile.ph
                                Behavior on p {
                                    enabled: !ForkTheme.reduceMotion
                                    NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1] }
                                }
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: "#FFFFFF"
                                opacity: 1 - 0.65 * p
                            }

                            ForkCanvasText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Running")
                                color: "#FFFFFF"
                                px: 10.5
                                weight: 700
                            }
                        }
                    }

                    // A sleeping PC's apps wake it
                    Rectangle {
                        visible: tile.asleep
                        x: 8
                        y: 8
                        width: 22
                        height: 22
                        radius: 11
                        color: "#9B45D9"

                        ForkPathIcon {
                            anchors.centerIn: parent
                            name: "moon"
                            size: 12
                            filled: true
                            stroked: false
                            color: "#FFFFFF"
                        }
                    }

                    // Pointed at: a veil and a disc in the PC's color
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, tile.hov ? 0.4 : 0)
                        Behavior on color { ColorAnimation { duration: 200 } }

                        RectangularShadow {
                            anchors.fill: disc
                            radius: 28
                            offset: Qt.vector2d(0, 10)
                            blur: 24
                            color: Qt.rgba(0, 0, 0, 0.45)
                            opacity: disc.opacity
                            scale: disc.scale
                        }

                        Rectangle {
                            id: disc
                            anchors.centerIn: parent
                            width: 56
                            height: 56
                            radius: 28
                            color: tile.pcFill
                            scale: tile.hov || ForkTheme.reduceMotion ? 1 : 0.6
                            opacity: tile.hov ? 1 : 0

                            Behavior on scale {
                                enabled: !ForkTheme.reduceMotion
                                NumberAnimation { duration: 280; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 1.3, 0.4, 1, 1, 1] }
                            }
                            Behavior on opacity { NumberAnimation { duration: 180 } }

                            ForkPathIcon {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: tile.asleep ? 0 : 1.5
                                name: tile.asleep ? "power" : "play"
                                size: 22
                                color: tile.pcOnFill
                                strokeWidth: 2
                                filled: !tile.asleep
                            }
                        }
                    }
                }
            }

            // The mask the cover is cut to (never drawn)
            Rectangle {
                id: coverMask
                width: cover.width
                height: cover.height
                radius: 14
                visible: false
                layer.enabled: true
                layer.smooth: true
            }

            // The ring: the running app's blue, else the PC's color while pointed at
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: 16
                color: "transparent"
                border.width: 2
                border.color: tile.running ? tile.runBlue : tile.pcFill
                visible: tile.running || tile.hov
            }
        }

        // The name
        ForkCanvasText {
            id: nameLabel
            y: tile.coverH + 10
            width: parent.width
            height: 18
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: tile.appName
            color: tile.hidden ? ForkTheme.cv.muted : ForkTheme.cv.text
            px: 14
            weight: 600
        }

        // The chips: two rows at most
        Flow {
            id: chipFlow
            y: nameLabel.y + 18 + 6
            width: parent.width
            height: Math.min(childrenRect.height, 45)
            spacing: 5
            clip: true

            Repeater {
                model: tile.chips

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property var colors: tile.chipColors(modelData.tone)

                    width: chipRow.implicitWidth + 14
                    height: 20
                    radius: 6
                    color: colors[0]

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 4

                        ForkPathIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!chip.modelData.icon
                            name: chip.modelData.icon || ""
                            size: 11
                            strokeWidth: 2.2
                            filled: false
                            color: chip.colors[1]
                        }

                        ForkCanvasText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.text
                            color: chip.colors[1]
                            px: 11
                            weight: 500
                        }
                    }
                }
            }
        }

        // A click starts or resumes (or wakes first); a right click opens the menu
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: chipFlow.y + chipFlow.height
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            Accessible.role: Accessible.Button
            Accessible.name: tile.clickLabel
            Accessible.description: tile.chips.map(function(chip) { return chip.text }).join(", ")
            Accessible.onPressAction: tile.activated()
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    tile.menuRequested()
                }
                else {
                    tile.activated()
                }
            }
        }

        // The More button: a 40 point target with a 30 point disc, always there
        Item {
            id: more
            x: parent.width - 42
            y: 2
            width: 40
            height: 40
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("More for %1").arg(tile.appName)
            Accessible.onPressAction: tile.menuToggled()

            RectangularShadow {
                anchors.fill: moreDisc
                radius: 15
                offset: Qt.vector2d(0, 2)
                blur: 8
                color: Qt.rgba(0, 0, 0, 0.3)
            }

            Rectangle {
                id: moreDisc
                anchors.centerIn: parent
                width: 30
                height: 30
                radius: 15
                color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, tile.hov || tile.menuOpen ? 0.8 : 0.55)
                Behavior on color { ColorAnimation { duration: 200 } }

                ForkPathIcon {
                    anchors.centerIn: parent
                    name: "more"
                    size: 16
                    strokeWidth: 2.8
                    color: "#ECEEF6"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.menuToggled()
            }
        }
    }

    // The menu: under the More button, to the right of it (the left from the fifth column)
    Loader {
        id: menuLoader
        active: tile.menuOpen
        x: tile.column < 4 ? tile.width - 44 : tile.width - 4 - 248
        y: 40
        z: 20
        sourceComponent: ForkLibraryMenu {
            appName: tile.appName
            items: tile.menuItems
            current: tile.menuCurrent
            onTriggered: function(index) { tile.menuTriggered(index) }
            onCloseRequested: tile.menuClosed()
            Component.onCompleted: forceActiveFocus()
        }
    }
}
