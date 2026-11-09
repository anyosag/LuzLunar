import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Templates as T

import ForkTheme 1.0

// [fork] The top of a PC's apps page (AppView's header), as in the design's All apps: a band in
// the PC's color with the PC (Apollo's logo, its name, its host software and network, and its
// address, which can be copied) and what it's doing (the app that runs, with Resume and Quit, or
// that it's ready); then the page's title, how many apps there are, a search field and a switch
// that shows the hidden apps. As wide as the grid's block (AppView sets the width), so its edges
// line up with the tiles.
Column {
    id: header

    // The PC: its name, whether its host is Apollo (for the logo), the line under its name (host
    // software and network, like "Apollo 0.4.8 · Home network") and its address
    property string pcName: ""
    property bool apollo: false
    property string hostLine: ""
    property string address: ""

    // The app that runs, and its stream in one line, like "3024×1890 · 120 fps · HEVC 10-bit · Office profile"
    property bool hasRunning: false
    property string runningName: ""
    property url runningBoxart
    property string runningSummary: ""

    // Apps that aren't hidden and apps that are, whether hidden ones show, and how many match the
    // search (-1 with no search)
    property bool showingHidden: false
    property int appCount: 0
    property int hiddenCount: 0
    property int matchCount: -1
    property alias searchText: search.text

    signal resume()
    signal quit()
    signal toggleHidden()
    signal copyAddress()
    // The search field took the keyboard; Up (to the toolbar), and Down or Return (to the apps), leave it
    signal searchFocused()
    signal searchUp()
    signal searchDown()

    // How the band fits its width: the moon only where there's room; what the PC is doing under
    // the PC rather than beside it where they'd meet; Resume and Quit as bare symbols, and no
    // cover, when even that is tight
    readonly property bool roomy: width >= 900
    readonly property bool stacked: width < 820
    readonly property bool tiny: width < 520
    readonly property real bandTop: 124

    // The page rhythm: 28 above, 24 between the band and the title, 20 to the grid
    spacing: 24
    topPadding: 28
    bottomPadding: 20

    // ⌘F
    function focusSearch() {
        search.forceActiveFocus(Qt.ShortcutFocusReason)
        search.selectAll()
    }

    Rectangle {
        id: band
        width: header.width
        height: header.stacked ? header.bandTop + capsule.height + 16 : header.bandTop
        radius: ForkTheme.radiusCard
        color: ForkTheme.pcSky
        clip: true

        // A few stars that twinkle (still with Reduce Motion)
        Repeater {
            model: [[0.2, 18, 2, 0], [0.26, 100, 2, 1], [0.36, 14, 3, 2], [0.39, 94, 2, 0], [0.48, 30, 2, 1], [0.985, 8, 2, 2]]

            delegate: Rectangle {
                required property var modelData

                x: Math.round(band.width * modelData[0])
                y: modelData[1]
                width: modelData[2]
                height: width
                radius: width / 2
                color: "#FFFFFF"
                opacity: 0.6

                SequentialAnimation on opacity {
                    running: !ForkTheme.reduceMotion && band.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: modelData[3] * 700 }
                    NumberAnimation { to: 0.2; duration: 1100; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.8; duration: 1100; easing.type: Easing.InOutSine }
                }
            }
        }

        // The moon, between the PC and what it's doing, where there's room; its glow breathes
        // while an app runs (no glow where effects can't draw)
        Shape {
            id: moon

            property real glow: 0.45

            visible: header.roomy && !header.stacked && capsule.x - (identity.x + identity.width) > 130
            x: Math.round((identity.x + identity.width + capsule.x) / 2 - width / 2)
            y: 24
            width: 54
            height: 54
            preferredRendererType: Shape.CurveRenderer
            Accessible.ignored: true

            layer.enabled: visible && GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#F5C878"
                shadowBlur: 1.0
                shadowOpacity: moon.glow
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            SequentialAnimation on glow {
                running: header.hasRunning && moon.visible && !ForkTheme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.8; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
            }

            // A crescent: the moon's circle less the same circle moved 14 right and 7 up
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "#F5C878"
                PathSvg { path: "M22.44 0.39A27 27 0 1 0 45.56 46.61A27 27 0 0 1 22.44 0.39Z" }
            }
        }

        // The PC: Apollo's logo, or a PC on a tile for other host software
        Image {
            id: logo
            visible: header.apollo
            x: 22
            y: Math.round((header.bandTop - height) / 2)
            width: 68
            height: 68
            source: "qrc:/res/apollo.png"
            sourceSize.width: 136
            sourceSize.height: 136
            mipmap: true
            Accessible.ignored: true
        }

        Rectangle {
            id: otherLogo
            visible: !header.apollo
            x: 26
            y: Math.round((header.bandTop - height) / 2)
            width: 60
            height: 60
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.12)

            ForkSymbol {
                anchors.centerIn: parent
                symbol: "pc"
                fallback: "qrc:/res/desktop_windows-48px.svg"
                size: 30
                color: "#FFFFFF"
            }
        }

        Column {
            id: identity
            x: (header.apollo ? logo.x + logo.width : otherLogo.x + otherLogo.width) + 14
            y: Math.round((header.bandTop - height) / 2)
            // Beside the capsule, never wider than the room it leaves
            width: header.stacked ? band.width - x - 24 : Math.max(0, Math.min(320, capsule.x - x - 24))
            spacing: 4

            ForkText {
                width: parent.width
                kind: "titleSm"
                color: "#FFFFFF"
                elide: Text.ElideRight
                text: header.pcName
                Accessible.role: Accessible.Heading
            }

            ForkText {
                width: parent.width
                visible: header.hostLine !== ""
                kind: "body"
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.78)
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: header.hostLine
            }

            // The address, in a pill with a copy button; a long one (IPv6) is shortened in the middle
            Rectangle {
                visible: header.address !== ""
                width: Math.min(parent.width, pillRow.implicitWidth + 11)
                height: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, 0.13)
                clip: true

                Row {
                    id: pillRow
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        id: ipLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "IP"
                        textFormat: Text.PlainText
                        font.family: ForkTheme.uiFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                        color: "#FFFFFF"
                        opacity: 0.7
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Math.max(24, identity.width - 19 - ipLabel.implicitWidth - copyButton.width - 2 * pillRow.spacing))
                        text: header.address
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        font.family: ForkTheme.monoFamily
                        font.pixelSize: 12
                        color: "#FFFFFF"
                    }

                    T.AbstractButton {
                        id: copyButton
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        hoverEnabled: true
                        focusPolicy: Qt.NoFocus
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Copy the address of %1").arg(header.pcName)

                        background: Rectangle {
                            radius: 9
                            color: copyButton.hovered ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                        }

                        contentItem: Item {
                            ForkSymbol {
                                anchors.centerIn: parent
                                symbol: "doc.on.doc"
                                size: 11
                                color: "#FFFFFF"
                            }
                        }

                        onClicked: header.copyAddress()
                    }
                }
            }
        }

        // What the PC is doing: the app that runs, with Resume and Quit, or that it's ready. Beside
        // the PC, or under it where they'd meet.
        Rectangle {
            id: capsule
            x: header.stacked ? 16 : band.width - width - 16
            y: header.stacked ? header.bandTop : Math.round((header.bandTop - height) / 2)
            width: header.stacked ? band.width - 32 : capsuleRow.implicitWidth + 26
            height: 92
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.08)
            border.color: Qt.rgba(1, 1, 1, 0.14)

            Accessible.role: Accessible.Grouping
            Accessible.name: header.hasRunning ? qsTr("Now running: %1").arg(header.runningName) : qsTr("Nothing running")

            Row {
                id: capsuleRow
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                // The running app's cover, in the running ring
                Item {
                    id: thumb
                    visible: header.hasRunning && !header.tiny
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54
                    height: 72

                    // The host's placeholder art has one of these sizes (as AppView checks)
                    readonly property bool hasArt: {
                        if (thumbImage.status !== Image.Ready) {
                            return false
                        }
                        var w = thumbImage.sourceSize.width
                        var h = thumbImage.sourceSize.height
                        return !((w === 130 && h === 180) || (w === 628 && h === 888) || (w === 200 && h === 266))
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: 12
                        color: "transparent"
                        border.width: 2
                        border.color: ForkTheme.running
                    }

                    ForkAppCover {
                        anchors.fill: parent
                        visible: !thumb.hasArt
                        name: header.runningName
                        radius: 10
                        showName: false
                    }

                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        source: header.runningBoxart
                        fillMode: Image.PreserveAspectCrop
                        // Drawn through the rounded mask below, or plainly where effects can't draw
                        visible: thumb.hasArt && GraphicsInfo.api === GraphicsInfo.Software
                        asynchronous: true
                    }

                    Rectangle {
                        id: thumbMask
                        anchors.fill: parent
                        radius: 10
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        visible: thumb.hasArt && GraphicsInfo.api !== GraphicsInfo.Software
                        anchors.fill: parent
                        source: thumbImage
                        maskEnabled: true
                        maskSource: thumbMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                // Ready: a check
                Rectangle {
                    id: readyDisc
                    visible: !header.hasRunning
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 22
                    color: "#30D158"

                    ForkSymbol {
                        anchors.centerIn: parent
                        symbol: "checkmark"
                        fallback: "qrc:/res/baseline-check_circle_outline-24px.svg"
                        size: 18
                        color: "#05230F"
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    // Beside the PC a fixed width; under it, whatever the buttons leave
                    width: {
                        if (!header.stacked) {
                            return header.roomy ? 240 : 190
                        }
                        var others = 0
                        var parts = [thumb, readyDisc, resumeButton, quitButton]
                        for (var i = 0; i < parts.length; i++) {
                            if (parts[i].visible) {
                                others += parts[i].width + capsuleRow.spacing
                            }
                        }
                        return Math.max(60, capsule.width - 24 - others)
                    }
                    spacing: 3

                    Row {
                        spacing: 7

                        // The dot sends out a ring while an app runs
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: header.hasRunning
                            width: 7
                            height: 7

                            Rectangle {
                                id: dotRing
                                anchors.centerIn: parent
                                visible: !ForkTheme.reduceMotion
                                width: 7
                                height: width
                                radius: width / 2
                                color: "#79D6B5"

                                ParallelAnimation {
                                    running: dotRing.visible && header.hasRunning && band.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { target: dotRing; property: "width"; from: 7; to: 19; duration: 1800; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: dotRing; property: "opacity"; from: 0.55; to: 0; duration: 1800; easing.type: Easing.OutCubic }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 3.5
                                color: "#79D6B5"
                            }
                        }

                        Text {
                            text: header.hasRunning ? qsTr("Now running") : qsTr("Ready")
                            textFormat: Text.PlainText
                            font.family: ForkTheme.uiFamily
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            font.capitalization: Font.AllUppercase
                            color: header.hasRunning ? "#79D6B5" : "#7EE2A0"
                        }
                    }

                    Text {
                        width: parent.width
                        text: header.hasRunning ? header.runningName : qsTr("Nothing running")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: ForkTheme.uiFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: "#FFFFFF"
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: header.hasRunning ? header.runningSummary : qsTr("Pick an app below to start it")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: header.hasRunning ? ForkTheme.monoFamily : ForkTheme.uiFamily
                        font.pixelSize: header.hasRunning ? 12 : 13
                        color: Qt.rgba(1, 1, 1, 0.72)
                    }
                }

                ForkButton {
                    id: resumeButton
                    visible: header.hasRunning
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "pc"
                    symbol: "play.fill"
                    symbolSize: 13
                    focusPolicy: Qt.NoFocus
                    text: header.tiny ? "" : qsTr("Resume")
                    Accessible.description: qsTr("Resume %1").arg(header.runningName)
                    onClicked: header.resume()
                }

                ForkButton {
                    id: quitButton
                    visible: header.hasRunning
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "glass"
                    symbol: "stop.fill"
                    symbolSize: 11
                    focusPolicy: Qt.NoFocus
                    text: header.tiny ? "" : qsTr("Quit")
                    Accessible.description: qsTr("Quit %1").arg(header.runningName)
                    onClicked: header.quit()
                }
            }
        }
    }

    // "All apps", how many, the search and the switch that shows the hidden apps
    Item {
        width: header.width
        height: 44

        ForkText {
            id: heading
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            kind: "titleSm"
            pixelSize: 26
            text: qsTr("All apps")
            Accessible.role: Accessible.Heading
        }

        ForkText {
            anchors.left: heading.right
            anchors.leftMargin: 12
            anchors.right: controls.left
            anchors.rightMargin: 12
            anchors.baseline: heading.baseline
            kind: "body"
            font.pixelSize: 14
            color: ForkTheme.muted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            text: {
                if (header.matchCount >= 0) {
                    return header.matchCount === 0 ? qsTr("No apps match")
                         : header.matchCount === 1 ? qsTr("1 app matches") : qsTr("%1 apps match").arg(header.matchCount)
                }
                var apps = header.appCount === 1 ? qsTr("1 app") : qsTr("%1 apps").arg(header.appCount)
                return header.hiddenCount > 0 ? apps + " · " + qsTr("%1 hidden").arg(header.hiddenCount) : apps
            }
        }

        Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            ForkTextField {
                id: search
                anchors.verticalCenter: parent.verticalCenter
                width: header.tiny ? 140 : (header.stacked ? 190 : 240)
                implicitHeight: 36
                leftPadding: 34
                rightPadding: text !== "" ? 34 : 12
                font.pixelSize: 13
                // The placeholder is the field's only visible label, so it's in the muted color
                // (4.5:1 or more in both appearances) rather than the fainter one fields use
                placeholderTextColor: ForkTheme.muted
                placeholderText: qsTr("Search apps")
                Accessible.name: qsTr("Search the apps on %1").arg(header.pcName)

                onActiveFocusChanged: {
                    if (activeFocus) {
                        header.searchFocused()
                    }
                }

                ForkSymbol {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    symbol: "magnifyingglass"
                    size: 14
                    color: ForkTheme.muted
                }

                // Clears the search; so does Escape
                T.AbstractButton {
                    id: clearButton
                    visible: search.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Clear the search")

                    background: Rectangle {
                        radius: 10
                        color: clearButton.hovered ? ForkTheme.lineStrong : ForkTheme.raised
                    }

                    contentItem: Item {
                        ForkSymbol {
                            anchors.centerIn: parent
                            symbol: "xmark"
                            size: 9
                            color: ForkTheme.text2
                        }
                    }

                    onClicked: search.text = ""
                }

                Keys.onEscapePressed: (event) => {
                    if (search.text !== "") {
                        search.text = ""
                        event.accepted = true
                    }
                    else {
                        event.accepted = false
                    }
                }
                // The arrow keys and a gamepad's pad (and its A, as Return) lead out of the field
                Keys.onUpPressed: header.searchUp()
                Keys.onDownPressed: header.searchDown()
                Keys.onReturnPressed: header.searchDown()
                Keys.onEnterPressed: header.searchDown()
            }

            Row {
                visible: header.hiddenCount > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                ForkText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !header.tiny
                    kind: "body"
                    font.pixelSize: 13
                    color: ForkTheme.text2
                    wrapMode: Text.NoWrap
                    text: qsTr("Show hidden apps")
                }

                ForkSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: header.showingHidden
                    focusPolicy: Qt.NoFocus
                    Accessible.name: qsTr("Show hidden apps")
                    onClicked: header.toggleHidden()
                }
            }
        }
    }
}
