// UI screenshots for CI. Inactive unless LUZLUNAR_SCREENSHOTS is set to an output folder. Then the
// app opens its main views and dialogs one after another, saves each window as a PNG with Qt's own
// window grab (no screen recording permission needed), and quits.
//
//   LUZLUNAR_SCREENSHOTS=/tmp/shots LUZLUNAR_SCREENSHOT_SCHEME=dark LuzLunar

#include <QCoreApplication>
#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QQmlContext>
#include <QQmlExpression>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTimer>

#include <iterator>

namespace
{
    struct Step {
        const char* name;     // screenshot file name, or null to only run the script
        const char* script;   // evaluated in main.qml's context before the screenshot, or null
        int delayMs;          // time to wait after the script
    };

    // Each step runs its script, waits, then saves a screenshot
    const Step k_Steps[] = {
        { "1-computers", nullptr, 6000 },
        { "2-settings-top", "settingsButton.clicked()", 2500 },
        { "3-settings-middle", "stackView.currentItem.contentY = Math.max(0, stackView.currentItem.contentHeight / 2 - stackView.currentItem.height / 2)", 1500 },
        { "4-settings-bottom", "stackView.currentItem.contentY = Math.max(0, stackView.currentItem.contentHeight - stackView.currentItem.height)", 1500 },
        { "5-add-pc-dialog", "goBack(); addPcDialog.open()", 2000 },
        { "6-stream-settings-dialog",
          "addPcDialog.close(); "
          "var d = Qt.createComponent('qrc:/gui/StreamProfileDialog.qml').createObject(window, { appName: 'Office Mode' }); "
          "d.fields = d.buildFields(); d.open(); d.refresh()", 2000 },
    };

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

        if (step.script != nullptr) {
            QQmlExpression expression(qmlContext(window), window, QString::fromUtf8(step.script));
            expression.evaluate();
            if (expression.hasError()) {
                qWarning() << "[fork] Screenshot harness script failed:" << expression.error().toString();
            }
        }

        QTimer::singleShot(step.delayMs, [outputDir, index, step]() {
            if (QQuickWindow* window = mainWindow()) {
                QString path = QDir(outputDir).filePath(QString::fromUtf8(step.name) + ".png");
                if (window->grabWindow().save(path)) {
                    qInfo() << "[fork] Saved screenshot" << path;
                }
                else {
                    qWarning() << "[fork] Couldn't save screenshot" << path;
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
                QGuiApplication::styleHints()->setColorScheme(scheme == "dark" ? Qt::ColorScheme::Dark : Qt::ColorScheme::Light);
            }
            runStep(outputDir, 0);
        });
    }
}

Q_COREAPP_STARTUP_FUNCTION(startScreenshotHarness)
