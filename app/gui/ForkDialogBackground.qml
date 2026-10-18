import QtQuick

import ForkTheme 1.0

// [fork] The panel behind dialogs: a ForkPopupBackground with the cards' rounder corners.
// NavigableDialog uses it as its background.
ForkPopupBackground {
    property var dialog

    radius: ForkTheme.radiusCard
}
