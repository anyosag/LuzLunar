// UI screenshots for CI. Inactive unless LUZLUNAR_SCREENSHOTS is set to an output folder. Then the
// app opens its main views and dialogs one after another, saves each window as a PNG with Qt's own
// window grab (no screen recording permission needed), and quits. QML warnings and failed step
// scripts go to harness-log.txt in the same folder, since the app's own log isn't in CI's output.
// The run has settings of its own and no PCs (main.cpp, computermanager.cpp).
//
// With LUZLUNAR_SCREENSHOTS_HIDDEN=1 (CI on a self-hosted runner, a Mac someone may be using)
// nothing shows on the screen: main.qml never shows the window, so Qt's grab renders it offscreen
// (with Metal, like on screen), and main.cpp keeps the app out of the Dock and from becoming the
// active app. There's no native capture of the title bar then.
//
//   LUZLUNAR_SCREENSHOTS=/tmp/shots LUZLUNAR_SCREENSHOT_SCHEME=dark LuzLunar

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQmlExpression>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTimer>

#include <iterator>

#include "mac/macintegration.h"
#include "screenshotharness.h"

namespace
{
    struct Step {
        const char* name;     // screenshot file name, or null to only run the script
        const char* script;   // evaluated in main.qml's context before the screenshot, or null
        int delayMs;          // time to wait after the script
        // The objectName of the window's child object the script runs on, so its properties and
        // functions need no prefix; null runs it on the window
        const char* target = nullptr;
    };

