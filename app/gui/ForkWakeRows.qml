import QtQuick
import QtQuick.Layouts

import ForkTheme 1.0

// [fork] Rows of a checkmark, a warning sign or an info sign, a line and what it means: Set Up Wake
// from Off's checks and Wake from Outside's steps. rows: [{id, kind ("ok", "warn", "info"), title,
// detail}], from ForkHostPower.wakeStatus() and ForkWakeOutside.status().
ColumnLayout {
    id: wakeRows

    property var rows: []

    spacing: 14

    Repeater {
        model: wakeRows.rows

        delegate: RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 10

            ForkSymbol {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                symbol: modelData.kind === "ok" ? "checkmark" : modelData.kind === "warn" ? "exclamationmark.triangle.fill" : "info.circle"
                fallback: modelData.kind === "ok" ? "qrc:/res/baseline-check_circle_outline-24px.svg"
                        : modelData.kind === "warn" ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg"
                        : "qrc:/res/baseline-help_outline-24px.svg"
                size: 15
                color: modelData.kind === "ok" ? ForkTheme.ok : modelData.kind === "warn" ? ForkTheme.warnIcon : ForkTheme.muted
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                ForkText {
                    Layout.fillWidth: true
                    kind: "label"
                    wrapMode: Text.Wrap
                    text: modelData.title
                }

                ForkText {
                    Layout.fillWidth: true
                    kind: "help"
                    visible: text !== ""
                    text: modelData.detail
                }
            }
        }
    }
}
