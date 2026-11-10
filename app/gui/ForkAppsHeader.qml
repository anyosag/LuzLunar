import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import ForkTheme 1.0

// [fork] The PC's band at the top of the All apps panel, as in the design (Library and
// LibraryAsleep): the PC's sky with a few twinkling stars, the Apollo logo, the PC's name, a line
// about it, its address with a copy button and a note, the moon (live and breathing, or asleep
// and rising with drifting Zs) and, on the right, a box that says what the PC is doing: NOW
// RUNNING with the app's thumbnail and Resume and Quit, READY, or ASLEEP with Wake PC.
// Fixed height 124; AppView puts it flush at the top of the panel (which rounds its corners).
Item {
    id: band

    property string pcName: ""
    property bool apollo: true
    property string hostLine: ""
    property string address: ""
    property string ipNote: ""
    property bool asleep: false
    property bool wakeReady: true
    // The app that runs, if any (an awake PC only)
    property bool hasRunning: false
    property string runningName: ""
    property string runningBoxart: ""
    property string runningColorKey: ""
    property string runningSummary: ""
    // The PC's color: its sky (this band), its fill (Resume, Wake PC) and the ink on it
    property color pcSky: "#17163F"
    property color pcFill: "#5E5CE6"
    property color pcOnFill: "#FFFFFF"
    // The beat (1100 ms): twinkles, breathing glows, the moon's bob
    property int tick: 0
    property bool entered: true
    property bool settled: true

    signal resume()
    signal quit()
    signal wake()
    signal copyAddress()

    readonly property int ph: tick % 2
    readonly property bool live: !asleep
    readonly property bool fx: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property color runBlue: ForkTheme.dark ? "#409CFF" : "#0A6CDB"
    readonly property var eased: [0.25, 0.1, 0.25, 1, 1, 1]
    readonly property var easedInOut: [0.42, 0, 0.58, 1, 1, 1]
    readonly property var easedOut: [0, 0, 0.58, 1, 1, 1]

    height: 124
    clip: true

    Rectangle {
        anchors.fill: parent
        color: band.pcSky
    }

    // Stars at fixed places, twinkling in opposite phases
    Repeater {
        model: [[232, 18, 2], [306, 102, 2], [418, 14, 3], [452, 96, 2], [566, 30, 2], [1188, 8, 2]]

        delegate: Rectangle {
            required property var modelData
            required property int index
            x: modelData[0]
            y: modelData[1]
            width: modelData[2]
            height: width
            radius: width / 2
            color: "#FFFFFF"
            opacity: (band.tick + index) % 2 ? 0.75 : 0.3
            visible: x < band.width - 2

            Behavior on opacity {
                enabled: !ForkTheme.reduceMotion
                NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: band.eased }
            }
        }
    }

    // The moon, lit on the left, with a soft halo that breathes (the box stays dark inside)
    Item {
        id: liveMoon
        visible: band.live && x + 54 < statusBox.x - 8
        x: 496
        y: 26
        width: 54
        height: 54

        property real p: band.ph
        Behavior on p {
            enabled: !ForkTheme.reduceMotion
            NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: band.easedInOut }
        }

        RectangularShadow {
            anchors.fill: parent
            radius: 27
            blur: 30 + 20 * liveMoon.p
            color: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.2 + 0.18 * liveMoon.p)
        }

        Rectangle {
            anchors.fill: parent
            radius: 27
            color: band.pcSky
        }

        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#F5C878"
                strokeColor: "transparent"
                PathSvg { path: "M22.44 0.39A27 27 0 1 0 45.56 46.61A27 27 0 0 1 22.44 0.39Z" }
            }
        }
    }

    // Asleep: a crescent rising over the band's bottom edge, bobbing, and Zs drifting up from it
    Item {
        visible: band.asleep && x + 76 < statusBox.x
        x: 486
        y: band.ph ? 74 : 70
        width: 76
        height: 54
        clip: true

        Behavior on y {
            enabled: !ForkTheme.reduceMotion
            NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: band.easedInOut }
        }

        Shape {
            x: 10
            y: 24
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#CFC8F3"
                strokeColor: "transparent"
                PathSvg { path: "M22.59 0.36A27 27 0 1 0 44.41 47.64A27 27 0 0 1 22.59 0.36Z" }
            }
        }
    }

    Repeater {
        model: band.asleep ? 3 : 0

        delegate: ForkCanvasText {
            id: z
            required property int index
            readonly property int zp: (band.tick + index) % 3
            x: 548 + zp * 8
            y: 72 - zp * 12
            visible: x < statusBox.x
            text: "z"
            color: Qt.rgba(1, 1, 1, 0.8)
            px: 11
            weight: 800
            scale: 1 + 0.2 * zp
            opacity: zp === 1 ? 0.75 : 0

            Behavior on x { enabled: z.zp !== 0 && !ForkTheme.reduceMotion; NumberAnimation { duration: 1100 } }
            Behavior on y { enabled: z.zp !== 0 && !ForkTheme.reduceMotion; NumberAnimation { duration: 1100 } }
            Behavior on scale { enabled: z.zp !== 0 && !ForkTheme.reduceMotion; NumberAnimation { duration: 1100 } }
            Behavior on opacity {
                enabled: z.zp !== 0 && !ForkTheme.reduceMotion
                NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: band.eased }
            }
        }
    }

    // The logo (Apollo's icon, 68 square, 4 into the gap on each side) or a plain tile
    ForkLibraryEnter {
        x: 22
        y: 28
        width: 68
        height: 68
        entered: band.entered
        settled: band.settled
        delay: 90

        Image {
            id: logo
            anchors.fill: parent
            visible: band.apollo
            source: "qrc:/res/apollo.png"
            sourceSize: Qt.size(136, 136)
            smooth: true
            mipmap: true
            fillMode: Image.PreserveAspectFit
            Accessible.ignored: true
            layer.enabled: band.fx && band.apollo
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.35)
                shadowVerticalOffset: 6
                shadowBlur: 0.5
                blurMax: 12
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: !band.apollo
            radius: 16
            color: band.pcFill

            ForkCanvasText {
                anchors.centerIn: parent
                text: band.pcName.charAt(0).toUpperCase()
                color: band.pcOnFill
                px: 34
                weight: 700
            }
        }
    }

    // The name, a line about the PC, its address and a note
    ForkLibraryEnter {
        id: names
        x: 104
        y: (band.height - height) / 2
        width: Math.max(80, Math.min(360, statusBox.x - 18 - 104))
        height: 81
        entered: band.entered
        settled: band.settled
        delay: 140

        ForkCanvasText {
            y: 0
            width: parent.width
            height: 34
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: band.pcName
            color: "#FFFFFF"
            px: 28
            weight: 750
            tracking: -0.56
        }

        ForkCanvasText {
            y: 38
            width: parent.width
            height: 17
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: band.hostLine
            color: Qt.rgba(1, 1, 1, 0.78)
            px: 13
        }

        Row {
            y: 59
            width: parent.width
            height: 22
            spacing: 8

            Rectangle {
                id: ipChip
                visible: band.address !== ""
                width: chipRow.implicitWidth + 8 + 3
                height: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, 0.13)

                Row {
                    id: chipRow
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    ForkCanvasText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "IP"
                        opacity: 0.7
                        color: "#FFFFFF"
                        px: 10
                        weight: 700
                        tracking: 0.6
                    }

                    ForkCanvasText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: band.address
                        color: "#FFFFFF"
                        font.family: ForkTheme.monoFamily
                        px: 12
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        opacity: 0.8
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Copy the IP address of %1").arg(band.pcName)
                        Accessible.onPressAction: band.copyAddress()

                        ForkPathIcon {
                            anchors.centerIn: parent
                            name: "copy"
                            size: 12
                            color: "#FFFFFF"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: band.copyAddress()
                        }
                    }
                }
            }

            ForkCanvasText {
                width: Math.max(0, parent.width - (ipChip.visible ? ipChip.width + 8 : 0))
                height: 22
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: band.ipNote
                color: Qt.rgba(1, 1, 1, 0.62)
                px: 11.5
            }
        }
    }

    // What the PC is doing: running an app, ready, or asleep
    ForkLibraryEnter {
        id: statusBox
        x: band.width - 18 - width
        y: 16
        width: 1 + 10 + statusRow.implicitWidth + 12 + 1
        height: 92
        entered: band.entered
        settled: band.settled
        delay: 200

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
        }

        Row {
            id: statusRow
            x: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            // NOW RUNNING
            Item {
                visible: band.live && band.hasRunning
                width: 104
                height: 72
                anchors.verticalCenter: parent.verticalCenter

                RectangularShadow {
                    anchors.fill: parent
                    radius: 11
                    spread: 2
                    property real p: band.ph
                    Behavior on p {
                        enabled: !ForkTheme.reduceMotion
                        NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: band.easedInOut }
                    }
                    blur: 10 + 12 * p
                    color: Qt.rgba(64 / 255, 156 / 255, 1, 0.25 + 0.25 * p)
                }

                Item {
                    id: thumb
                    anchors.fill: parent
                    layer.enabled: band.fx
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: thumbMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Rectangle { anchors.fill: parent; color: band.pcSky }

                    ForkAppCover {
                        anchors.fill: parent
                        visible: !thumbArt.ready
                        kind: "thumb"
                        name: band.runningName
                        colorKey: band.runningColorKey
                        radius: 0
                    }

                    // The art (3:4), cropped to its upper middle
                    Image {
                        id: thumbArt
                        readonly property bool ready: status === Image.Ready && !(sourceSize.width === 200 && sourceSize.height === 266)
                        width: parent.width
                        height: width * 4 / 3
                        y: -0.4 * (height - parent.height)
                        fillMode: Image.Stretch
                        asynchronous: true
                        source: band.runningBoxart
                        visible: ready
                    }
                }

                Rectangle {
                    id: thumbMask
                    anchors.fill: parent
                    radius: 11
                    visible: false
                    layer.enabled: true
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: 13
                    color: "transparent"
                    border.width: 2
                    border.color: band.runBlue
                }
            }

            Column {
                visible: band.live && band.hasRunning
                width: 236
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Row {
                    height: 14
                    spacing: 7

                    Item {
                        width: 7
                        height: 7
                        anchors.verticalCenter: parent.verticalCenter
                        property real p: band.ph
                        Behavior on p {
                            enabled: !ForkTheme.reduceMotion
                            NumberAnimation { duration: 1100; easing.type: Easing.BezierSpline; easing.bezierCurve: band.easedOut }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 7 + 10 * parent.p
                            height: width
                            radius: width / 2
                            color: Qt.rgba(121 / 255, 214 / 255, 181 / 255, 0.55 * (1 - parent.p))
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: "#79D6B5"
                        }
                    }

                    ForkCanvasText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Now running").toUpperCase()
                        color: "#79D6B5"
                        px: 10.5
                        weight: 700
                        tracking: 1.26
                    }
                }

                ForkCanvasText {
                    width: parent.width
                    height: 23
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: band.runningName
                    color: "#FFFFFF"
                    px: 18
                    weight: 650
                }

                ForkCanvasText {
                    width: parent.width
                    height: 15
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: band.runningSummary
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.family: ForkTheme.monoFamily
                    px: 11.5
                }
            }

            ForkLibraryButton {
                visible: band.live && band.hasRunning
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Resume")
                iconName: "play"
                iconSize: 15
                iconStrokeWidth: 1.6
                iconFilled: 1
                fill: band.pcFill
                ink: band.pcOnFill
                padLeft: 13
                padRight: 16
                onClicked: band.resume()
            }

            ForkLibraryButton {
                visible: band.live && band.hasRunning
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Quit")
                iconName: "stop"
                iconSize: 14
                iconFilled: 1
                iconStroked: 0
                fill: Qt.rgba(1, 1, 1, 0.1)
                ink: "#FFFFFF"
                borderColor: Qt.rgba(1, 1, 1, 0.18)
                borderWidth: 1
                fontWeight: 550
                padLeft: 12
                padRight: 15
                onClicked: band.quit()
            }

            // READY
            Item {
                visible: band.live && !band.hasRunning
                width: 44 + 6
                height: 44
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    x: 6
                    width: 44
                    height: 44
                    radius: 22
                    color: "#30D158"

                    ForkPathIcon {
                        anchors.centerIn: parent
                        name: "check"
                        size: 22
                        strokeWidth: 2
                        color: "#05230F"
                    }
                }
            }

            Column {
                visible: band.live && !band.hasRunning
                width: 314
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                ForkCanvasText {
                    height: 14
                    text: qsTr("Ready").toUpperCase()
                    color: "#7EE2A0"
                    px: 10.5
                    weight: 700
                    tracking: 1.26
                }
                ForkCanvasText {
                    height: 23
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Nothing running")
                    color: "#FFFFFF"
                    px: 18
                    weight: 650
                }
                ForkCanvasText {
                    height: 16
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Pick an app below to start it")
                    color: Qt.rgba(1, 1, 1, 0.72)
                    px: 12.5
                }
            }

            // ASLEEP
            Item {
                visible: band.asleep
                width: 44 + 6
                height: 44
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    x: 6
                    width: 44
                    height: 44
                    radius: 22
                    color: "#9B45D9"

                    ForkPathIcon {
                        anchors.centerIn: parent
                        name: "moon"
                        size: 20
                        filled: true
                        stroked: false
                        color: "#FFFFFF"
                    }
                }
            }

            Column {
                visible: band.asleep
                width: 250
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                ForkCanvasText {
                    height: 14
                    text: qsTr("Asleep").toUpperCase()
                    color: "#CFC8F3"
                    px: 10.5
                    weight: 700
                    tracking: 1.26
                }
                ForkCanvasText {
                    width: parent.width
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: qsTr("Picking an app wakes it first")
                    color: "#FFFFFF"
                    px: 17
                    weight: 650
                }
                ForkCanvasText {
                    width: parent.width
                    height: 16
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: band.wakeReady ? qsTr("Wake from off is ready") : qsTr("Wakes from sleep, not from off")
                    color: Qt.rgba(1, 1, 1, 0.72)
                    px: 12.5
                }
            }

            ForkLibraryButton {
                visible: band.asleep
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Wake PC")
                iconName: "power"
                iconSize: 16
                iconStrokeWidth: 2
                iconFilled: 0
                fill: band.pcFill
                ink: band.pcOnFill
                onClicked: band.wake()
            }
        }
    }
}