    // The sample data of the redesign's screens (spec/samplepcs.json, contract-data.md section 6), as a
    // QtObject the steps use (the step's `target` is "harnessSamples"). Only made-up PCs and apps: a
    // screenshot run never shows this Mac's account or the PCs of the network it runs on. `row(key)` is
    // every role ComputerModel has, so PcView's own delegate code runs unchanged; the covers of the
    // first apps are Apollo's own (qrc:/res/samples), the others get a generated cover (sampleColor).
    const char* k_SamplesQml = R"QML(
import QtQuick
QtObject {
    id: self
    readonly property var sample: ({
        base: {"online":false,"paired":true,"busy":false,"wakeable":true,"statusUnknown":false,"serverSupported":true,"details":"","hostSoftware":"Apollo","knownPaired":true,"keepFirst":false,"wakeOnPick":true,"hasRemoteAddress":false,"remoteWorked":false,"foundAutomatically":true,"lastSeenSecs":1760000000,"lastSeenVia":"home","runningAppId":0,"runningApp":"","streamStartedHere":false,"streamWidth":0,"streamHeight":0,"streamFps":0,"streamHdr":false,"streamCodec":"","hostUpdate":false,"apolloUpToDate":true,"apolloUpdating":false,"wakeFromOff":"ready","waking":false,"wakeTimedOut":false,"powerAction":"","canSleep":false,"canShutDown":false,"canSetUpWake":true,"appsCached":true,"hiddenAppCount":0,"network":"","latencyMs":-1,"addressNote":"lastAddress","apolloVersion":"0.4.8","mainAppId":1,"mainApp":"Desktop"},
        pcs: {
            gonzalo: {"online":true,"hostUpdate":true,"apolloUpToDate":false,"busy":true,"hasRemoteAddress":true,"remoteWorked":true,"runningAppId":1,"runningApp":"Desktop","streamStartedHere":true,"streamWidth":3024,"streamHeight":1890,"streamFps":120,"streamHdr":true,"streamCodec":"HEVC","canSleep":true,"canShutDown":true,"appsCached":false,"hiddenAppCount":1,"network":"home","latencyMs":2,"addressNote":"reachableOutside","name":"GonzaloPC","uuid":"sample-gonzalo","state":"streaming","colorKey":"indigo","address":"10.0.0.77","appCount":7,"previewApps":[{"appid":1,"name":"Desktop","boxart":"qrc:/res/samples/desktop.png","running":true},{"appid":2,"name":"Desktop (multiple displays)","boxart":"qrc:/res/samples/desktop_multi.png","running":false},{"appid":3,"name":"Steam Big Picture","boxart":"qrc:/res/samples/steam.png","running":false}]},
            living: {"lastSeenSecs":1759990000,"name":"Living Room","uuid":"sample-living-room","state":"asleep","colorKey":"teal","address":"10.0.0.42","appCount":6,"previewApps":[{"appid":3,"name":"Steam Big Picture","boxart":"qrc:/res/samples/steam.png","running":false},{"appid":1,"name":"Desktop","boxart":"qrc:/res/samples/desktop.png","running":false},{"appid":2,"name":"Desktop (multiple displays)","boxart":"qrc:/res/samples/desktop_multi.png","running":false}]},
            office: {"online":true,"paired":false,"wakeable":false,"hostSoftware":"","knownPaired":false,"lastSeenSecs":0,"lastSeenVia":"","apolloUpToDate":false,"wakeFromOff":"","canSetUpWake":false,"appsCached":false,"network":"home","latencyMs":3,"addressNote":"foundAutomatically","apolloVersion":"","mainAppId":0,"mainApp":"","name":"Office PC","uuid":"sample-office","state":"pair","colorKey":"gray","address":"10.0.0.31","appCount":0,"previewApps":[]},
            studio: {"lastSeenSecs":1759900000,"powerAction":"off","name":"Studio PC","uuid":"sample-studio","state":"off","colorKey":"blue","address":"10.0.0.58","appCount":5,"previewApps":[{"appid":1,"name":"Desktop","boxart":"qrc:/res/samples/desktop.png","running":false},{"appid":2,"name":"Desktop (multiple displays)","boxart":"qrc:/res/samples/desktop_multi.png","running":false},{"appid":3,"name":"Steam Big Picture","boxart":"qrc:/res/samples/steam.png","running":false}]},
            basement: {"wakeable":false,"lastSeenSecs":1758000000,"apolloUpToDate":false,"wakeFromOff":"","canSetUpWake":false,"name":"Basement PC","uuid":"sample-basement","state":"lost","colorKey":"pink","address":"10.0.0.19","appCount":4,"previewApps":[{"appid":1,"name":"Desktop","boxart":"qrc:/res/samples/desktop.png","running":false},{"appid":2,"name":"Desktop (multiple displays)","boxart":"qrc:/res/samples/desktop_multi.png","running":false},{"appid":3,"name":"Steam Big Picture","boxart":"qrc:/res/samples/steam.png","running":false}]},
        }
    })
    // A card state on top of one of the sample PCs
    readonly property var variants: ({
        ready: { from: "gonzalo", set: { state: "ready", busy: false, runningAppId: 0, runningApp: "", streamStartedHere: false, streamWidth: 0, streamHeight: 0, streamFps: 0, streamHdr: false, streamCodec: "" } },
        waking: { from: "studio", set: { state: "waking", waking: true, powerAction: "" } },
        offNoWake: { from: "studio", set: { state: "offNoWake", wakeFromOff: "", canSetUpWake: false, wakeable: false } },
        checking: { from: "studio", set: { state: "checking", powerAction: "" } }
    })

    // One PC's row: a sample PC ("gonzalo" "living" "office" "studio" "basement") or a variant
    function row(key) {
        var v = variants[key]
        var r = JSON.parse(JSON.stringify(sample.base))
        var src = sample.pcs[v ? v.from : key]
        for (var k in src) r[k] = src[k]
        if (v) for (var j in v.set) r[j] = v.set[j]
        return r
    }
    // A ListModel of these PCs, for PcView.forkSampleModel (empty: the first run page)
    function pcsModel(keys) {
        var m = Qt.createQmlObject("import QtQuick\nListModel {}", self, "harness-pcs")
        for (var i = 0; i < keys.length; i++) m.append(row(keys[i]))
        return m
    }
    // Shows another state on the card in row i, in place
    function setRow(model, i, key) { model.set(i, row(key)) }
    // Many PCs, as an owner may have them (made-up names): one ready, one that can't be reached, and
    // four saved PCs that share a long name and can't be reached either
    function manyModel() {
        var m = pcsModel(['ready', 'basement'])
        var colors = ['green', 'orange', 'purple', 'gold']
        for (var i = 0; i < colors.length; i++) {
            var r = row('basement')
            r.name = 'Upstairs-Gaming-Laptop-Pro'
            r.uuid = 'sample-upstairs-' + (i + 1)
            r.colorKey = colors[i]
            m.append(r)
        }
        return m
    }

    // [name, Apollo cover or "", cover color, profile, extra chips, hidden]
    readonly property var libraryApps: [
        ["Desktop", "desktop", "", "", "", false], ["Desktop (multiple displays)", "desktop_multi", "", "office", "", false],
        ["Steam Big Picture", "steam", "", "gaming", "", false], ["Virtual Display", "virtual_desktop", "", "", "", false],
        ["Forza Horizon 5", "", "orange", "gaming", "", false], ["Cyberpunk 2077", "", "pink", "gaming", "", false],
        ["Hades II", "", "red", "gaming", "", false], ["Rocket League", "", "blue", "gaming", "", false],
        ["Blender", "", "teal", "custom", "Mac trackpad", false], ["Visual Studio Code", "", "purple", "custom", "16:10", false],
        ["Epic Games Launcher", "", "graphite", "", "", true], ["Xbox", "", "gold", "", "", true]]
    readonly property var asleepApps: [
        ["Steam Big Picture", "steam", "", "gaming", "", false], ["Desktop", "desktop", "", "", "", false],
        ["Desktop (multiple displays)", "desktop_multi", "", "office", "", false], ["Virtual Display", "virtual_desktop", "", "", "", false],
        ["Rocket League", "", "blue", "gaming", "", false], ["Forza Horizon 5", "", "orange", "gaming", "", false]]

    // A ListModel with AppModel's roles, for PcView.forkSampleApps; "library" is GonzaloPC's 12 apps with
    // the Desktop running, "asleep" the Living Room's 6, none running
    function appsModel(kind) {
        var list = kind === "asleep" ? asleepApps : libraryApps
        var m = Qt.createQmlObject("import QtQuick\nListModel {}", self, "harness-apps")
        for (var i = 0; i < list.length; i++) {
            var a = list[i]
            m.append({ name: a[0], running: kind !== "asleep" && i === 0, hidden: a[5], appid: i + 1, directLaunch: false,
                       isAppCollectorGame: false, boxart: a[1] !== "" ? "qrc:/res/samples/" + a[1] + ".png" : "qrc:/res/no_app_image.png",
                       sampleProfile: a[3], sampleColor: a[2], sampleExtras: a[4] })
        }
        return m
    }
}
)QML";

    // Runs on the page that shows: stack, window and the dialogs' ids are main.qml's
    #define P "var p = stackView.currentItem; "

    // Each step runs its script, waits, then saves a screenshot. Every one runs in the dark and the
    // light run. PcView's steps use the page's harness hooks (spec/contract-pcview.md) with the sample
    // PCs above; the page stays in sample mode to the end, so it never asks for the real PCs.
    // The delays add up to about 80 s per run; CI stops a run after 180 s (fork-macos.yml).
    const Step k_Steps[] = {
        // The redesign's boards are 1280 x 900 (Settings and the dialogs below use 860)
        // The size is set twice: in a hidden run the window is never shown, and its overlay (where dialogs
        // are centered and dimmed) only gets its size from a resize, which setting the size it already has
        // (main.qml opens at 1280 x 900) doesn't make: the Customize sheet came out at the corner
        { nullptr, "window.width = 1200; window.height = 800", 300 },
        { nullptr, "window.width = 1280; window.height = 900", 500 },
        // The first run: no PCs (an empty sample list; the real list is never asked)
        { "1-computers", P "p.forkSampleModel = pcsModel([]); p.forkSkipEntrance()", 2500, "harnessSamples" },
        // Your PCs as the canvas opens: GonzaloPC streaming, with Living Room asleep and Office PC not paired
        { "1b-pcs-carousel",
          P "p.forkSampleModel = pcsModel(['gonzalo', 'living', 'office']); p.forkSkipEntrance(); p.forceActiveFocus(); p.forkFocus(0)", 2500, "harnessSamples" },
        // Each other card in front (a move takes about 1.2 s with the card's ring)
        { "1b2-pcs-next1", "stackView.currentItem.forkFocus(1)", 1400 },
        { "1b3-pcs-next2", "stackView.currentItem.forkFocus(2)", 1400 },
        { "1b4-pcs-next3", "stackView.currentItem.forkFocus(3)", 1400 },
        // The ... menu of GonzaloPC
        { nullptr, "stackView.currentItem.forkFocus(0)", 1300 },
        { "1b5-pcs-menu", "stackView.currentItem.forkOpenMenu(0)", 700 },
        { "1b6-pcs-grid", "stackView.currentItem.forkCloseMenu(); stackView.currentItem.forkSetViewMode('grid')", 1500 },
        // The Customize sheet, from the menu's action
        { nullptr, "stackView.currentItem.forkSetViewMode('carousel')", 1300 },
        { "1b7-customize", "stackView.currentItem.forkOpenCustomize(0)", 1000 },
        { nullptr, P "var d = p.data; for (var i = 0; i < d.length; i++) if (d[i] && d[i].opened === true && typeof d[i].close === 'function') d[i].close()", 600 },
        // The other card states on the focused card (streaming, asleep and not paired are above)
        { "1b-pcs-state-ready", P "setRow(p.forkSampleModel, 0, 'ready')", 1000, "harnessSamples" },
        { "1b-pcs-state-waking", P "setRow(p.forkSampleModel, 0, 'waking')", 1000, "harnessSamples" },
        { "1b-pcs-state-off", P "setRow(p.forkSampleModel, 0, 'studio')", 1000, "harnessSamples" },
        { "1b-pcs-state-offnowake", P "setRow(p.forkSampleModel, 0, 'offNoWake')", 1000, "harnessSamples" },
        { "1b-pcs-state-lost", P "setRow(p.forkSampleModel, 0, 'basement')", 1000, "harnessSamples" },
        { "1b-pcs-state-checking", P "setRow(p.forkSampleModel, 0, 'checking')", 1000, "harnessSamples" },
        { nullptr, P "setRow(p.forkSampleModel, 0, 'gonzalo')", 600, "harnessSamples" },
        // All apps opened from GonzaloPC's card (the Library board), then the asleep Living Room's
        { "1b8-allapps",
          P "p.forkSampleApps = appsModel('library'); p.forkSampleHostInfo = ({ local: true, remote: false, reachableRemote: true }); p.forkOpenApps(0)", 2600, "harnessSamples" },
        { nullptr, "stackView.pop(null, StackView.Immediate)", 1000 },
        { "1a-apps-asleep", P "p.forkSampleApps = appsModel('asleep'); p.forkOpenApps(1)", 2600, "harnessSamples" },
        { nullptr, "stackView.pop(null, StackView.Immediate)", 1000 },
        // The autoplay demo (the OptionLoop board): three frames, each a step of the demo
        { nullptr, "stackView.currentItem.forkFocus(0); stackView.currentItem.forkStartDemo()", 1300 },
        { "1b9-pcs-demo-1", nullptr, 100 },
        // forkTickDemo() is one step of the demo; stop and start again so the page's own 3.4 s timer starts over
        { "1b9-pcs-demo-2", "var p = stackView.currentItem; p.forkTickDemo(); p.forkStopDemo(); p.forkStartDemo()", 1300 },
        { "1b9-pcs-demo-3", "var p = stackView.currentItem; p.forkTickDemo(); p.forkStopDemo(); p.forkStartDemo()", 1300 },
        { nullptr, "stackView.currentItem.forkStopDemo(); stackView.currentItem.forkFocus(0)", 1300 },
        // Six PCs: the story says it in two sentences ("GonzaloPC is ready", "Can't reach 5 PCs"),
        // and long names are cut short, in the carousel's chips and the grid
        { "1b10-pcs-many", P "p.forkSampleModel = manyModel(); p.forkSkipEntrance(); p.forkFocus(0)", 1500, "harnessSamples" },
        { "1b11-pcs-many-grid", "stackView.currentItem.forkSetViewMode('grid')", 1500 },
        // Dragging a card in the grid: the first PC lifted over the third cell, the others making room
        { "1b12-pcs-grid-drag", "stackView.currentItem.forkDragPreview(0, 2)", 900 },
        { nullptr, "var p = stackView.currentItem; p.forkDragEnd(); p.forkSetViewMode('carousel')", 1300 },

        // The stream launch screen, with sample values (a real one needs a stream). The page hides the
        // window's bars while it shows, as a stream's launch does
        { nullptr, "window.height = 860", 300 },
        { "1c-launch",
          "toolBar.visible = false; "
          "stackView.push(Qt.createQmlObject('import QtQuick; Item { ForkLaunchPanel { "
          "appName: \"Desktop\"; hostName: \"GonzaloPC\"; stageText: \"Starting RTSP handshake...\"; stagesDone: 4; started: true; "
          "summary: [\"3024×1890 · 16:10\", \"120 fps\", \"81 Mb/s\", \"HEVC · HDR\"] } }', stackView, 'qrc:/gui/HarnessLaunch.qml'), StackView.Immediate)", 1500 },
        { nullptr, "stackView.pop(null, StackView.Immediate); toolBar.visible = true", 400 },
        // A multi-display stream's launch screen with the iMac (ForkGroupLaunch's samples): checking its
        // route, then straight from the PC, then through this Mac
        { "1d-launch-displays-checking",
          "toolBar.visible = false; "
          "stackView.push(Qt.createQmlObject('import QtQuick; import ForkGroupLaunch 1.0; Item { "
          "Component.onCompleted: ForkGroupLaunch.showSample(0); ForkLaunchPanel { "
          "appName: \"Desktop (multiple displays)\"; hostName: \"GonzaloPC\"; stagesDone: 0; started: true; "
          "summary: [\"3024×1890 · 16:10\", \"120 fps\", \"81 Mb/s\", \"HEVC · HDR\"] } }', stackView, 'qrc:/gui/HarnessLaunch.qml'), StackView.Immediate)", 1500 },
        { nullptr, "stackView.pop(null, StackView.Immediate); toolBar.visible = true", 400 },
        { "1e-launch-displays-direct",
          "toolBar.visible = false; "
          "stackView.push(Qt.createQmlObject('import QtQuick; import ForkGroupLaunch 1.0; Item { "
          "Component.onCompleted: ForkGroupLaunch.showSample(1); ForkLaunchPanel { "
          "appName: \"Desktop (multiple displays)\"; hostName: \"GonzaloPC\"; stageText: \"Starting name resolution...\"; stagesDone: 2; started: true; "
          "summary: [\"3024×1890 · 16:10\", \"120 fps\", \"81 Mb/s\", \"HEVC · HDR\"] } }', stackView, 'qrc:/gui/HarnessLaunch.qml'), StackView.Immediate)", 1500 },
        { nullptr, "stackView.pop(null, StackView.Immediate); toolBar.visible = true", 400 },
        { "1f-launch-displays-via-mac",
          "toolBar.visible = false; "
          "stackView.push(Qt.createQmlObject('import QtQuick; import ForkGroupLaunch 1.0; Item { "
          "Component.onCompleted: ForkGroupLaunch.showSample(2); ForkLaunchPanel { "
          "appName: \"Desktop (multiple displays)\"; hostName: \"GonzaloPC\"; stageText: \"Starting RTSP handshake...\"; stagesDone: 4; started: true; "
          "summary: [\"3024×1890 · 16:10\", \"120 fps\", \"81 Mb/s\", \"HEVC · HDR\"] } }', stackView, 'qrc:/gui/HarnessLaunch.qml'), StackView.Immediate)", 1500 },
        { nullptr, "stackView.pop(null, StackView.Immediate); toolBar.visible = true", 400 },
        { "2-settings-display", "settingsButton.clicked()", 2000 },
        { "2b-settings-display-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 800 },
        { "2c-settings-video", "stackView.currentItem.showSection('video')", 1000 },
        { "2d-settings-audio", "stackView.currentItem.showSection('audio')", 1000 },
        { "2e-settings-mouse", "stackView.currentItem.showSection('mouse')", 1000 },
        { "2e2-settings-mouse-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 800 },
        { "2f-settings-keyboard", "stackView.currentItem.showSection('keyboard')", 1000 },
        { "2g-settings-keyboard-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 800 },
        { "2h-settings-gamepads", "stackView.currentItem.showSection('gamepads')", 1000 },
        { "2i-settings-host", "stackView.currentItem.showSection('host')", 1000 },
        { "2j-settings-app", "stackView.currentItem.showSection('app')", 1000 },
        { "2j2-settings-updates", "stackView.currentItem.showSection('updates')", 1000 },
        { "2k-settings-mac", "stackView.currentItem.showSection('mac')", 1000 },
        { "2l-settings-mac-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 800 },
        // Back on Your PCs (still the sample PCs), the Add PC dialog over the carousel
        { "5-add-pc-dialog", "goBack(); addPcDialog.open()", 1800 },
        // An app's stream settings: every row on Global, the Office preset, Office with one row
        // changed (Custom), the end of the list, and the top again in a short window
        { "6-stream-settings-dialog",
          "addPcDialog.close(); "
          "var d = Qt.createComponent('qrc:/gui/StreamProfileDialog.qml').createObject(window, "
          "  { appName: 'Office Mode', objectName: 'harnessStreamSettings' }); "
          "d.fields = d.buildFields(); d.open(); d.refresh()", 1800 },
        { "6a-stream-settings-office", "applyPreset(officePreset)", 800, "harnessStreamSettings" },
        { "6b-stream-settings-custom", "chooseValue('fps', 60)", 800, "harnessStreamSettings" },
        { "6c-stream-settings-end", "scrollY = scrollMax", 800, "harnessStreamSettings" },
        { nullptr, "window.height = 600", 400 },
        { "6d-stream-settings-short", "scrollY = 0", 1200, "harnessStreamSettings" },
        // A toast while a dialog is open shows above the dialog and its dim (main.qml). Last, since
        // a toast stays a few seconds and would be in the screenshots after it.
        { "7-toast-over-dialog", "forkToast(qsTr('Renamed to Office PC'))", 800 },
    };
    #undef P

    // The engine whose QML warnings go to harness-log.txt (watchWarnings()), or null for none yet
    QQmlEngine* s_WatchedEngine = nullptr;

    // Adds a line to harness-log.txt in the output folder
    void logLine(const QString& outputDir, const QString& line)
    {
        QFile file(QDir(outputDir).filePath("harness-log.txt"));
        if (file.open(QIODevice::Append | QIODevice::Text)) {
            file.write(line.toUtf8() + '\n');
        }
        qWarning().noquote() << "[fork] Screenshot harness:" << line;
    }

    // LUZLUNAR_SCREENSHOTS_HIDDEN=1: nothing on the screen (see the top)
    bool hiddenRun()
    {
        static const bool hidden = qEnvironmentVariableIntValue("LUZLUNAR_SCREENSHOTS_HIDDEN") == 1;
        return hidden;
    }

    // The app's window: the shown one, or in a hidden run, where main.qml doesn't show it, the one
    // main.qml made
    QQuickWindow* mainWindow()
    {
        for (QWindow* window : QGuiApplication::topLevelWindows()) {
            if (auto quickWindow = qobject_cast<QQuickWindow*>(window)) {
                if (quickWindow->isVisible() || hiddenRun()) {
                    return quickWindow;
                }
            }
        }
        return nullptr;
    }

    // In a hidden run, a window that shows anyway (a step opening one, say) is made invisible and
    // click-through before it reaches the screen, and logged: Qt sends the show event before the
    // native window is ordered in
    class HiddenWindowGuard : public QObject
    {
    public:
        HiddenWindowGuard(const QString& outputDir, QObject* parent)
            : QObject(parent), m_OutputDir(outputDir)
        {
        }

        bool eventFilter(QObject* watched, QEvent* event) override
        {
            if (event->type() == QEvent::Show && watched->isWindowType()) {
                QWindow* window = static_cast<QWindow*>(watched);
                window->setFlags(window->flags() | Qt::WindowTransparentForInput | Qt::WindowDoesNotAcceptFocus);
                window->setOpacity(0.0);
                logLine(m_OutputDir, QString("A window showed in the hidden run, kept invisible: %1 (%2)")
                                         .arg(window->objectName(), QString::fromUtf8(window->metaObject()->className())));
            }
            return false;
        }

    private:
        QString m_OutputDir;
    };

    // The sample data object (k_SamplesQml), a child of the window named "harnessSamples", made once
    void makeSamples(const QString& outputDir, QQuickWindow* window)
    {
        if (window->findChild<QObject*>(QStringLiteral("harnessSamples")) != nullptr) {
            return;
        }
        QQmlEngine* engine = qmlEngine(window);
        if (engine == nullptr) {
            logLine(outputDir, QStringLiteral("No QML engine for the sample data"));
            return;
        }
        QQmlComponent component(engine);
        component.setData(QByteArray(k_SamplesQml), QUrl(QStringLiteral("qrc:/harness-samples.qml")));
        QObject* samples = component.create();
        if (samples == nullptr) {
            logLine(outputDir, QStringLiteral("The sample data didn't load: %1").arg(component.errorString()));
            return;
        }
        samples->setObjectName(QStringLiteral("harnessSamples"));
        samples->setParent(window);
    }

    void runStep(const QString& outputDir, size_t index, int attempt = 0)
    {
        if (index >= std::size(k_Steps)) {
            QCoreApplication::quit();
            return;
        }

        const Step& step = k_Steps[index];
        QQuickWindow* window = mainWindow();
        if (window == nullptr) {
            // The main window shows a moment after the event loop starts
            if (attempt < 40) {
                QTimer::singleShot(250, [outputDir, index, attempt]() {
                    runStep(outputDir, index, attempt + 1);
                });
            }
            else {
                qWarning() << "[fork] Screenshot harness: no visible window";
                QCoreApplication::exit(1);
            }
            return;
        }

        // A window that isn't shown can still be grabbed once it's created (QQuickWindow::grabWindow())
        if (hiddenRun() && window->handle() == nullptr) {
            window->create();
        }

        // QML's warnings, if main.cpp didn't hand over the engine before main.qml loaded: from now on
        if (s_WatchedEngine == nullptr) {
            if (QQmlEngine* engine = qmlEngine(window)) {
                ScreenshotHarness::watchWarnings(engine);
            }
        }

        makeSamples(outputDir, window);

        if (step.script != nullptr) {
            QString stepName = step.name != nullptr ? QString::fromUtf8(step.name) : QString("step %1").arg(index);
            QObject* scope = window;
            if (step.target != nullptr) {
                scope = window->findChild<QObject*>(QString::fromUtf8(step.target));
            }

            if (scope == nullptr) {
                logLine(outputDir, QString("No object named %1 for %2").arg(QString::fromUtf8(step.target), stepName));
            }
            else {
                QQmlExpression expression(qmlContext(window), scope, QString::fromUtf8(step.script));
                expression.evaluate();
                if (expression.hasError()) {
                    logLine(outputDir, QString("Script of %1 failed: %2").arg(stepName, expression.error().toString()));
                }
            }
        }

        QTimer::singleShot(step.delayMs, [outputDir, index, step]() {
            if (step.name == nullptr) {
                runStep(outputDir, index + 1);
                return;
            }
            if (QQuickWindow* window = mainWindow()) {
                QString path = QDir(outputDir).filePath(QString::fromUtf8(step.name) + ".png");
                if (window->grabWindow().save(path)) {
                    qInfo() << "[fork] Saved screenshot" << path;
                }
                else {
                    qWarning() << "[fork] Couldn't save screenshot" << path;
                }

                // Qt's grab only has the QML content. The window server's capture also has the
                // title bar and native toolbar, if the CI Mac allows screen capture; a hidden run
                // has nothing on the screen to capture.
                long number = hiddenRun() ? 0 : MacIntegration::windowNumber(window);
                if (number != 0) {
                    QProcess capture;
                    capture.start("/usr/sbin/screencapture",
                                  { "-x", "-o", QString("-l%1").arg(number),
                                    QDir(outputDir).filePath(QString::fromUtf8(step.name) + "-native.png") });
                    if (!capture.waitForFinished(5000)) {
                        capture.kill();
                    }
                }
            }
            runStep(outputDir, index + 1);
        });
    }

    void startScreenshotHarness()
    {
        QString outputDir = qEnvironmentVariable("LUZLUNAR_SCREENSHOTS");
        if (outputDir.isEmpty()) {
            return;
        }
        QDir().mkpath(outputDir);

        if (hiddenRun()) {
            QCoreApplication::instance()->installEventFilter(new HiddenWindowGuard(outputDir, QCoreApplication::instance()));
        }

        // Starts once the event loop runs, when the app is fully set up
        QTimer::singleShot(0, [outputDir]() {
            QString scheme = qEnvironmentVariable("LUZLUNAR_SCREENSHOT_SCHEME");
            if (scheme == "dark" || scheme == "light") {
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
                QGuiApplication::styleHints()->setColorScheme(scheme == "dark" ? Qt::ColorScheme::Dark : Qt::ColorScheme::Light);
#else
                qWarning() << "[fork] Screenshot harness: LUZLUNAR_SCREENSHOT_SCHEME needs Qt 6.8; using the system appearance";
#endif
            }
            runStep(outputDir, 0);
        });
    }
}

void ScreenshotHarness::watchWarnings(QQmlEngine* engine)
{
    // The output folder exists by now: startScreenshotHarness() runs as the app object is made
    QString outputDir = qEnvironmentVariable("LUZLUNAR_SCREENSHOTS");
    if (outputDir.isEmpty() || engine == nullptr || s_WatchedEngine != nullptr) {
        return;
    }

    s_WatchedEngine = engine;
    QObject::connect(engine, &QQmlEngine::warnings, engine, [outputDir](const QList<QQmlError>& warnings) {
        for (const QQmlError& warning : warnings) {
            logLine(outputDir, warning.toString());
        }
    });
}

Q_COREAPP_STARTUP_FUNCTION(startScreenshotHarness)
