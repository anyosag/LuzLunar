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
        readonly property color green: theme.dark ? "#30D158" : "#1A7F37"
        readonly property color blue: theme.dark ? "#409CFF" : "#0062CC"
        readonly property color purple: theme.dark ? "#C17DF5" : "#8E3BB8"
        readonly property color gold: theme.dark ? "#F5C878" : "#8A5A00"
        readonly property color orange: theme.dark ? "#FF9F0A" : "#A85A00"
        readonly property color red: theme.dark ? "#FF6961" : "#C1272D"
    }

    // A PC's color by key: fill (its main button, focus ring, switches), onFill (text and icons on
    // the fill), tile (its tiles' tint) and sky (its card's header band). Bindings that call it
    // follow the theme.
    function hue(key) {
        switch (key) {
        case "teal":
            return { fill: dark ? "#40C8E0" : "#0E7C93", onFill: dark ? "#05232B" : "#FFFFFF", tile: "#0E7C93", sky: "#0A2A33" }
        case "pink":
            return { fill: "#D7264B", onFill: "#FFFFFF", tile: "#D7264B", sky: "#36111F" }
        case "gray":
            // A PC that isn't paired yet stays grey: it isn't one of yours until it's paired
            return { fill: dark ? "#5A5E6E" : "#4B4F5C", onFill: "#FFFFFF", tile: "#4B4F5C", sky: "#202229" }
        case "indigo":
        default:
            return { fill: "#5E5CE6", onFill: "#FFFFFF", tile: "#5E5CE6", sky: "#17163F" }
        }
    }
}
