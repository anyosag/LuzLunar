#include "streamdiagnostics.h"

#include <cmath>
#include <vector>

#include <QStringList>
#include <QSysInfo>

#include "clienthardware.h"
#include "forklinkrules.h"
#include "forknetworklink.h"
#include "forkpreferences.h"
#include "hostcadence.h"
#include "notchstatus.h"
#include "path.h"
#include "streamstats.h"

namespace ForkStreamDiagnostics
{
namespace
{
    QString ms(double value)
    {
        return StreamHistory::known(value) ? QString::number(value, 'f', 1) + QStringLiteral(" ms") : QStringLiteral("?");
    }

    QString percent(double value)
    {
        return QString::number(value, 'f', 1) + QStringLiteral("%");
    }
}

QString text(const Context& context)
{
    QStringList lines;
    ClientHardware* hardware = ClientHardware::get();
    lines << QStringLiteral("LuzLunar %1 on %2%3")
                 .arg(ForkPreferences::get()->buildId(), QSysInfo::prettyProductName(),
                      hardware != nullptr && !hardware->chip().isEmpty() ? QStringLiteral(" (%1)").arg(hardware->chip()) : QString());
    lines << QStringLiteral("Streaming %1 from %2").arg(context.appName, context.hostName);

    ForkStreamStats::Snapshot latest;
    bool haveLatest = ForkStreamStats::latest(&latest);
    QString video = QStringLiteral("Video: %1×%2").arg(context.width).arg(context.height);
    if (haveLatest) {
        video += QStringLiteral(" · %1 · %2 fps · %3 Mb/s received")
                     .arg(latest.codec)
                     .arg(latest.fps, 0, 'f', 0)
                     .arg(latest.mbps, 0, 'f', 1);
    }
    lines << video;
    lines << QStringLiteral("Bitrate: %1").arg(context.bitrate);

    ForkNetworkLink::Current link = ForkNetworkLink::current();
    if (link.known) {
        std::string speed = ForkLinkRules::speedText(link.link.mbps);
        lines << QStringLiteral("Connection: %1%2")
                     .arg(QString::fromStdString(ForkLinkRules::connectionText(link.link, link.viaLan)),
                          speed.empty() ? QString() : QStringLiteral(" · ") + QString::fromStdString(speed));
    }
    else {
        lines << QStringLiteral("Connection: not known yet");
    }

    if (haveLatest) {
        const StreamHistory::Parts& parts = latest.latencyMs;
        lines << QStringLiteral("Latency now: %1 (PC capture and encode %2, network round trip %3 ± %4 ms, Mac decode %5, display %6)")
                     .arg(ms(StreamHistory::total(parts)), ms(parts[StreamHistory::PcCaptureAndEncode]),
                          ms(parts[StreamHistory::NetworkRoundTrip]))
                     .arg(latest.rttVarianceMs)
                     .arg(ms(parts[StreamHistory::MacDecode]), ms(parts[StreamHistory::Display]));
        lines << QStringLiteral("Frames lost: %1 on the network, %2 to jitter")
                     .arg(percent(latest.dropPercent), percent(latest.jitterDropPercent));

        PacingVerdict verdict = pacingVerdict(latest.pacingLowest, latest.fps);
        if (StreamHistory::known(latest.pacingLowest)) {
            lines << QStringLiteral("PC frame pacing: %1 (lowest %2 %, average %3 %)")
                         .arg(verdict == PacingVerdict::Even ? QStringLiteral("even") : verdict == PacingVerdict::Uneven ? QStringLiteral("uneven")
                                                                                                                        : QStringLiteral("no verdict"))
                         .arg(latest.pacingLowest, 0, 'f', 1)
                         .arg(latest.pacingAverage, 0, 'f', 1);
        }
        else {
            lines << QStringLiteral("PC frame pacing: no score");
        }
    }
    else {
        lines << QStringLiteral("No video yet");
    }

    std::vector<StreamHistory::Sample> samples = ForkStreamStats::history();
    NotchStatus::Summary summary = NotchStatus::summarize(samples);
    if (summary.any) {
        int cuts = 0;
        for (const StreamHistory::Sample& sample : samples) {
            cuts += sample.lowered ? 1 : 0;
        }
        double now = ForkStreamStats::nowSeconds();
        lines << QStringLiteral("Last 2 minutes: usually %1, peak %2 %3 s ago, %4 bitrate cut(s), %5 samples")
                     .arg(ms(summary.usualMs), ms(summary.peakMs))
                     .arg(NotchStatus::secondsAgo(now - samples[summary.peakIndex].seconds))
                     .arg(cuts)
                     .arg(static_cast<int>(samples.size()));
    }

    lines << QStringLiteral("Clipboard sync: %1").arg(context.clipboard);
    lines << QStringLiteral("Mac drive: %1").arg(context.drive.isEmpty() ? QStringLiteral("none") : context.drive);
    lines << QStringLiteral("Logs: %1/Moonlight-*.log").arg(Path::getLogDir());
    return lines.join(QLatin1Char('\n')) + QLatin1Char('\n');
}
}
