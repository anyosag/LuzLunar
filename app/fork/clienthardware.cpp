#include "clienthardware.h"

#include "clientdisplay.h"
#include "forkpreferences.h"

#include "settings/streamingpreferences.h"

// The platform parts (read and watchDisplays) are in mac/clienthardware_mac.mm on macOS (a different name, so qmake doesn't give both files the same object file)

namespace
{
    ForkHwRules::Codec codecFor(int videoCodecConfig)
    {
        switch (videoCodecConfig) {
        case StreamingPreferences::VCC_FORCE_H264:
            return ForkHwRules::Codec::H264;
        case StreamingPreferences::VCC_FORCE_HEVC:
        case StreamingPreferences::VCC_FORCE_HEVC_HDR_DEPRECATED:
            return ForkHwRules::Codec::HEVC;
        case StreamingPreferences::VCC_FORCE_AV1:
            return ForkHwRules::Codec::AV1;
        default:
            return ForkHwRules::Codec::Auto;
        }
    }

    // "AV1", "AV1 and HEVC", "AV1, HEVC and H.264"
    QString joinNames(const QStringList& names)
    {
        if (names.size() <= 1) {
            return names.join(QString());
        }
        return names.mid(0, names.size() - 1).join(QStringLiteral(", ")) + QStringLiteral(" and ") + names.last();
    }
}

ClientHardware* ClientHardware::get()
{
    static ClientHardware* instance = new ClientHardware();
    return instance;
}

ClientHardware::ClientHardware(QObject* parent)
    : QObject(parent)
{
    refresh();
    ClientHardwarePlatform::watchDisplays([this]() { refresh(); });

    // hdrPeak follows the setting
    connect(ForkPreferences::get(), &ForkPreferences::hdrPeakOverrideChanged, this, &ClientHardware::refresh);
}

void ClientHardware::refresh()
{
    m_Info = ClientHardwarePlatform::read();

    m_Decoders = {
        { "h264", m_Info.decoders.h264 },
        { "hevc", m_Info.decoders.hevc },
        { "hevcMain10", m_Info.decoders.hevcMain10 },
        { "av1", m_Info.decoders.av1 },
    };

    m_Displays.clear();
    for (const Display& display : m_Info.displays) {
        const ForkHwRules::Display& rules = display.rules;
        m_Displays.append(QVariantMap {
            { "name", QString::fromStdString(rules.name) },
            { "nativeWidth", rules.nativeWidth },
            { "nativeHeight", rules.nativeHeight },
            { "safeWidth", rules.safeWidth },
            { "safeHeight", rules.safeHeight },
            { "fullRatio", QString::fromStdString(ForkHwRules::ratioLabel(rules.nativeWidth, rules.nativeHeight)) },
            { "belowNotchRatio", QString::fromStdString(ForkHwRules::ratioLabel(rules.safeWidth, rules.safeHeight)) },
            { "pointWidth", display.pointWidth },
            { "pointHeight", display.pointHeight },
            { "scale", rules.scale },
            { "hasNotch", rules.hasNotch },
            { "maxRefresh", rules.maxRefresh },
            { "hdr", rules.hdr },
            { "isBuiltin", display.isBuiltin },
            { "widthMm", rules.widthMm },
            { "heightMm", rules.heightMm },
            { "p3", rules.p3 },
            { "edrPotential", rules.edrPotential },
            { "hdrPeak", ClientDisplay::describe(rules, display.isBuiltin, ForkPreferences::get()->hdrPeakOverride()).peakNits },
            { "isMain", display.isMain },
            { "isMirror", display.isMirror },
            { "isDisplayExtend", display.isDisplayExtend },
        });
    }

    m_Summary = buildSummary();
    emit changed();
}

QString ClientHardware::buildSummary() const
{
    QStringList parts;
    if (!m_Info.chip.isEmpty()) {
        parts << m_Info.chip;
    }

    // The first display is the main one
    if (!m_Info.displays.empty()) {
        const ForkHwRules::Display& rules = m_Info.displays.front().rules;
        QString text = QStringLiteral("%1 %2×%3").arg(QString::fromStdString(rules.name))
                                                 .arg(rules.nativeWidth).arg(rules.nativeHeight);
        if (rules.hasNotch) {
            text += QStringLiteral(", %1 below the notch")
                    .arg(QString::fromStdString(ForkHwRules::ratioLabel(rules.safeWidth, rules.safeHeight)));
        }
        else {
            text += QStringLiteral(", %1").arg(QString::fromStdString(ForkHwRules::ratioLabel(rules.nativeWidth, rules.nativeHeight)));
        }
        parts << text.trimmed();

        if (rules.maxRefresh > 0) {
            parts << QStringLiteral("%1 Hz").arg(rules.maxRefresh);
        }
        if (rules.hdr) {
            parts << QStringLiteral("HDR");
        }
    }

    // The newest codec first
    QStringList codecs;
    if (m_Info.decoders.av1) {
        codecs << QStringLiteral("AV1");
    }
    if (m_Info.decoders.hevc) {
        codecs << QStringLiteral("HEVC");
    }
    if (m_Info.decoders.h264) {
        codecs << QStringLiteral("H.264");
    }
    parts << (codecs.isEmpty() ? QStringLiteral("no hardware video decoding")
                               : joinNames(codecs) + QStringLiteral(" hardware decoding"));

    return parts.join(QStringLiteral(" · "));
}

QStringList ClientHardware::warningsFor(int width, int height, int fps, int videoCodecConfig,
                                        bool hdr, int displayIndex) const
{
    // No display to check the frame rate against if the index is out of range
    ForkHwRules::Display noDisplay;
    const ForkHwRules::Display* display = &noDisplay;
    if (displayIndex >= 0 && displayIndex < static_cast<int>(m_Info.displays.size())) {
        display = &m_Info.displays[displayIndex].rules;
    }

    QStringList warnings;
    for (const std::string& warning : ForkHwRules::checkStream(m_Info.decoders, *display, width, height, fps,
                                                               codecFor(videoCodecConfig), hdr)) {
        warnings << QString::fromStdString(warning);
    }
    return warnings;
}

#ifndef Q_OS_DARWIN

ClientHardware::Snapshot ClientHardwarePlatform::read()
{
    return ClientHardware::Snapshot();
}

void ClientHardwarePlatform::watchDisplays(std::function<void()>)
{
}

#endif
