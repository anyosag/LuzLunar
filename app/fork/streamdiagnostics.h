#pragma once

#include <QString>

// [fork] Stream status's Copy Diagnostics: the stream right now, in a few lines of plain English for
// a bug report, from the same numbers Stream status shows. Main thread.
namespace ForkStreamDiagnostics
{
    // What the stream knows that ForkStreamStats and ForkNetworkLink don't
    struct Context {
        QString appName;
        QString hostName;
        int width = 0;
        int height = 0;
        int ownBitrateKbps = 0;     // the bitrate the user chose
        QString clipboard;          // like "automatic" or "off in Settings"
        QString drive;              // like "M: (the whole disk)"; empty for none
    };

    QString text(const Context& context);
}
