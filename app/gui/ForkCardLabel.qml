import QtQuick
import ForkTheme 1.0

// [fork] Text sized in CSS pixels: Qt 6.11 only takes whole numbers for font.pixelSize, and the
// canvas uses sizes like 11.5 and 12.5, so the size is set in points converted for the screen's DPI
// (a Mac is 72 dpi, so 1 pt = 1 px there).
Text {
    property real px: 13
    font.family: ForkTheme.uiFamily
    font.pointSize: px * 72 / (Screen.logicalPixelDensity > 0 ? Screen.logicalPixelDensity * 25.4 : 72)
}
