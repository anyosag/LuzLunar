import QtQuick
import QtQuick.Effects
import ForkTheme 1.0

import "ForkPcCardText.js" as CardText

// [fork] The small PC card of the canvas's States board (281 x 238, 64 px header): one status
// box, one chip and one main button with ⋯. The app doesn't show it on a page (the grid scales the
// big card); it's the design's state sheet, and the screenshot harness draws it. Presentational,
// like ForkPcCard; no hover, no ring, no motion.
Item {
    id: card

    property string pcName: ""
    property string hueKey: "indigo"
    // The 9 states of ForkPcCard
    property string cardState: "ready"
    property string address: ""
    property string version: ""
    property string network: "Home network"
    property int latencyMs: -1
    property string runningApp: ""
    property string defaultApp: "Desktop"
    property int streamWidth: 0
    property int streamHeight: 0
    property int streamFps: 0
    property bool updateAvailable: false
    property url logoSource: "qrc:/res/apollo.png"

    signal primaryClicked(string action)
    signal moreClicked()

    readonly property bool dark: ForkTheme.dark
    readonly property string stateId: CardText.normalizeState(cardState)
    readonly property var hue: ForkTheme.hue(stateId === "notPaired" ? "gray" : hueKey)
    readonly property var info: CardText.describeSmall({
        state: cardState, name: pcName, address: address, version: version, network: network,
        latencyMs: latencyMs, runningApp: runningApp, defaultApp: defaultApp, streamWidth: streamWidth,
        streamHeight: streamHeight, streamFps: streamFps, updateAvailable: updateAvailable, dark: dark
    })

    function stateInk(key) {
        switch (key) {
        case "green": return ForkTheme.st.green
        case "orange": return ForkTheme.st.orange
        case "text2": return ForkTheme.cv.text2
        }
        return CardText.stateColor(key, dark)
    }

    width: 281
    height: 238
    implicitWidth: 281
    implicitHeight: 238

    Accessible.role: Accessible.Pane
    Accessible.name: pcName + ", " + (CardText.STATE_TITLES[stateId] || "")

    RectangularShadow {
        anchors.fill: face
        offset.y: card.dark ? 14 : 10
        blur: card.dark ? 36 : 28
        radius: 18
        color: card.dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.10)
    }
    Rectangle {
        id: face
        anchors.fill: parent
        radius: 18
        color: ForkTheme.cv.surface
        border.width: 1
        border.color: ForkTheme.cv.line
    }

    // ---- header band
    Item {
        x: 1; y: 1
        width: 279; height: 64
        clip: true

        Rectangle {
            width: parent.width
            height: 64 + 20
            radius: 17
            color: card.hue.sky
        }
        Rectangle { x: 176; y: 12; width: 2; height: 2; radius: 1; color: Qt.rgba(1, 1, 1, 0.5) }
        Rectangle { x: 198; y: 48; width: 2; height: 2; radius: 1; color: Qt.rgba(1, 1, 1, 0.35) }
        Rectangle { x: 264; y: 16; width: 2; height: 2; radius: 1; color: Qt.rgba(1, 1, 1, 0.45) }

        ForkCardMoonSmall {
            kind: card.info.moon
            sky: card.hue.sky
        }

        Image {
            id: logo
            x: 11; y: 11
            width: 42; height: 42
            source: card.logoSource
            sourceSize.width: 84
            sourceSize.height: 84
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
            shadowBlur: 0.25
            shadowVerticalOffset: 4
            shadowOpacity: 1
        }
        Column {
            x: 60
            y: (64 - height) / 2
            spacing: 1
            ForkCanvasText {
                width: Math.min(150, implicitWidth)
                text: card.pcName
                elide: Text.ElideRight
                color: "white"
                px: 15; weight: 700; lineHeightPx: 20
            }
            ForkCanvasText {
                width: Math.min(150, implicitWidth)
                text: card.info.host
                elide: Text.ElideRight
                color: Qt.rgba(1, 1, 1, 0.75)
                px: 11.5
            }
        }
    }

    // ---- body
    Rectangle {
        id: status
        x: 13; y: 77
        width: 255
        height: 20 + Math.max(28, textCol.height)
        radius: 12
        color: Qt.rgba(card.info.tint.r, card.info.tint.g, card.info.tint.b, card.info.tint.a)

        Rectangle {
            x: 10; y: 10; width: 28; height: 28; radius: 14
            color: card.info.disc
            ForkCardIcon {
                anchors.centerIn: parent
                path: CardText.ICONS[card.info.glyph]
                size: 15
                color: card.info.discInk
                filled: card.info.glyphFill
                strokeWidth: 2
            }
        }
        Column {
            id: textCol
            x: 48; y: 10
            width: 197
            spacing: 2
            ForkCanvasText {
                width: parent.width
                text: card.info.headline
                color: ForkTheme.cv.text
                px: 13.5; weight: 650; lineHeightPx: 18
            }
            ForkCanvasText {
                width: parent.width
                text: card.info.sub
                wrapMode: Text.WordWrap
                color: ForkTheme.cv.muted
                px: 11.5; lineHeightPx: 16
            }
        }
    }

    ForkCardChip {
        visible: card.info.chip !== null
        x: 13; y: status.y + status.height + 10
        big: false
        text: card.info.chip ? card.info.chip.label : ""
        iconPath: card.info.chip ? CardText.ICONS[card.info.chip.icon] : ""
        ink: card.info.chip ? card.stateInk(card.info.chip.colorKey) : "white"
        warm: card.info.chip ? !!card.info.chip.warm : false
    }

    // The row sits at the bottom, but under a two-line sub it overflows the padding by 4 px
    Row {
        x: 13
        y: Math.max(189, status.y + status.height + 10 + (card.info.chip ? 24 + 10 : 0))
        spacing: 6
        ForkCardButton {
            big: false
            kind: "primary"
            width: 213
            hue: card.hue
            text: card.info.action.label
            iconPath: CardText.ICONS[card.info.action.icon] || ""
            iconFilled: !!card.info.action.fill
            quietLook: !!card.info.action.quietLook
            dimmed: !!card.info.action.disabled
            enabled: !card.info.action.disabled
            onClicked: card.primaryClicked(card.info.action.id)
        }
        ForkCardButton {
            big: false
            kind: "icon"
            iconPath: CardText.ICONS.more
            accessibleName: "More for " + card.pcName
            onClicked: card.moreClicked()
        }
    }
}
