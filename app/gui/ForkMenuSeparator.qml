import QtQuick
import QtQuick.Controls

import ForkTheme 1.0

// [fork] A thin line between groups of menu items, like before Remove or Quit
MenuSeparator {
    topPadding: 4
    bottomPadding: 4
    leftPadding: 2
    rightPadding: 2

    contentItem: Rectangle {
        implicitWidth: 200
        implicitHeight: 1
        color: ForkTheme.lineSoft
    }
}
