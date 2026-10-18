// UI screenshots for CI. Inactive unless LUZLUNAR_SCREENSHOTS is set to an output folder. Then the
// app opens its main views and dialogs one after another, saves each window as a PNG with Qt's own
// window grab (no screen recording permission needed), and quits. QML warnings and failed step
// scripts go to harness-log.txt in the same folder, since the app's own log isn't in CI's output.
//
//   LUZLUNAR_SCREENSHOTS=/tmp/shots LUZLUNAR_SCREENSHOT_SCHEME=dark LuzLunar

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QProcess>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQmlExpression>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTimer>

#include <iterator>

#include "mac/macintegration.h"

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

    // Each step runs its script, waits, then saves a screenshot
    const Step k_Steps[] = {
        // A window tall enough for the redesign's Settings cards
        { nullptr, "window.width = 1280; window.height = 860", 500 },
        { "1-computers", nullptr, 6000 },
        // The PCs of this Mac, if it has any: the first one's apps, cached from its last visit
        { "1a-apps",
          "var pcs = stackView.currentItem.computerModel; "
          "if (pcs.rowCount() > 0) { "
          "  var appView = Qt.createComponent('qrc:/gui/AppView.qml').createObject(stackView, "
          "    { computerIndex: 0, objectName: pcs.data(pcs.index(0, 0), 256) }); "
          "  stackView.push(appView, StackView.Immediate) "
          "}", 3000 },
        { nullptr, "if (stackView.depth > 1) stackView.pop(null, StackView.Immediate)", 500 },
        // The CI Mac has no PCs, so show sample tiles in their states (running an app, asleep, not paired)
        { "1b-computer-tiles",
          "stackView.currentItem.model = Qt.createQmlObject('import QtQuick; ListModel { "
          "ListElement { name: \"GonzaloPC\"; online: true; paired: true; busy: true; statusUnknown: false; serverSupported: true; wakeable: true; details: \"\" } "
          "ListElement { name: \"Living Room\"; online: false; paired: true; busy: false; statusUnknown: false; serverSupported: true; wakeable: true; details: \"\" } "
          "ListElement { name: \"Office PC\"; online: true; paired: false; busy: false; statusUnknown: false; serverSupported: true; wakeable: false; details: \"\" } "
          "}', window); "
          "stackView.currentItem.currentIndex = 0; stackView.currentItem.forceActiveFocus()", 1500 },
        // The stream launch screen, with sample values (a real one needs a stream)
        { "1c-launch",
          "stackView.push(Qt.createQmlObject('import QtQuick; Item { ForkLaunchPanel { "
          "appName: \"Desktop\"; hostName: \"GonzaloPC\"; stageText: \"Starting RTSP handshake...\"; stagesDone: 4; started: true; "
          "summary: [\"3024×1890 · 16:10\", \"120 fps\", \"81 Mb/s\", \"HEVC · HDR\"] } }', stackView, 'qrc:/gui/HarnessLaunch.qml'), StackView.Immediate)", 2000 },
        { nullptr, "stackView.pop(null, StackView.Immediate)", 500 },
        { "2-settings-display", "settingsButton.clicked()", 2500 },
        { "2b-settings-display-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 1000 },
        { "2c-settings-video", "stackView.currentItem.showSection('video')", 1500 },
        { "2d-settings-audio", "stackView.currentItem.showSection('audio')", 1500 },
        { "2e-settings-mouse", "stackView.currentItem.showSection('mouse')", 1500 },
        { "2e2-settings-mouse-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 1000 },
        { "2f-settings-keyboard", "stackView.currentItem.showSection('keyboard')", 1500 },
        { "2g-settings-keyboard-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 1000 },
        { "2h-settings-gamepads", "stackView.currentItem.showSection('gamepads')", 1500 },
        { "2i-settings-host", "stackView.currentItem.showSection('host')", 1500 },
        { "2j-settings-app", "stackView.currentItem.showSection('app')", 1500 },
        { "2k-settings-mac", "stackView.currentItem.showSection('mac')", 1500 },
        { "2l-settings-mac-end", "stackView.currentItem.scrollY = stackView.currentItem.scrollMax", 1000 },
        { "5-add-pc-dialog", "goBack(); addPcDialog.open()", 2000 },
        // An app's stream settings: every row on Global, the Office preset, Office with one row
        // changed (Custom), the end of the list, and the top again in the window's default height
        { "6-stream-settings-dialog",
          "addPcDialog.close(); "
          "var d = Qt.createComponent('qrc:/gui/StreamProfileDialog.qml').createObject(window, "
          "  { appName: 'Office Mode', objectName: 'harnessStreamSettings' }); "
          "d.fields = d.buildFields(); d.open(); d.refresh()", 2000 },
        { "6a-stream-settings-office", "applyPreset(officePreset)", 1000, "harnessStreamSettings" },
        { "6b-stream-settings-custom", "chooseValue('fps', 60)", 1000, "harnessStreamSettings" },
        { "6c-stream-settings-end", "scrollY = scrollMax", 1000, "harnessStreamSettings" },
        { nullptr, "window.height = 600", 500 },
        { "6d-stream-settings-short", "scrollY = 0", 1500, "harnessStreamSettings" },
    };

    // Adds a line to harness-log.txt in the output folder
    void logLine(const QString& outputDir, const QString& line)
    {
        QFile file(QDir(outputDir).filePath("harness-log.txt"));
        if (file.open(QIODevice::Append | QIODevice::Text)) {
            file.write(line.toUtf8() + '\n');
        }
        qWarning().noquote() << "[fork] Screenshot harness:" << line;
    }

    QQuickWindow* mainWindow()
    {
        for (QWindow* window : QGuiApplication::topLevelWindows()) {
            if (auto quickWindow = qobject_cast<QQuickWindow*>(window)) {
                if (quickWindow->isVisible()) {
                    return quickWindow;
                }
            }
        }
        return nullptr;
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

        // QML's warnings while the steps run, once the main window's engine is there
        static bool watchingWarnings = false;
        if (!watchingWarnings) {
            if (QQmlEngine* engine = qmlEngine(window)) {
                watchingWarnings = true;
                QObject::connect(engine, &QQmlEngine::warnings, engine, [outputDir](const QList<QQmlError>& warnings) {
                    for (const QQmlError& warning : warnings) {
                        logLine(outputDir, warning.toString());
                    }
                });
            }
        }

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
                // title bar and native toolbar, if the CI Mac allows screen capture.
                if (long number = MacIntegration::windowNumber(window)) {
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

Q_COREAPP_STARTUP_FUNCTION(startScreenshotHarness)
