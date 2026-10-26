import QtQuick

import ForkGroupLaunch 1.0
import ForkTheme 1.0

// [fork] StreamSegue's screen while a stream starts: the moon mark, the app and PC, how far the
// connection has got (five labelled steps, then the stage in words), what the stream will use,
// and the shortcuts to know
Item {
    id: panel

    property string appName: ""
    property string hostName: ""
    property bool isResume: false
    // The stream follows a reconnect from the notch bar, or is ending for one
    property bool reconnect: false
    // Upstream's "Starting RTSP handshake..." line
    property string stageText: ""
    // Connection stages begun so far, of moonlight-common-c's 11 (platform setup to input stream)
    property int stagesDone: 0
    readonly property int stageCount: 11
    // Set once the session is initialized; the mark only moves after that, as upstream's spinner
    property bool started: false
    // The stream is up (StreamSegue.connectionStarted), so the last step is done
    property bool connected: false
    // A gamepad is connected, so the shortcut to end the stream is the gamepad's
    property bool gamepad: false
    // Chips like "3024×1890 · 16:10" and "120 fps" (AppView.forkStreamSummary): strings, or
    // { text, plain } for one that's words (the profile's name) rather than numbers
    property var summary: []

    // The design's steps, and the stage that finishes each: stage N starting means the stages
    // before N are done, so a step is done once the stage after its last one has started
    //   Find PC    1 platform init, 2 name resolution            done as stage 3 starts
    //   Handshake  4 RTSP handshake, 5 control init, 8 control start   done as stage 9 starts
    //   Video      6 video init, 9 video start                   done as stage 10 starts
    //   Audio      3 audio init, 10 audio start                  done as stage 11 starts
    //   Input      7 input init, 11 input start                  done once connected
    readonly property var connectionSteps: [
        { "label": qsTr("Find PC"), "doneAt": 3 },
        { "label": qsTr("Handshake"), "doneAt": 9 },
        { "label": qsTr("Video"), "doneAt": 10 },
        { "label": qsTr("Audio"), "doneAt": 11 },
        { "label": qsTr("Input"), "doneAt": 0 }
    ]

    // A multi-display stream with DisplayExtend's display first times the iMac's two routes
    // (ForkGroupLaunch), before the stream connects
    readonly property bool routeStep: ForkGroupLaunch.active && ForkGroupLaunch.checkNeeded
    readonly property var steps: routeStep ? [{ "label": qsTr("iMac route"), "route": true }].concat(connectionSteps)
                                           : connectionSteps

    function stepDone(i) {
        if (steps[i].route === true) {
            return ForkGroupLaunch.decided
        }
        return i === steps.length - 1 ? connected : stagesDone >= steps[i].doneAt
    }

    // The first step that isn't done
    readonly property int currentStep: {
        for (var i = 0; i < steps.length; i++) {
            if (!stepDone(i)) {
                return i
            }
        }
        return steps.length
    }

    anchors.fill: parent

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 640)
        // [multiple displays] tighter, to make room for the displays' card
        spacing: ForkGroupLaunch.active ? 20 : 28

        ForkMoonMark {
            anchors.horizontalCenter: parent.horizontalCenter
            size: ForkGroupLaunch.active ? 96 : 148
            tile: false
            shimmer: panel.started
        }

        Column {
            width: parent.width
            spacing: 8

            ForkText {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "eyebrow"
                pixelSize: 13
                text: panel.reconnect ? qsTr("Reconnecting") : panel.isResume ? qsTr("Resuming") : qsTr("Starting")
            }

            ForkText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                kind: "title"
                // 60 in a roomy window, down to 40 in a narrow one; [multiple displays] 46 down to 34, so
                // the displays' card fits
                pixelSize: ForkGroupLaunch.active ? Math.max(34, Math.min(46, panel.width * 0.054))
                                                  : Math.max(40, Math.min(60, panel.width * 0.07))
                font.letterSpacing: -0.03 * pixelSize
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: panel.appName
                Accessible.role: Accessible.Heading
            }

            ForkText {
                visible: panel.hostName !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "body"
                pixelSize: 17
                color: ForkTheme.muted
                // A group always has two displays or more
                text: ForkGroupLaunch.active ? qsTr("on %1 · %2 displays").arg(panel.hostName).arg(ForkGroupLaunch.displayCount)
                                             : qsTr("on %1").arg(panel.hostName)
            }
        }

        // Five steps (six with the iMac's route), each a bar that fills as the launch gets there, and
        // the stage in words
        Column {
            width: parent.width
            spacing: 12

            Row {
                id: stepRow
                width: parent.width
                spacing: 8

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Connection steps")

                Repeater {
                    model: panel.steps

                    delegate: Item {
                        id: step

                        required property int index
                        required property var modelData

                        readonly property bool done: panel.stepDone(index)
                        readonly property bool active: panel.currentStep === index
                        // How full the bar is: the current step's fills over 0.65 s (at once with Reduce Motion);
                        // the iMac's route as its check goes
                        property real fill: modelData.route === true ? (done ? 1 : ForkGroupLaunch.progress)
                                                                     : done || active ? 1 : 0

                        width: (stepRow.width - (panel.steps.length - 1) * stepRow.spacing) / panel.steps.length
                        height: bar.height + 8 + label.implicitHeight

                        Accessible.role: Accessible.ListItem
                        Accessible.name: done ? qsTr("%1, done").arg(modelData.label)
                                              : active ? qsTr("%1, in progress").arg(modelData.label)
                                                       : qsTr("%1, waiting").arg(modelData.label)

                        Behavior on fill {
                            enabled: !ForkTheme.reduceMotion
                            NumberAnimation { duration: 650 }
                        }

                        Rectangle {
                            id: bar
                            width: parent.width
                            height: 4
                            radius: 2
                            color: ForkTheme.line

                            Rectangle {
                                width: parent.width * step.fill
                                height: parent.height
                                radius: 2
                                color: ForkTheme.accentInk
                            }
                        }

                        ForkText {
                            id: label
                            anchors.top: bar.bottom
                            anchors.topMargin: 8
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            kind: "label"
                            pixelSize: 12
                            font.weight: step.active ? Font.DemiBold : Font.Normal
                            color: step.active ? ForkTheme.text : step.done ? ForkTheme.text2 : ForkTheme.faint
                            elide: Text.ElideRight
                            text: step.modelData.label
                            Accessible.ignored: true
                        }
                    }
                }
            }

            ForkText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                kind: "mono"
                pixelSize: 13
                color: ForkTheme.muted
                elide: Text.ElideRight
                text: ForkGroupLaunch.checking ? ForkGroupLaunch.checkText : panel.stageText
            }
        }

        // The displays of a multi-display stream, and where the iMac's picture comes from
        ForkGroupLaunchCard {
            visible: ForkGroupLaunch.active
            width: parent.width
            height: implicitHeight
        }

        // What the stream will use: pills centered, wrapping onto more lines when they don't fit
        Item {
            id: pillBox

            readonly property real gap: 8
            readonly property real pillHeight: 28

            visible: panel.summary.length > 0
            width: parent.width
            height: pillHeight

            function layoutPills() {
                var rows = []
                var row = []
                var rowWidth = 0
                for (var i = 0; i < pillRepeater.count; i++) {
                    var pill = pillRepeater.itemAt(i)
                    if (!pill) {
                        continue
                    }
                    if (row.length > 0 && rowWidth + gap + pill.width > width) {
                        rows.push({ "pills": row, "width": rowWidth })
                        row = []
                        rowWidth = 0
                    }
                    rowWidth += (row.length > 0 ? gap : 0) + pill.width
                    row.push(pill)
                }
                if (row.length > 0) {
                    rows.push({ "pills": row, "width": rowWidth })
                }

                var y = 0
                for (var r = 0; r < rows.length; r++) {
                    var x = Math.max(0, (width - rows[r].width) / 2)
                    for (var k = 0; k < rows[r].pills.length; k++) {
                        rows[r].pills[k].x = x
                        rows[r].pills[k].y = y
                        x += rows[r].pills[k].width + gap
                    }
                    y += pillHeight + gap
                }
                height = rows.length > 0 ? y - gap : pillHeight
            }

            onWidthChanged: layoutPills()

            Repeater {
                id: pillRepeater
                model: panel.summary

                onItemAdded: pillBox.layoutPills()
                onItemRemoved: pillBox.layoutPills()

                delegate: Rectangle {
                    required property var modelData

                    readonly property bool plain: typeof modelData !== "string" && modelData.plain === true

                    width: pillText.implicitWidth + 24
                    height: pillBox.pillHeight
                    radius: height / 2
                    color: ForkTheme.surface
                    border.color: ForkTheme.line

                    onWidthChanged: pillBox.layoutPills()

                    ForkText {
                        id: pillText
                        anchors.centerIn: parent
                        kind: parent.plain ? "body" : "mono"
                        pixelSize: 12
                        wrapMode: Text.NoWrap
                        lineHeightMode: Text.ProportionalHeight
                        lineHeight: 1.0
                        text: typeof parent.modelData === "string" ? parent.modelData : parent.modelData.text
                    }
                }
            }
        }

        // The two shortcuts, side by side when there's room, equally tall
        Grid {
            id: tips

            readonly property real tipWidth: columns === 2 ? (width - spacing) / 2 : width
            readonly property real tipHeight: Math.max(quitTip.implicitHeight, pointerTip.implicitHeight)

            width: parent.width
            columns: width >= 490 ? 2 : 1
            spacing: 10

            ForkTip {
                id: quitTip
                width: tips.tipWidth
                height: tips.tipHeight
                key: panel.gamepad ? "" : "Q"
                symbol: panel.gamepad ? "gamecontroller" : ""
                text: panel.gamepad ? qsTr("Start+Select+L1+R1 ends the stream") : qsTr("Control-Option-Shift-Q ends the stream")
            }

            ForkTip {
                id: pointerTip
                width: tips.tipWidth
                height: tips.tipHeight
                key: "Z"
                text: qsTr("Control-Option-Shift-Z frees the pointer")
            }
        }
    }
}
