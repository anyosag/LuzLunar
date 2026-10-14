import QtQuick 2.0
import QtQuick.Controls 2.2

import ComputerManager 1.0
import Session 1.0

Item {
    function onSearchingComputer() {
        stageLabel.text = qsTr("Establishing connection to PC...")
    }

    function onQuittingApp() {
        stageLabel.text = qsTr("Quitting app...")
    }

    function onFailure(message) {
        errorDialog.text = message
        errorDialog.open()
    }

    StackView.onActivated: {
        if (!launcher.isExecuted()) {
            toolBar.visible = false
            launcher.searchingComputer.connect(onSearchingComputer)
            launcher.quittingApp.connect(onQuittingApp)
            launcher.failed.connect(onFailure)
            launcher.execute(ComputerManager)
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 5

        ForkBusyIndicator { // [fork] was BusyIndicator
            id: stageSpinner
            running: visible
        }

        Label {
            id: stageLabel
            height: Math.max(stageSpinner.height, implicitHeight) // [fork] was stageSpinner.height
            text: stageText
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        onClosed: {
            Qt.quit()
        }
    }
}
