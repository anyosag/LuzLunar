#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <functional>
#include <vector>

#include "forkhwrules.h"

// What this Mac is (the machine LuzLunar runs on, not the host PC): chip, GPU, hardware video
// decoders and displays. Settings shows it as "This Mac" and warns about stream settings the
// hardware can't handle (forkhwrules.*). Read once at startup and again on refresh(), which also
// runs when the displays change.
class ClientHardware : public QObject
{
    Q_OBJECT

    // "Apple M4 Pro"
    Q_PROPERTY(QString chip READ chip NOTIFY changed)

    // The default Metal device's name; empty if there's none
    Q_PROPERTY(QString gpu READ gpu NOTIFY changed)

    // h264, hevc, hevcMain10 and av1, each true if decoded in hardware
    Q_PROPERTY(QVariantMap decoders READ decoders NOTIFY changed)

    // One map per display, in the order StreamUtils uses for its display index
    // (CGGetActiveDisplayList): name, nativeWidth, nativeHeight, safeWidth, safeHeight,
    // fullRatio, belowNotchRatio, pointWidth, pointHeight, scale, hasNotch, maxRefresh, hdr,
    // isBuiltin. Sizes are in pixels except the point size. A notched display has two shapes: the
    // full panel (native, e.g. 3024x1964, 1.54:1) and the area below the notch (safe, 3024x1890,
    // 16:10). Without a notch the safe size and belowNotchRatio equal the native ones.
    // maxRefresh is 0 if unknown.
    Q_PROPERTY(QVariantList displays READ displays NOTIFY changed)

    // One line, like "Apple M4 Pro · Built-in Retina Display 3024×1964, 16:10 below the notch ·
    // 120 Hz · HDR · AV1, HEVC and H.264 hardware decoding"
    Q_PROPERTY(QString summary READ summary NOTIFY changed)

public:
    // What the platform code reads
    struct Display {
        ForkHwRules::Display rules;
        int pointWidth = 0, pointHeight = 0;
        bool isBuiltin = false;
    };

    struct Snapshot {
        QString chip;
        QString gpu;
        ForkHwRules::Decoders decoders;
        std::vector<Display> displays;
    };

    static ClientHardware* get();

    QString chip() const { return m_Info.chip; }
    QString gpu() const { return m_Info.gpu; }
    QVariantMap decoders() const { return m_Decoders; }
    QVariantList displays() const { return m_Displays; }
    QString summary() const { return m_Summary; }

    // Reads everything again
    Q_INVOKABLE void refresh();

    // Warnings about a stream's settings on this Mac and the display at displayIndex (the same
    // index as displays); empty if all is fine. videoCodecConfig is a
    // StreamingPreferences::VideoCodecConfig. An index that doesn't exist skips the display checks.
    Q_INVOKABLE QStringList warningsFor(int width, int height, int fps, int videoCodecConfig,
                                        bool hdr, int displayIndex = 0) const;

signals:
    void changed();

private:
    explicit ClientHardware(QObject* parent = nullptr);

    QString buildSummary() const;

    Snapshot m_Info;
    QVariantMap m_Decoders;
    QVariantList m_Displays;
    QString m_Summary;
};

// The platform half, in mac/clienthardware_mac.mm; other platforms get an empty snapshot
namespace ClientHardwarePlatform
{
    ClientHardware::Snapshot read();

    // Calls onChange (on the GUI thread) whenever the displays change
    void watchDisplays(std::function<void()> onChange);
}
