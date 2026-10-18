import QtQuick

import ForkTheme 1.0

// [fork] Text in one of LuzLunar's type styles. Always plain text, since much of it comes from
// the host (PC and app names).
//   title     the page title (36 pt bold)
//   titleSm   a smaller title (28 pt bold)
//   heading   a card's or option's name (15 pt semibold)
//   label     a setting's name (15 pt medium)
//   body      running text (13 pt)
//   help      a setting's explanation (12 pt, muted)
//   eyebrow   a card's small capitals title (12 pt, muted)
//   mono      numbers like sizes and stats (12 pt SF Mono)
// Titles and eyebrows track by a share of their size: to set one larger, set pixelSize (not
// font.pixelSize), so the tracking follows. Running text gets the design's line height (1.4 to
// 1.45 times its size).
Text {
    property string kind: "body"

    readonly property var sizes: ({ "title": 36, "titleSm": 28, "heading": 15, "label": 15, "body": 13,
                                    "help": 12, "eyebrow": 12, "mono": 12 })
    property real pixelSize: sizes[kind] !== undefined ? sizes[kind] : 13

    color: kind === "help" || kind === "eyebrow" ? ForkTheme.muted : ForkTheme.text
    font.family: kind === "mono" ? ForkTheme.monoFamily : ForkTheme.uiFamily
    font.pixelSize: pixelSize
    font.weight: kind === "title" || kind === "titleSm" ? Font.Bold
               : kind === "heading" || kind === "eyebrow" ? Font.DemiBold
               : kind === "label" ? Font.Medium : Font.Normal
    font.letterSpacing: kind === "title" ? -0.022 * pixelSize
                      : kind === "titleSm" ? -0.015 * pixelSize
                      : kind === "eyebrow" ? 0.12 * pixelSize : 0
    font.capitalization: kind === "eyebrow" ? Font.AllUppercase : Font.MixedCase
    textFormat: Text.PlainText
    wrapMode: kind === "help" || kind === "body" ? Text.Wrap : Text.NoWrap
    lineHeightMode: kind === "help" || kind === "body" ? Text.FixedHeight : Text.ProportionalHeight
    lineHeight: kind === "help" ? Math.round(font.pixelSize * 1.45) : kind === "body" ? Math.round(font.pixelSize * 1.4) : 1.0
}
