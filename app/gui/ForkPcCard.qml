import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ForkTheme 1.0

import "ForkPcCardText.js" as CardText

// [fork] The big PC card of Your PCs (the canvas's Main board): a 560 x 540 card with a 104 px
// header in the PC's own sky, a status box, the apps (or the pairing steps), chips and the action
// row. Presentational: it takes plain properties and sends signals, so the page feeds it from the
// model and the screenshot harness from sample data. See spec/contract-card.md.
Item {
    id: card

    // ---- the PC
    property string pcName: ""
    // A key of ForkTheme.hue(); a PC that isn't paired is always "gray" (forced below)
    property string hueKey: "indigo"
    // ready streaming waking asleep offCanWake offNoWake notPaired unreachable (the model's short
    // names off, pair and lost work too)
    property string state: "ready"
    property string version: ""
    property string network: "Home network"
    property int latencyMs: -1
    property string address: ""
    // "" picks the note by state; set it to override
    property string ipNote: ""
    property bool reachableOutside: false
    property bool onLanNow: true
    property string runningApp: ""
    property string defaultApp: "Desktop"
    property int streamWidth: 0
    property int streamHeight: 0
    property int streamFps: 0
    property bool streamHdr: false
    // "ready" | "notSetUp" | "unknown"
    property string wakeFromOff: "unknown"
    property bool updateAvailable: false
    // The first three apps: [{ name, cover (url), running (bool) }]
    property var apps: []
    property url logoSource: "qrc:/res/apollo.png"

    // ---- from the page
    property bool focused: true
    // The ring flares wide for the first moment after a move (only once revealed)
    property bool arriving: false
    // The first-open entrance: settled 120 ms after mount, revealed at 1600 ms. Both true = no entrance
    property bool settled: true
    property bool revealed: true
    // Runs the entrance by itself when the card is created (standalone use)
    property bool autoEntrance: false
    // The shared animation clock (the page's 1100 ms counter); -1 = use the card's own
    property int sharedTick: -1
    // False stops all ambient motion (the page turns it off when the window is hidden)
    property bool motion: true

    readonly property alias hovered: cardHover.hovered

    signal primaryClicked(string action)
    signal quietClicked(string action)
    signal moreClicked()
    signal copyAddressClicked(string address)
    signal updateApolloClicked()
    signal tileClicked(int index, var app)
    // The All apps tile: where its center is, in the card's coordinates, for the page's grow-out
    signal allAppsClicked(point origin)
    // The card was clicked while not focused
    signal picked()

    readonly property bool dark: ForkTheme.dark
    readonly property string stateId: CardText.normalizeState(state)
    readonly property var hue: ForkTheme.hue(stateId === "notPaired" ? "gray" : hueKey)
    readonly property color tileDisc: hue.tile
    readonly property color tileInk: hue.tileInk
    readonly property bool animating: motion && visible && !ForkTheme.reduceMotion && width > 0
    readonly property int tick: animating ? (sharedTick >= 0 ? sharedTick : ownClock.tick) : 0
    readonly property int ph: tick % 2

    readonly property var info: CardText.describe({
        state: state, name: pcName, version: version, network: network, latencyMs: latencyMs,
        address: address, runningApp: runningApp, defaultApp: defaultApp, streamWidth: streamWidth,
        streamHeight: streamHeight, streamFps: streamFps, streamHdr: streamHdr, wakeFromOff: wakeFromOff,
        updateAvailable: updateAvailable, reachableOutside: reachableOutside, onLanNow: onLanNow,
        dark: dark, ipNote: ipNote !== "" ? ipNote : undefined
    })

    function stateInk(key) {
        switch (key) {
        case "green": return ForkTheme.st.green
        case "blue": return ForkTheme.st.blue
        case "purple": return ForkTheme.st.purple
        case "gold": return ForkTheme.st.gold
        case "orange": return ForkTheme.st.orange
        case "red": return ForkTheme.st.red
        case "text2": return ForkTheme.cv.text2
        }
        return CardText.stateColor(key, dark)
    }
    function iconPath(name) { return CardText.ICONS[name] || "" }

    width: 560
    height: 540
    implicitWidth: 560
    implicitHeight: 540

    Accessible.role: Accessible.Pane
    Accessible.name: pcName

    ForkCardClock {
        id: ownClock
        running: card.animating && card.sharedTick < 0
    }

    Timer {
        id: settleTimer
        interval: 120
        onTriggered: card.settled = true
    }
    Timer {
        id: revealTimer
        interval: 1600
        onTriggered: card.revealed = true
    }
    Component.onCompleted: {
        if (autoEntrance && !ForkTheme.reduceMotion) {
            settled = false
            revealed = false
            settleTimer.start()
            revealTimer.start()
        }
    }

    // ---- the shadow, the focus ring and the flare
    readonly property real shY: !focused ? 18 : (hovered ? 36 : 26)
    readonly property real shBlur: !focused ? 44 : (hovered ? 80 : 60)
    readonly property real shAlpha: dark ? (!focused ? 0.45 : (hovered ? 0.7 : 0.6)) : (!focused ? 0.10 : (hovered ? 0.26 : 0.18))
    readonly property real ringW: !focused ? 0 : (arriving && revealed && !settled ? 9 : 2)
    readonly property real ringAlpha: ringW > 2 ? 0.25 : 1

    RectangularShadow {
        anchors.fill: face
        offset.y: card.shY
        blur: card.shBlur
        radius: 24
        color: card.dark ? Qt.rgba(0, 0, 0, card.shAlpha) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, card.shAlpha)
        Behavior on offset.y { NumberAnimation { duration: card.arriving ? 0 : 750; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
        Behavior on blur { NumberAnimation { duration: card.arriving ? 0 : 750; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
    }

    Rectangle {
        id: ring
        property real w: card.ringW
        property real a: card.ringAlpha
        Behavior on w { NumberAnimation { duration: card.arriving ? 0 : 750; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
        Behavior on a { NumberAnimation { duration: card.arriving ? 0 : 750; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
        visible: w > 0.01
        x: -w; y: -w; width: card.width + 2 * w; height: card.height + 2 * w
        radius: 24 + w
        color: "transparent"
        border.width: w
        border.color: Qt.alpha(card.hue.fill, a)
    }

    // ---- the card
    Rectangle {
        id: face
        anchors.fill: parent
        radius: 24
        color: ForkTheme.cv.surface
        border.width: 1
        border.color: ForkTheme.cv.line
    }

    HoverHandler {
        id: cardHover
        enabled: card.focused
    }

    Item {
        id: inner
        anchors.fill: parent
        enabled: card.focused

        // ---- header band (558 x 104, inside the border)
        Item {
            id: band
            x: 1; y: 1
            width: 558; height: 104
            clip: true

            Rectangle {
                width: parent.width
                height: 104 + 30
                radius: 23
                color: card.hue.sky
            }

            // Stars
            Repeater {
                model: [[338, 20, 2, 0], [392, 74, 2, 1], [420, 16, 3, 1], [532, 84, 2, 0]]
                delegate: Rectangle {
                    required property var modelData
                    x: modelData[0]; y: modelData[1]
                    width: modelData[2]; height: modelData[2]; radius: modelData[2] / 2
                    color: "white"
                    opacity: (modelData[3] === 0) === (card.ph === 1) ? 0.75 : 0.3
                    Behavior on opacity { NumberAnimation { duration: 1100; easing.type: Easing.Bezier; easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1] } }
                }
            }

            ForkCardMoon {
                kind: card.info.moon
                tick: card.tick
                breathe: card.stateId === "streaming"
                sky: card.hue.sky
            }

            Image {
                id: logo
                x: 17; y: 23
                width: 58; height: 58
                source: card.logoSource
                sourceSize.width: 116
                sourceSize.height: 116
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                visible: false
            }
            MultiEffect {
                source: logo
                anchors.fill: logo
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.35)
                shadowBlur: 0.4
                shadowVerticalOffset: 6
                shadowOpacity: 1
                autoPaddingEnabled: true
            }

            Column {
                id: texts
                x: 86
                y: (104 - height) / 2
                spacing: 4
                Text {
                    width: Math.min(360, implicitWidth)
                    text: card.pcName
                    elide: Text.ElideRight
                    color: "white"
                    font.family: ForkTheme.uiFamily; font.pixelSize: 22; font.weight: 700
                    font.letterSpacing: -0.33
                    lineHeightMode: Text.FixedHeight; lineHeight: 28
                }
                Text {
                    width: Math.min(360, implicitWidth)
                    text: card.info.subLine
                    elide: Text.ElideRight
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.family: ForkTheme.uiFamily; font.pixelSize: 13; font.weight: 400
                    lineHeightMode: Text.FixedHeight; lineHeight: 17
                }
                Item {
                    width: 360
                    height: 22
                    Rectangle {
                        id: ipChip
                        height: 22
                        width: ipRow.implicitWidth + 11
                        radius: 11
                        color: Qt.rgba(1, 1, 1, 0.13)
                        Row {
                            id: ipRow
                            x: 8
                            height: parent.height
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "IP"
                                color: "white"; opacity: 0.7
                                font.family: ForkTheme.uiFamily; font.pixelSize: 10; font.weight: 700
                                font.letterSpacing: 0.6
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.address
                                color: "white"
                                font.family: ForkTheme.monoFamily; font.pixelSize: 12
                            }
                            Item {
                                id: copyBtn
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: 0.8
                                Accessible.role: Accessible.Button
                                Accessible.name: "Copy the IP address of " + card.pcName
                                Accessible.onPressAction: card.copyAddressClicked(card.address)
                                ForkCardIcon {
                                    anchors.centerIn: parent
                                    path: card.iconPath("copy")
                                    size: 12; color: "white"; strokeWidth: 2.2
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: card.copyAddressClicked(card.address) }
                            }
                        }
                    }
                    Text {
                        anchors.left: ipChip.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 360 - ipChip.width - 8)
                        text: card.info.ipNote
                        elide: Text.ElideRight
                        color: Qt.rgba(1, 1, 1, 0.62)
                        font.family: ForkTheme.uiFamily; font.pixelSize: 11.5
                    }
                }
            }
        }

        // ---- body
        Column {
            id: body
            x: 21; y: 123
            width: 518
            spacing: 18

            ForkCardEnter {
                shown: card.settled || card.revealed
                revealed: card.revealed
                delay: 60
                Rectangle {
                    width: 518; height: 63
                    radius: 14
                    color: Qt.rgba(card.info.tint.r, card.info.tint.g, card.info.tint.b, card.info.tint.a)

                    Item {
                        id: disc
                        x: 14; y: 14.5
                        width: 34; height: 34
                        Rectangle { anchors.fill: parent; radius: 17; color: card.info.disc }
                        Rectangle {
                            visible: card.stateId === "streaming"
                            anchors.fill: parent
                            radius: 17
                            color: "transparent"
                            border.width: 2
                            border.color: "#0A6CDB"
                            scale: card.ph ? 1.75 : 1
                            opacity: card.ph ? 0 : 0.8
                            Behavior on scale { enabled: card.ph === 1; NumberAnimation { duration: 1100; easing.type: Easing.OutQuad } }
                            Behavior on opacity { enabled: card.ph === 1; NumberAnimation { duration: 1100; easing.type: Easing.OutQuad } }
                        }
                        ForkCardIcon {
                            id: glyph
                            anchors.centerIn: parent
                            path: card.iconPath(card.info.glyph)
                            size: 18
                            color: card.info.discInk
                            filled: card.info.glyphFill
                            strokeWidth: 1.9
                            rotation: card.stateId === "asleep" ? (card.ph ? -12 : 8) : 0
                            Behavior on rotation { enabled: card.stateId === "asleep"; NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
                            RotationAnimator on rotation {
                                running: card.stateId === "waking" && card.animating
                                from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                            }
                        }
                    }

                    Column {
                        x: 60
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: Math.min(implicitWidth, 518 - 60 - 14 - statusLabel.implicitWidth - 12)
                            text: card.info.title
                            elide: Text.ElideRight
                            color: ForkTheme.cv.text
                            font.family: ForkTheme.uiFamily; font.pixelSize: 15; font.weight: 650
                            lineHeightMode: Text.FixedHeight; lineHeight: 20
                        }
                        Text {
                            width: Math.min(implicitWidth, 518 - 60 - 14 - statusLabel.implicitWidth - 12)
                            text: card.info.sub
                            elide: Text.ElideRight
                            color: ForkTheme.cv.muted
                            font.family: ForkTheme.uiFamily; font.pixelSize: 12.5
                            lineHeightMode: Text.FixedHeight; lineHeight: 17
                        }
                    }
                    Text {
                        id: statusLabel
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.info.label
                        color: card.stateInk(card.info.labelKey)
                        font.family: ForkTheme.uiFamily; font.pixelSize: 11; font.weight: 700
                        font.letterSpacing: 0.66
                        font.capitalization: Font.AllUppercase
                    }
                }
            }

            // Apps
            Column {
                visible: card.info.showApps
                spacing: 10
                ForkCardEnter {
                    shown: card.settled || card.revealed
                    revealed: card.revealed
                    delay: 130
                    Item {
                        width: 518
                        height: card.info.tilesNote !== "" ? 15 : 14
                        Text {
                            id: appsTitle
                            text: card.info.tilesTitle
                            color: ForkTheme.cv.faint
                            font.family: ForkTheme.uiFamily; font.pixelSize: 11; font.weight: 700
                            font.letterSpacing: 0.88
                            font.capitalization: Font.AllUppercase
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.baseline: appsTitle.baseline
                            text: card.info.tilesNote
                            color: ForkTheme.cv.muted
                            font.family: ForkTheme.uiFamily; font.pixelSize: 12
                        }
                    }
                }
                Row {
                    spacing: 14
                    Repeater {
                        model: Math.min(card.apps.length, 3) + 1
                        delegate: ForkCardEnter {
                            id: tileEnter
                            required property int index
                            readonly property bool isAll: index === Math.min(card.apps.length, 3)
                            readonly property var app: isAll ? null : card.apps[index]
                            shown: card.settled || card.revealed
                            revealed: card.revealed
                            delay: 180 + 60 * index
                            ForkCardTile {
                                width: 119
                                name: tileEnter.isAll ? "All apps" : tileEnter.app.name
                                accessibleName: (tileEnter.isAll ? "All apps" : tileEnter.app.name)
                                                + (card.info.sleepy ? ", wakes " + card.pcName + " first" : "")
                                cover: tileEnter.isAll ? "" : (tileEnter.app.cover || "")
                                collage: tileEnter.isAll
                                fan: [card.apps.length > 0 ? card.apps[0].cover : "",
                                      card.apps.length > 1 ? card.apps[1].cover : (card.apps.length > 0 ? card.apps[0].cover : ""),
                                      card.apps.length > 2 ? card.apps[2].cover : (card.apps.length > 0 ? card.apps[0].cover : "")]
                                allNote: card.info.allNote
                                running: !tileEnter.isAll && card.stateId === "streaming" && !!tileEnter.app.running
                                sleepy: card.info.sleepy
                                badge: card.info.badge
                                sky: card.hue.sky
                                ph: card.ph
                                onClicked: {
                                    if (tileEnter.isAll) {
                                        var p = mapToItem(card, width / 2, height / 2)
                                        card.allAppsClicked(Qt.point(p.x, p.y))
                                    } else {
                                        card.tileClicked(tileEnter.index, tileEnter.app)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Pairing steps
            Column {
                visible: card.info.showSteps
                spacing: 10
                ForkCardEnter {
                    shown: card.settled || card.revealed
                    revealed: card.revealed
                    delay: 130
                    Text {
                        text: "How to pair"
                        color: ForkTheme.cv.faint
                        font.family: ForkTheme.uiFamily; font.pixelSize: 11; font.weight: 700
                        font.letterSpacing: 0.88
                        font.capitalization: Font.AllUppercase
                    }
                }
                Repeater {
                    model: card.info.steps
                    delegate: ForkCardEnter {
                        id: stepEnter
                        required property int index
                        required property string modelData
                        shown: card.settled || card.revealed
                        revealed: card.revealed
                        delay: 180 + 70 * index
                        Item {
                            width: 518; height: 24
                            Rectangle {
                                width: 24; height: 24; radius: 12
                                color: card.tileDisc
                                Text {
                                    anchors.centerIn: parent
                                    text: stepEnter.index + 1
                                    color: card.tileInk
                                    font.family: ForkTheme.uiFamily; font.pixelSize: 12; font.weight: 700
                                }
                            }
                            Text {
                                x: 34
                                width: 518 - 34
                                anchors.verticalCenter: parent.verticalCenter
                                text: stepEnter.modelData
                                elide: Text.ElideRight
                                color: ForkTheme.cv.text2
                                font.family: ForkTheme.uiFamily; font.pixelSize: 13.5
                                lineHeightMode: Text.FixedHeight; lineHeight: 19
                            }
                        }
                    }
                }
            }

            // Chips
            ForkCardEnter {
                shown: card.settled || card.revealed
                revealed: card.revealed
                delay: 420
                Flow {
                    width: 518
                    spacing: 6
                    Repeater {
                        model: card.info.chips
                        delegate: ForkCardChip {
                            required property var modelData
                            text: modelData.label
                            iconPath: card.iconPath(modelData.icon)
                            ink: card.stateInk(modelData.colorKey)
                            warm: !!modelData.button
                            onClicked: if (modelData.id === "updateApollo") card.updateApolloClicked()
                        }
                    }
                }
            }
        }

        // ---- actions, pinned to the bottom
        ForkCardEnter {
            x: 21
            y: 540 - 21 - 44
            shown: card.settled || card.revealed
            revealed: card.revealed
            delay: 480
            Item {
                width: 518; height: 44

                Row {
                    spacing: 8
                    Repeater {
                        model: card.info.quiet
                        delegate: ForkCardButton {
                            required property var modelData
                            kind: "quiet"
                            text: modelData.label
                            iconPath: card.iconPath(modelData.icon)
                            iconColor: card.stateInk(modelData.colorKey)
                            onClicked: card.quietClicked(modelData.id)
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    ForkCardButton {
                        kind: "icon"
                        iconPath: card.iconPath("more")
                        accessibleName: "More for " + card.pcName
                        onClicked: card.moreClicked()
                    }
                    ForkCardButton {
                        kind: "primary"
                        hue: card.hue
                        text: card.info.primary.label
                        iconPath: card.iconPath(card.info.primary.icon)
                        iconFilled: !!card.info.primary.fill
                        quietLook: !!card.info.primary.quietLook
                        dimmed: !!card.info.primary.disabled
                        enabled: !card.info.primary.disabled
                        glowWhenHovered: card.focused && card.hovered
                        onClicked: card.primaryClicked(card.info.primary.id)
                    }
                }
            }
        }
    }

    // ---- a click on a card that isn't focused only focuses it
    MouseArea {
        anchors.fill: parent
        visible: !card.focused
        cursorShape: Qt.PointingHandCursor
        Accessible.role: Accessible.Button
        Accessible.name: "Show " + card.pcName
        Accessible.onPressAction: card.picked()
        onClicked: card.picked()
    }
}
