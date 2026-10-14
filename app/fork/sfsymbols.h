#pragma once

#include <QObject>
#include <QString>

class QQmlEngine;
class QQuickImageProvider;

// SF Symbols for QML on macOS, drawn by AppKit through the "sfsymbol" image provider:
//   IconImage { source: SfSymbols.url("desktopcomputer"); color: palette.windowText }
// The images are black template images for IconImage to tint. Elsewhere available is false and
// url() returns an empty string, so QML keeps its own icons.
class ForkSfSymbols : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool available READ isAvailable CONSTANT)

public:
    // Also adds the image provider to the engine
    static ForkSfSymbols* get(QQmlEngine* engine);

    bool isAvailable() const;

    Q_INVOKABLE QString url(const QString& symbolName) const;

private:
    ForkSfSymbols() = default;
};

#ifdef Q_OS_DARWIN
// In mac/sfsymbolprovider.mm
QQuickImageProvider* createSfSymbolProvider();
#endif
