import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T

import ForkTheme 1.0

// [fork] Under the PCs (PcView's footer): a dashed "Add a PC" card in the grid's next free cell
// (the last row's, when it has room), and the line about this Mac
Item {
    id: footer

    // The grid's layout, from PcView
    property int count: 0
    property int columns: 1
    property real cellWidth: 293
    property real cellHeight: 350
    property real cardWidth: 273
    property real cardHeight: 330

    signal addPc()

    // The last row has a free cell, so the card goes there, above this footer
    readonly property int freeColumn: count % Math.max(1, columns)
    readonly property bool inLastRow: count > 0 && freeColumn !== 0

    implicitHeight: macStrip.y + macStrip.height + 24

    T.Button {
        id: addCard
        x: footer.inLastRow ? footer.freeColumn * footer.cellWidth : 0
        y: footer.inLastRow ? -footer.cellHeight : 0
        width: footer.cardWidth
        height: footer.cardHeight
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        onClicked: footer.addPc()

        Accessible.name: qsTr("Add a PC")
        Accessible.description: qsTr("By IP address or hostname")

        background: Item {
            Rectangle {
                anchors.fill: parent
                radius: ForkTheme.radiusCard
                color: addCard.hovered ? ForkTheme.surface : "transparent"
            }

            // A dashed outline, inset by half the line
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: ForkTheme.lineStrong
                    strokeWidth: 1.5
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 1.5]
                    fillColor: "transparent"
                    readonly property real w: addCard.width - 0.75
                    readonly property real h: addCard.height - 0.75
                    readonly property real r: 19.25
                    startX: r + 0.75; startY: 0.75
                    PathLine { x: addCard.width - 20; y: 0.75 }
                    PathArc { x: addCard.width - 0.75; y: 20; radiusX: 19.25; radiusY: 19.25 }
                    PathLine { x: addCard.width - 0.75; y: addCard.height - 20 }
                    PathArc { x: addCard.width - 20; y: addCard.height - 0.75; radiusX: 19.25; radiusY: 19.25 }
                    PathLine { x: 20; y: addCard.height - 0.75 }
                    PathArc { x: 0.75; y: addCard.height - 20; radiusX: 19.25; radiusY: 19.25 }
                    PathLine { x: 0.75; y: 20 }
                    PathArc { x: 20; y: 0.75; radiusX: 19.25; radiusY: 19.25 }
                }
            }
        }

        contentItem: Item {
            Column {
                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 52
                    height: 52
                    radius: 26
                    color: ForkTheme.raised

                    ForkSymbol {
                        anchors.centerIn: parent
                        symbol: "plus"
                        size: 22
                        color: ForkTheme.accentInk
                    }
                }

                ForkText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "heading"
                    font.pixelSize: 16
                    text: qsTr("Add a PC")
                }

                ForkText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "help"
                    font.pixelSize: 13
                    wrapMode: Text.NoWrap
                    text: qsTr("By IP address or hostname")
                }
            }
        }
    }

    ForkThisMacStrip {
        id: macStrip
        // The page's 28 between the grid and the strip (a grid row already ends with its 20 gap)
        y: footer.inLastRow ? 8 : addCard.y + addCard.height + 28
        width: footer.width
    }
}
