pragma Singleton
import QtQuick

import WindowChrome 1.0

// [fork] LuzLunar's look, from the design canvas: the "Night" palette in dark mode and "Day" in
// light mode, the system font (SF Pro) for text and titles, and SF Mono for numbers. Registered
// as the ForkTheme singleton in forkqml.cpp.
QtObject {
    id: theme

    // Follows the system appearance; Qt.ColorScheme.Light is 1 (Unknown counts as dark, the default look)
    readonly property bool dark: Qt.styleHints.colorScheme !== 1

    // Grounds and surfaces
    readonly property color bg: dark ? "#0A0E1C" : "#EEF0F7"
    readonly property color bar: dark ? "#0E1328" : "#E4E7F1"
    readonly property color surface: dark ? "#121831" : "#FFFFFF"
    readonly property color raised: dark ? "#1A2142" : "#E8EBF4"
    readonly property color tile: dark ? "#1E2650" : "#DCE1EF"

    // A selected option's fill and edge, and the segmented control's track and selected segment
    readonly property color sel: dark ? "#18204A" : "#FFF4DD"
    readonly property color selEdge: dark ? "#F5C878" : "#A86B0C"
    readonly property color seg: dark ? "#0E1328" : "#E4E7F1"
    readonly property color segOn: dark ? "#232C5C" : "#FFFFFF"

    // Lines
    readonly property color line: dark ? "#262E52" : "#D3D8E8"
    readonly property color lineSoft: dark ? "#1F2747" : "#E0E4EF"
    readonly property color lineStrong: dark ? "#34407A" : "#B8C0D6"

    // Text
    readonly property color text: dark ? "#ECEEF6" : "#121733"
    readonly property color text2: dark ? "#C4CADC" : "#2E3557"
    readonly property color muted: dark ? "#A3ABC6" : "#525A7A"
    readonly property color faint: dark ? "#8C94B2" : "#646C8C"

    // Moonlight gold: a fill (accent), text and strokes on surfaces (accentInk), text on the fill
    readonly property color accent: dark ? "#F5C878" : "#F2BE5C"
    readonly property color accentInk: dark ? "#F5C878" : "#84550B"
    readonly property color textOnAccent: "#1A1405"
    // The moon mark drawn without its tile
    readonly property color markInk: dark ? "#F5C878" : "#A8720F"
    // The app icon's tile, the same in both modes
    readonly property color markTile: "#0E1430"

    // A PC's own color on the page of its apps: the band at the top (pcSky, in both modes) and its
    // main button, focus ring and play disc (pcFill). Every PC has the design's Indigo for now.
    readonly property color pcFill: "#5E5CE6"
    readonly property color pcSky: "#17163F"

    // The app that's running: its ring and glow, and its badge
    readonly property color running: dark ? "#409CFF" : "#0A6CDB"
    readonly property color runningBadge: "#0A6CDB"

    // States
    readonly property color ok: dark ? "#79D6B5" : "#16805D"
    readonly property color chipScrim: dark ? Qt.rgba(10 / 255, 14 / 255, 28 / 255, 0.74) : Qt.rgba(1, 1, 1, 0.88)
    readonly property color warnBg: dark ? "#2A1E14" : "#FFF2DC"
    readonly property color warnLine: dark ? "#5A3E1E" : "#EBC57E"
    readonly property color warnText: dark ? "#FFDDB0" : "#5C3A0A"
    readonly property color warnIcon: dark ? "#F5C878" : "#A86B0C"
    readonly property color danger: dark ? "#FFB4B4" : "#A8283A"
    readonly property color dangerLine: dark ? "#4A2A33" : "#E8B4BC"

    // Switches
    readonly property color trackOff: dark ? "#1A2142" : "#D3D8E8"
    readonly property color trackEdge: dark ? "#4A5585" : "#A7AEC6"
    readonly property color knobOff: dark ? "#C4CADC" : "#FFFFFF"
    readonly property color knobOn: dark ? "#0A0E1C" : "#1A1405"

    // Behind modal dialogs, under panels that float (dialogs, menus, lists), and the toast
    readonly property color scrim: dark ? Qt.rgba(5 / 255, 7 / 255, 15 / 255, 0.62) : Qt.rgba(18 / 255, 23 / 255, 51 / 255, 0.36)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(18 / 255, 23 / 255, 51 / 255, 0.18)
    readonly property color toastBg: dark ? "#ECEEF6" : "#121733"
    readonly property color toastText: dark ? "#0A0E1C" : "#FFFFFF"

    // The system's Reduce Motion setting: animations that loop or move things stop when it's on
    readonly property bool reduceMotion: WindowChrome.reduceMotion

    // Fonts: the system font, and SF Mono where it's installed (Menlo otherwise)
    readonly property string uiFamily: Qt.application.font.family
    readonly property string monoFamily: Qt.fontFamilies().indexOf("SF Mono") >= 0 ? "SF Mono" : "Menlo"

    // Corner radii: cards and dialogs, buttons and fields, option cards and tiles, floating menus
    readonly property real radiusCard: 20
    readonly property real radiusControl: 12
    readonly property real radiusTile: 14
    readonly property real radiusMenu: 14

    // The height of buttons, fields, drop-downs and sidebar items
    readonly property real controlHeight: 44

    // The gap between cards, a card's padding, and the gap between the blocks inside a card
    readonly property real gap: 20
    readonly property real cardPadding: 22
    readonly property real cardSpacing: 22

    // The pages' content column: at most this wide, centered, with at least 24 on each side
    readonly property real contentMaxWidth: 1152

    // [fork] The redesign canvas ("LuzLunar · Your PCs, redesigned"): Your PCs, All apps, Customize
    // and the first run use these. cv is the canvas's t tokens, st its S state colors; hue() a PC's
    // own color. The older tokens above stay for the pages the canvas doesn't cover.
    readonly property QtObject cv: QtObject {
        id: cvObj
        readonly property color bg: theme.dark ? "#0D0F17" : "#F2F2F7"
        readonly property color bar: theme.dark ? "#141722" : "#FAFAFC"
        readonly property color barGlass: theme.dark ? Qt.rgba(16 / 255, 19 / 255, 32 / 255, 0.55) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.62)
        readonly property color surface: theme.dark ? "#161925" : "#FFFFFF"
        readonly property color raised: theme.dark ? "#1E2230" : "#F6F6F9"
        readonly property color chip: theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.045)
        readonly property color glass: theme.dark ? Qt.rgba(1, 1, 1, 0.07) : "#FFFFFF"
        readonly property color line: theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color lineStrong: theme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.18)
        readonly property color text: theme.dark ? "#F2F3F7" : "#1D1D1F"
        readonly property color text2: theme.dark ? "#C9CCD8" : "#3A3A42"
        readonly property color muted: theme.dark ? "#9EA3B5" : "#5F616E"
        readonly property color faint: theme.dark ? "#868B9E" : "#6B6D7B"
        readonly property color menu: theme.dark ? "#1F2230" : "#FCFCFE"
        readonly property color gold: theme.dark ? "#F5C878" : "#A8720F"
        // The ring around the discovery pill's dot, and the menu's highlighted row
        readonly property color discRing: theme.dark ? Qt.rgba(48 / 255, 209 / 255, 88 / 255, 0.18) : Qt.rgba(26 / 255, 127 / 255, 55 / 255, 0.14)
        readonly property color menuHi: "#0A6CDB"
    }

    readonly property QtObject st: QtObject {
        id: stObj
        readonly property color green: theme.dark ? "#30D158" : "#1A7F37"
        readonly property color blue: theme.dark ? "#409CFF" : "#0062CC"
        readonly property color purple: theme.dark ? "#C17DF5" : "#8E3BB8"
        readonly property color gold: theme.dark ? "#F5C878" : "#8A5A00"
        readonly property color orange: theme.dark ? "#FF9F0A" : "#A85A00"
        readonly property color red: theme.dark ? "#FF6961" : "#C1272D"
        // The States board's two extra state colors: Waking and Off
        readonly property color amber: theme.dark ? "#FFB340" : "#9A5B00"
        readonly property color gray: theme.dark ? "#9EA3B5" : "#5F616E"
    }

    // A PC's color by key: fill (its main button, focus ring, switches), onFill (text and icons on
    // the fill), tile (its tiles' tint, and the pairing-step discs), tileInk (text on the tile) and
    // sky (its card's header band). Bindings that call it follow the theme. The 10 Customize colors
    // (card.md 2.1) and gray, the color of a PC that isn't paired.
    function hue(key) {
        switch (key) {
        case "blue":
            return { fill: "#0A6CDB", onFill: "#FFFFFF", tile: "#0A6CDB", tileInk: "#FFFFFF", sky: "#0B1F3D" }
        case "purple":
            return { fill: "#9B45D9", onFill: "#FFFFFF", tile: "#9B45D9", tileInk: "#FFFFFF", sky: "#24123A" }
        case "red":
            return { fill: "#C62828", onFill: "#FFFFFF", tile: "#C62828", tileInk: "#FFFFFF", sky: "#36100F" }
        case "orange":
            return { fill: "#B85800", onFill: "#FFFFFF", tile: "#B85800", tileInk: "#FFFFFF", sky: "#33200C" }
        case "gold":
            return { fill: "#F5C878", onFill: "#1A1405", tile: "#F5C878", tileInk: "#1A1405", sky: "#2B2410" }
        case "green":
            return { fill: "#1E7B34", onFill: "#FFFFFF", tile: "#1E7B34", tileInk: "#FFFFFF", sky: "#0E2A17" }
        case "graphite":
            return { fill: "#4B4F5C", onFill: "#FFFFFF", tile: "#4B4F5C", tileInk: "#FFFFFF", sky: "#1A1C24" }
        case "teal":
            return { fill: dark ? "#40C8E0" : "#0E7C93", onFill: dark ? "#05232B" : "#FFFFFF", tile: "#0E7C93", tileInk: "#FFFFFF", sky: "#0A2A33" }
        case "pink":
            return { fill: "#D7264B", onFill: "#FFFFFF", tile: "#D7264B", tileInk: "#FFFFFF", sky: "#36111F" }
        case "gray":
            // A PC that isn't paired yet stays grey: it isn't one of yours until it's paired
            return { fill: dark ? "#5A5E6E" : "#4B4F5C", onFill: "#FFFFFF", tile: dark ? "#5A5E6E" : "#4B4F5C", tileInk: "#FFFFFF", sky: "#202229" }
        case "indigo":
        default:
            return { fill: "#5E5CE6", onFill: "#FFFFFF", tile: "#5E5CE6", tileInk: "#FFFFFF", sky: "#17163F" }
        }
    }

    // The 10 colors of Customize in the canvas's order: key, name, the swatch's fill (the same in
    // both themes: teal's swatch is its light fill) and the sky behind it. gray isn't a choice.
    readonly property var pcPalette: [
        { key: "indigo", name: "Indigo", fill: "#5E5CE6", sky: "#17163F" },
        { key: "blue", name: "Blue", fill: "#0A6CDB", sky: "#0B1F3D" },
        { key: "purple", name: "Purple", fill: "#9B45D9", sky: "#24123A" },
        { key: "pink", name: "Pink", fill: "#D7264B", sky: "#36111F" },
        { key: "red", name: "Red", fill: "#C62828", sky: "#36100F" },
        { key: "orange", name: "Orange", fill: "#B85800", sky: "#33200C" },
        { key: "gold", name: "Moon gold", fill: "#F5C878", sky: "#2B2410" },
        { key: "green", name: "Green", fill: "#1E7B34", sky: "#0E2A17" },
        { key: "teal", name: "Teal", fill: "#0E7C93", sky: "#0A2A33" },
        { key: "graphite", name: "Graphite", fill: "#4B4F5C", sky: "#1A1C24" }
    ]

    // The order a newly paired PC takes its color in (card.md 2.2): the first not used yet
    readonly property var defaultHueOrder: ["indigo", "teal", "blue", "pink", "purple", "orange", "green", "red", "gold", "graphite"]

    // The default color key for the n-th paired PC (0-based, wraps after 10), or, given a key,
    // that key when it is one of the 10 colors and indigo otherwise
    function defaultHue(indexOrKey) {
        if (typeof indexOrKey === "string")
            return defaultHueOrder.indexOf(indexOrKey) >= 0 ? indexOrKey : "indigo"
        var n = defaultHueOrder.length
        var i = Math.floor(Number(indexOrKey))
        if (isNaN(i))
            i = 0
        return defaultHueOrder[((i % n) + n) % n]
    }

    // ---- Card states (card.md 1, 3.4, 5.3, 6) ----
    component StateStyle: QtObject {
        // The status disc, its glyph's ink, the status box's tint, the label's ink, the label
        // text, the glyph's icon name (ForkPathIcon) and whether it is drawn filled
        property color disc
        property color ink
        property color tint
        property color labelInk
        property string label
        property string glyph
        property bool glyphFilled: false
    }
    // Tint: the state's color at 0.13 in dark and 0.08 in light, except Off. Streaming, Asleep and
    // Not paired use the big card's own values (Main.dc.html 675, 726, 767), which the canvas sets
    // apart from this formula in light, and for Not paired in dark too.
    function stateTint(r, g, b) {
        return Qt.rgba(r / 255, g / 255, b / 255, dark ? 0.13 : 0.08)
    }
    readonly property QtObject states: QtObject {
        id: statesObj
        readonly property StateStyle ready: StateStyle { disc: "#248A3D"; ink: "#FFFFFF"; tint: theme.stateTint(48, 209, 88); labelInk: stObj.green; label: "Ready"; glyph: "tick" }
        readonly property StateStyle streaming: StateStyle { disc: "#0A6CDB"; ink: "#FFFFFF"; tint: theme.dark ? theme.stateTint(64, 156, 255) : Qt.rgba(0, 98 / 255, 204 / 255, 0.08); labelInk: stObj.blue; label: "Streaming"; glyph: "play"; glyphFilled: true }
        readonly property StateStyle waking: StateStyle { disc: "#B85800"; ink: "#FFFFFF"; tint: theme.stateTint(255, 179, 64); labelInk: stObj.amber; label: "Waking"; glyph: "spinner" }
        readonly property StateStyle asleep: StateStyle { disc: "#9B45D9"; ink: "#FFFFFF"; tint: theme.dark ? theme.stateTint(193, 125, 245) : Qt.rgba(142 / 255, 59 / 255, 184 / 255, 0.08); labelInk: stObj.purple; label: "Asleep"; glyph: "moon" }
        readonly property StateStyle off: StateStyle { disc: "#636366"; ink: "#FFFFFF"; tint: theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05); labelInk: stObj.gray; label: "Off"; glyph: "power" }
        readonly property StateStyle offNoWake: off
        readonly property StateStyle pair: StateStyle { disc: "#F5C878"; ink: "#1A1405"; tint: theme.dark ? Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.12) : Qt.rgba(168 / 255, 114 / 255, 15 / 255, 0.09); labelInk: stObj.gold; label: "Not paired"; glyph: "lock" }
        readonly property StateStyle lost: StateStyle { disc: "#C62828"; ink: "#FFFFFF"; tint: theme.stateTint(255, 105, 97); labelInk: stObj.red; label: "Can’t reach"; glyph: "noWifi" }
    }
    // A card state's style by key: ready streaming waking asleep off offNoWake pair lost
    function stateStyle(key) {
        switch (key) {
        case "streaming": return statesObj.streaming
        case "waking": return statesObj.waking
        case "asleep": return statesObj.asleep
        case "off": return statesObj.off
        case "offNoWake": return statesObj.offNoWake
        case "pair": return statesObj.pair
        case "lost": return statesObj.lost
        case "ready":
        default: return statesObj.ready
        }
    }

    // Colors that are the same in both themes (card.md 1.4)
    readonly property QtObject fixedColors: QtObject {
        readonly property color white: "#FFFFFF"
        readonly property color running: "#0A6CDB"
        readonly property color runningRing: "#409CFF"
        readonly property color sleepyBadge: "#9B45D9"
        readonly property color moonLit: "#F5C878"
        readonly property color moonInk: "#1A1405"
        readonly property color moonAsleep: "#CFC8F3"
        readonly property color moonWaking: "#FFC46B"
        readonly property color offRing: Qt.rgba(207 / 255, 200 / 255, 243 / 255, 0.45)
        readonly property color pairRing: Qt.rgba(245 / 255, 200 / 255, 120 / 255, 0.75)
        readonly property color lostRing: Qt.rgba(255 / 255, 105 / 255, 97 / 255, 0.7)
        readonly property color lostMark: Qt.rgba(255 / 255, 105 / 255, 97 / 255, 0.9)
    }

    // The warm "Update Apollo" chip
    readonly property color warmChipBg: dark ? Qt.rgba(255 / 255, 159 / 255, 10 / 255, 0.12) : Qt.rgba(168 / 255, 90 / 255, 0, 0.07)
    readonly property color warmChipLine: dark ? Qt.rgba(255 / 255, 159 / 255, 10 / 255, 0.4) : Qt.rgba(168 / 255, 90 / 255, 0, 0.3)

    // The States board's tokens (card.md 1.2): the same colors as cv, with its own card shadow
    readonly property QtObject statesBoard: QtObject {
        readonly property color bg: cvObj.bg
        readonly property color surface: cvObj.surface
        readonly property color chip: cvObj.chip
        readonly property color line: cvObj.line
        readonly property color text: cvObj.text
        readonly property color text2: cvObj.text2
        readonly property color muted: cvObj.muted
        readonly property color faint: cvObj.faint
        readonly property ShadowSpec shadow: ShadowSpec { y: theme.dark ? 14 : 10; blur: theme.dark ? 36 : 28; color: theme.dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.10) }
    }

    // ---- Shadows as data: a CSS box-shadow `0 <y>px <blur>px <color>` ----
    component ShadowSpec: QtObject {
        property real x: 0
        property real y: 0
        property real blur: 0
        property real spread: 0
        property color color: "transparent"
    }
    // A PC card at rest, focused, and lifted (sky-chrome.md 3.1, card.md 1.1)
    readonly property ShadowSpec cardShadow: ShadowSpec { y: theme.dark ? 18 : 12; blur: theme.dark ? 44 : 32; color: theme.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.10) }
    readonly property ShadowSpec focusShadow: ShadowSpec { y: theme.dark ? 26 : 22; blur: theme.dark ? 60 : 54; color: theme.dark ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.18) }
    readonly property ShadowSpec liftShadow: ShadowSpec { y: theme.dark ? 36 : 32; blur: theme.dark ? 80 : 70; color: theme.dark ? Qt.rgba(0, 0, 0, 0.7) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.26) }
    // An app tile at rest and hovered (card.md 1.1)
    readonly property ShadowSpec tileShadow: ShadowSpec { y: 8; blur: 18; color: theme.dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.14) }
    readonly property ShadowSpec tileLiftShadow: ShadowSpec { y: 14; blur: 28; color: theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(24 / 255, 26 / 255, 46 / 255, 0.22) }
    // The heading's text shadow (dark only): 0 2px 16px
    readonly property ShadowSpec textShadow: ShadowSpec { y: 2; blur: 16; color: theme.dark ? Qt.rgba(5 / 255, 7 / 255, 15 / 255, 0.75) : "transparent" }

    // ---- Type scale: font size (px), weight (CSS numeric), letter spacing (absolute px, em x size)
    // and line height (px, 0 = normal). Names say where the boards use them.
    component TypeStyle: QtObject {
        property real size: 13
        property int weight: 400
        property real spacing: 0
        property real lineHeight: 0
        property bool upper: false
    }
    readonly property QtObject ty: QtObject {
        // "Your PCs": carousel.md 42/48, 750, -0.03em
        readonly property TypeStyle display: TypeStyle { size: 42; weight: 750; spacing: -1.26; lineHeight: 48 }
        // "Let's find your PC": customize-empty.md 34/40, 700, -0.022em
        readonly property TypeStyle title34: TypeStyle { size: 34; weight: 700; spacing: -0.748; lineHeight: 40 }
        // A PC's name on its apps page: library.md 28/34, 750, -0.02em
        readonly property TypeStyle title28: TypeStyle { size: 28; weight: 750; spacing: -0.56; lineHeight: 34 }
        // "All apps": library.md 26/32, 750, -0.02em
        readonly property TypeStyle title26: TypeStyle { size: 26; weight: 750; spacing: -0.52; lineHeight: 32 }
        // The card's name and "Add a PC": card.md 22/28, 700, -0.015em
        readonly property TypeStyle cardName: TypeStyle { size: 22; weight: 700; spacing: -0.33; lineHeight: 28 }
        // "Customize GonzaloPC": customize-empty.md 19/24, 700, -0.01em
        readonly property TypeStyle dialogTitle: TypeStyle { size: 19; weight: 700; spacing: -0.19; lineHeight: 24 }
        // The status title: card.md 15/20, 650; its sub 12.5/17, 400
        readonly property TypeStyle statusTitle: TypeStyle { size: 15; weight: 650; lineHeight: 20 }
        readonly property TypeStyle statusSub: TypeStyle { size: 12.5; weight: 400; lineHeight: 17 }
        // "LuzLunar" in the header: sky-chrome.md 14, 600, -0.01em
        readonly property TypeStyle brand: TypeStyle { size: 14; weight: 600; spacing: -0.14 }
        // Greeting line: carousel.md 11.5/16, 700, 0.12em, uppercase
        readonly property TypeStyle greeting: TypeStyle { size: 11.5; weight: 700; spacing: 1.38; lineHeight: 16; upper: true }
        // "Tonight's moon", "Now running": 10.5, 700, 0.12em, uppercase
        readonly property TypeStyle eyebrow: TypeStyle { size: 10.5; weight: 700; spacing: 1.26; lineHeight: 14; upper: true }
        // "This Mac": sky-chrome.md 10.5, 700, 0.08em, uppercase
        readonly property TypeStyle groupLabel: TypeStyle { size: 10.5; weight: 700; spacing: 0.84; upper: true }
        // Section titles (APPS, HOW TO PAIR): card.md 11, 700, 0.08em, uppercase
        readonly property TypeStyle sectionTitle: TypeStyle { size: 11; weight: 700; spacing: 0.88; upper: true }
        // The status label (STREAMING): card.md 11, 700, 0.06em, uppercase
        readonly property TypeStyle statusLabel: TypeStyle { size: 11; weight: 700; spacing: 0.66; upper: true }
        // The "IP" tag: card.md 10, 700, 0.06em
        readonly property TypeStyle ipTag: TypeStyle { size: 10; weight: 700; spacing: 0.6 }
        // A menu item's badge (New): carousel.md 10.5, 700, 0.02em
        readonly property TypeStyle badge: TypeStyle { size: 10.5; weight: 700; spacing: 0.21 }
        // The big card's primary button: card.md 14.5, 650
        readonly property TypeStyle button: TypeStyle { size: 14.5; weight: 650 }
        // A quiet button and a menu item: 13.5, 500
        readonly property TypeStyle menuItem: TypeStyle { size: 13.5; weight: 500 }
        // A header button and a small card's button: 13, 500 / 600
        readonly property TypeStyle control: TypeStyle { size: 13; weight: 500 }
        readonly property TypeStyle controlBold: TypeStyle { size: 13; weight: 600 }
        // A chip: 11.5, 500 (warm 600); an app chip: 11, 500
        readonly property TypeStyle chip: TypeStyle { size: 11.5; weight: 500 }
        // Menu rows (carousel.md §6.2, library.md §10.2) and the big card's chips (card.md §3.7)
        readonly property TypeStyle menuRow: TypeStyle { size: 13; weight: 400 }
        readonly property TypeStyle cardChip: TypeStyle { size: 12; weight: 500 }
        readonly property TypeStyle chipSmall: TypeStyle { size: 11; weight: 500 }
        // The monogram on an app cover: library.md 800, -0.04em (size set by the cover)
        readonly property TypeStyle monogram: TypeStyle { size: 66; weight: 800; spacing: -2.64; lineHeight: 66 }
    }
}
