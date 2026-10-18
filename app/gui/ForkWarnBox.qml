import QtQuick

import ForkTheme 1.0

// [fork] Warnings in an amber box, one line each; hidden when there are none. With okText and no
// warnings it shows that line with a green check instead (like "This Mac decodes these settings
// in hardware.").
Rectangle {
    id: box

    property var warnings: []
    property string okText: ""

    readonly property bool hasWarnings: warnings.length > 0

    // 14 above and below the warnings and 18 at the sides; the green line is 2 less tall
    readonly property real padding: hasWarnings ? 14 : 12

    visible: hasWarnings || okText !== ""
    width: parent ? parent.width : 400
    implicitHeight: column.implicitHeight + 2 * padding
    height: visible ? implicitHeight : 0
    radius: 16
    color: hasWarnings ? ForkTheme.warnBg : ForkTheme.bar
    border.color: hasWarnings ? ForkTheme.warnLine : ForkTheme.lineSoft

    Column {
        id: column
        x: 18
        y: box.padding
        width: parent.width - 36
        spacing: 10

        Repeater {
            model: box.hasWarnings ? box.warnings : [box.okText]

            delegate: Row {
                required property string modelData

                width: column.width
                spacing: 10

                ForkSymbol {
                    y: 2
                    symbol: box.hasWarnings ? "exclamationmark.triangle.fill" : "checkmark"
                    fallback: box.hasWarnings ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-check_circle_outline-24px.svg"
                    size: 15
                    color: box.hasWarnings ? ForkTheme.warnIcon : ForkTheme.ok
                }

                ForkText {
                    width: parent.width - 25
                    kind: "body"
                    color: box.hasWarnings ? ForkTheme.warnText : ForkTheme.text2
                    text: parent.modelData
                }
            }
        }
    }
}
