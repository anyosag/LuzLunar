import QtQuick

import ForkTheme 1.0
import QtQuick.Controls.impl

import SfSymbols 1.0

// [fork] An SF Symbol tinted in a theme color, or the fallback image where SF Symbols aren't available
IconImage {
    property string symbol: ""
    property string fallback: ""
    property real size: 16

    source: SfSymbols.available && symbol !== "" ? SfSymbols.url(symbol) : fallback
    width: size
    height: size
    // Drawn from a 2x image, so it's sharp on Retina
    sourceSize.width: size * 2
    sourceSize.height: size * 2
    color: ForkTheme.text
}
