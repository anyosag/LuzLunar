import QtQuick 2.9
import QtQuick.Controls 2.2

import ForkTheme 1.0 // [fork]

GridView {
    property int minMargin: 10
    property real availableWidth: (parent.width - 2 * minMargin)
    property int itemsPerRow: forkStretch ? forkColumns : availableWidth / cellWidth // [fork] was availableWidth / cellWidth
    // [fork] Centers the columns whenever one fits, also with fewer items than columns (upstream
    // only centered full rows), so the redesign's headers and footers line up with a centered block
    property real horizontalMargin: forkStretch ? forkSideMargin
                                                : (availableWidth >= cellWidth ? (parent.width - itemsPerRow * cellWidth) / 2 : minMargin)

    // [fork] The design's grid: columns at least forkMinItemWidth wide share a centered block at
    // most ForkTheme.contentMaxWidth wide (24 pt from the sides when the window is narrower),
    // forkGap apart, and stretch to fill it, so the block's edges line up with the header and
    // footer. Set forkStretch, set cellWidth to forkItemWidth + forkGap, and size the delegates
    // (and header and footer) to forkItemWidth (and forkContentWidth).
    property bool forkStretch: false
    property real forkMinItemWidth: 250
    property real forkGap: 20
    readonly property real forkAvailableWidth: Math.max(forkMinItemWidth, Math.min(ForkTheme.contentMaxWidth, (parent ? parent.width : 0) - 48))
    readonly property int forkColumns: Math.max(1, Math.floor((forkAvailableWidth + forkGap) / (forkMinItemWidth + forkGap)))
    readonly property real forkItemWidth: Math.floor((forkAvailableWidth - (forkColumns - 1) * forkGap) / forkColumns)
    readonly property real forkContentWidth: forkColumns * forkItemWidth + (forkColumns - 1) * forkGap
    readonly property real forkSideMargin: Math.max(0, Math.floor(((parent ? parent.width : 0) - forkContentWidth) / 2))

    function updateMargins() {
        leftMargin = horizontalMargin
        // [fork] In the design's grid the last column's trailing gap sits in the right margin
        // (with a point of slack, so rounding never drops a column)
        rightMargin = forkStretch ? Math.max(0, horizontalMargin - forkGap - 1) : horizontalMargin
    }

    onHorizontalMarginChanged: {
        updateMargins()
    }

    onForkGapChanged: updateMargins() // [fork]

    Component.onCompleted: {
        updateMargins()
    }

    boundsBehavior: Flickable.OvershootBounds
}
