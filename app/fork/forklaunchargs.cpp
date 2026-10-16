#include "forklaunchargs.h"

#include "clientdisplay.h"
#include "clienthardware.h"
#include "forkpreferences.h"
#include "forkvideoscaling.h"
#include "SDL_compat.h"

#include <QMutex>
#include <QMutexLocker>

namespace ForkLaunchArgs
{

namespace
{
    QMutex s_Lock;
    QString s_Args;
}

void capture(QWindow* qtWindow)
{
    QString args;

#ifdef Q_OS_DARWIN
    ForkPreferences* prefs = ForkPreferences::get();
    if (prefs->describeDisplay()) {
        int index = ForkVideoScaling::displayIndexFor(qtWindow);
        const std::vector<ClientHardware::Display>& displays = ClientHardware::get()->info().displays;

        if (index >= 0 && index < static_cast<int>(displays.size())) {
            const ClientHardware::Display& display = displays[index];
            const ForkHwRules::Display& r = display.rules;
            ClientDisplay::Description d = ClientDisplay::describe(r, display.isBuiltin, prefs->hdrPeakOverride());
            args = QString::fromStdString(ClientDisplay::queryArgs(d));

            // Also what the HDR brightness rules are tuned against
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Describing %s to the host: %dx%d mm, %dx%d (%dx%d below the notch), %d-%d Hz, %s, "
                        "EDR %.2f potential / %.2f now / %.2f reference, HDR %s",
                        r.name.c_str(), r.widthMm, r.heightMm, r.nativeWidth, r.nativeHeight, d.safeWidth, d.safeHeight,
                        r.minRefresh, r.maxRefresh, r.p3 ? "Display P3" : "sRGB",
                        r.edrPotential, r.edrCurrent, r.edrReference,
                        !d.hdr ? "no" : d.peakNits > 0 ? QString("%1/%2 nits").arg(d.peakNits).arg(d.fullFrameNits).toUtf8().constData() : "of unknown brightness");
        }
        else {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Not describing the screen to the host: can't tell which one the stream is on");
        }
    }
#else
    (void)qtWindow;
#endif

    QMutexLocker lock(&s_Lock);
    s_Args = args;
}

QString take(bool isNvidiaServerSoftware)
{
    QMutexLocker lock(&s_Lock);
    QString args = s_Args;
    s_Args.clear();
    return isNvidiaServerSoftware ? QString() : args;
}

}
