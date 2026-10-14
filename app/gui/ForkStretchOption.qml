import QtQuick
import QtQuick.Controls

import StreamingPreferences 1.0
import SystemProperties 1.0

// "Fullscreen fill" under Display mode in SettingsView: fit the stream with black bars, or stretch
// it over the whole screen. Only a fullscreen stream stretches, so it's off while Windowed.
Column {
    id: stretchOption

    readonly property bool windowed: StreamingPreferences.windowMode === StreamingPreferences.WM_WINDOWED

    // The area a fullscreen stream fills on the first display: below the notch where there is one
    property size screenSize: Qt.size(0, 0)
    // The whole panel, notch strip included
    property size panelSize: Qt.size(0, 0)

    spacing: 5

    function refreshScreen() {
        var rect = SystemProperties.getSafeAreaResolution(0)
        if (rect.width <= 0) {
            // The display list isn't loaded yet
            SystemProperties.refreshDisplays()
            rect = SystemProperties.getSafeAreaResolution(0)
        }
        var panel = SystemProperties.getNativeResolution(0)
        if (rect.width <= 0) {
            rect = panel
        }
        screenSize = Qt.size(rect.width, rect.height)
        panelSize = Qt.size(panel.width, panel.height)
    }

    // 1920x1080 as 16:9, 2560x1600 as 16:10, and a decimal for ratios that don't reduce to small numbers
    function ratioName(w, h) {
        var a = w
        var b = h
        while (b > 0) {
            var rest = a % b
            a = b
            b = rest
        }

        var ratioW = w / a
        var ratioH = h / a
        if (ratioW === 8 && ratioH === 5) {
            ratioW = 16
            ratioH = 10
        }
        return ratioW <= 32 && ratioH <= 32 ? ratioW + ":" + ratioH : (w / h).toFixed(2) + ":1"
    }

    // How much a stretched stream looks off on this screen
    function distortionText() {
        var w = StreamingPreferences.width
        var h = StreamingPreferences.height
        if (w <= 0 || h <= 0 || screenSize.width <= 0 || screenSize.height <= 0) {
            return ""
        }

        var streamRatio = w / h
        var screenRatio = screenSize.width / screenSize.height
        var panelRatio = panelSize.width / panelSize.height
        var percent = Math.round((Math.max(streamRatio / screenRatio, screenRatio / streamRatio) - 1) * 100)
        var name = ratioName(w, h)

        // A stream with the whole panel's ratio fills the panel, under the notch, so nothing is distorted
        if (percent < 1 || Math.abs(streamRatio / panelRatio - 1) <= 0.01) {
            return qsTr("%1 matches this screen: no distortion").arg(name)
        }

        // A stream that's wider than the screen gets squeezed sideways, so it looks taller
        return streamRatio > screenRatio ? qsTr("%1 on this screen: %2% taller").arg(name).arg(percent)
                                         : qsTr("%1 on this screen: %2% wider").arg(name).arg(percent)
    }

    Component.onCompleted: {
        refreshScreen()
        fillComboBox.recalculateWidth()
    }

    // The combo box is disabled while Windowed, and a disabled control doesn't show its own tooltip
    HoverHandler {
        id: hoverHandler
    }

    ToolTip.delay: 1000
    ToolTip.timeout: 5000
    ToolTip.visible: hoverHandler.hovered
    ToolTip.text: qsTr("When the stream's aspect ratio differs from the screen, fill the screen instead of showing black bars. The picture is distorted.")

    Label {
        width: parent.width
        text: qsTr("Fullscreen fill")
        font.pointSize: 12
        wrapMode: Text.Wrap
        enabled: !stretchOption.windowed
    }

    AutoResizingComboBox {
        id: fillComboBox
        enabled: !stretchOption.windowed
        font.pointSize: 12
        model: [qsTr("Fit (black bars)"), qsTr("Stretch")]
        currentIndex: StreamingPreferences.fullscreenStretch ? 1 : 0

        // ::onActivated must be used, as it only listens for when the index is changed by a human
        onActivated: {
            StreamingPreferences.fullscreenStretch = currentIndex === 1
        }
    }

    Label {
        width: parent.width
        font.pointSize: 9
        wrapMode: Text.Wrap
        text: stretchOption.windowed ? qsTr("Only used in fullscreen. A windowed stream always fits.") :
              StreamingPreferences.fullscreenStretch ? stretchOption.distortionText() : ""
        visible: text !== ""
    }
}
