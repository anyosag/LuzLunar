import QtQuick
import QtQuick.Window

import ForkTheme 1.0

// [fork] Text at the redesign canvas's sizes, which are often fractional (10.5, 11.5, 12.5, 13.5 px).
// font.pixelSize is a whole number (Qt rejects 11.5 and truncates expressions), so the size goes
// through font.pointSize: a Mac is 72 dpi, so 13.5 pt draws at 13.5 px there, and elsewhere the
// conversion keeps the same pixel size. `role` takes a ForkTheme.ty style (size, weight, tracking,
// line height, capitals); px, weight and tracking override it. Always plain text, since much of it
// comes from the host (PC and app names).
Text {
    property string role: ""
    readonly property var typeStyle: role !== "" && ForkTheme.ty[role] !== undefined ? ForkTheme.ty[role] : null

    property real px: typeStyle ? typeStyle.size : 13
    property int weight: typeStyle ? typeStyle.weight : 400
    property real tracking: typeStyle ? typeStyle.spacing : 0
    property real lineHeightPx: typeStyle ? typeStyle.lineHeight : 0
    property bool upper: typeStyle ? typeStyle.upper : false

    readonly property real _dpi: Screen.logicalPixelDensity > 0 ? Screen.logicalPixelDensity * 25.4 : 72

    color: ForkTheme.cv.text
    textFormat: Text.PlainText
    font.family: ForkTheme.uiFamily
    font.pointSize: px * 72 / _dpi
    font.weight: weight
    font.letterSpacing: tracking
    font.capitalization: upper ? Font.AllUppercase : Font.MixedCase
    lineHeightMode: lineHeightPx > 0 ? Text.FixedHeight : Text.ProportionalHeight
    lineHeight: lineHeightPx > 0 ? lineHeightPx : 1.0
}
