import QtQuick

import ForkTheme 1.0

// [fork] A card that groups settings, with a small-capitals title. Its children stack in a
// column 22 pt apart (ForkTheme.cardSpacing); ForkSwitchRows inside it draw their own dividers.
//
//   ForkCard {
//       title: qsTr("Muting")
//       ForkSwitchRow { showDivider: false; ... }
//       ForkSwitchRow { ... }
//   }
//
// quiet gives it the toolbar's ground instead of a surface, for secondary information.
Rectangle {
    id: card

    property string title: ""
    property bool quiet: false
    property alias spacing: column.spacing
    default property alias content: column.data

    width: parent ? parent.width : 600
    implicitHeight: column.implicitHeight + 2 * ForkTheme.cardPadding
    height: implicitHeight
    radius: ForkTheme.radiusCard
    color: quiet ? ForkTheme.bar : ForkTheme.surface
    border.color: quiet ? ForkTheme.lineSoft : ForkTheme.line

    Column {
        id: column
        x: ForkTheme.cardPadding
        y: ForkTheme.cardPadding
        width: parent.width - 2 * ForkTheme.cardPadding
        spacing: ForkTheme.cardSpacing

        ForkText {
            visible: card.title !== ""
            kind: "eyebrow"
            text: card.title
            Accessible.role: Accessible.Heading
        }
    }
}
