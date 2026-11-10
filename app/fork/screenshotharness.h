#pragma once

#include <QtGlobal>

class QQmlEngine;

// [fork] CI's UI screenshots (screenshotharness.cpp, macOS only). The harness starts by itself when
// LUZLUNAR_SCREENSHOTS is set; this is what main.cpp has to hand it.
namespace ScreenshotHarness
{
#ifdef Q_OS_DARWIN
    // With LUZLUNAR_SCREENSHOTS set, the engine's QML warnings go to harness-log.txt from now on.
    // main.cpp calls it before the engine loads main.qml, so the warnings while it loads are there
    // too. Does nothing otherwise.
    void watchWarnings(QQmlEngine* engine);
#else
    inline void watchWarnings(QQmlEngine*) {}
#endif
}
