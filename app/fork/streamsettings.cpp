#include "streamsettings.h"

#include <algorithm>
#include <cmath>

#include <QCoreApplication>
#include <QVariantMap>

#include "forkaspectratios.h"
#include "settings/streamingpreferences.h"
#include "streamprofiles.h"

using StreamSettingsRules::Key;
using StreamSettingsRules::Profile;

namespace
{
    QString tr(const char* text)
    {
        return QCoreApplication::translate("NotchBar", text);
    }

    // StreamProfiles' keys for each setting; the resolution is width and height
    const char* profileKey(Key key)
    {
        switch (key) {
        case Key::Resolution:
            return nullptr;
        case Key::Fps:
            return "fps";
        case Key::Hdr:
            return "enableHdr";
        case Key::Codec:
            return "videoCodecConfig";
        case Key::Yuv444:
            return "enableYUV444";
        case Key::Bitrate:
            return "bitrateKbps";
        case Key::Fill:
            return "fullscreenStretch";
        case Key::Vsync:
            return "enableVsync";
        case Key::Pacing:
            return "framePacing";
        case Key::Mouse:
            return "absoluteMouseMode";
        case Key::Trackpad:
            return "trackpadMode";
        }
        return nullptr;
    }

    bool isBool(Key key)
    {
        return key == Key::Hdr || key == Key::Yuv444 || key == Key::Fill || key == Key::Vsync || key == Key::Pacing ||
               key == Key::Mouse;
    }

    Profile fromProfile(const QVariantMap& map)
    {
        Profile profile;
        for (Key key : StreamSettingsRules::keys()) {
            if (key == Key::Resolution) {
                if (map.contains("width") && map.contains("height")) {
                    profile[key] = ReconnectRules::packSize({ map.value("width").toInt(), map.value("height").toInt() });
                }
                continue;
            }
            QString name = QString::fromLatin1(profileKey(key));
            if (map.contains(name)) {
                profile[key] = isBool(key) ? (map.value(name).toBool() ? 1 : 0) : map.value(name).toInt();
            }
        }
        return profile;
    }

    QVariantMap toProfile(const Profile& profile)
    {
        QVariantMap map;
        for (const auto& [key, value] : profile) {
            if (key == Key::Resolution) {
                ReconnectRules::Size size = ReconnectRules::unpackSize(value);
                map.insert("width", size.width);
                map.insert("height", size.height);
            }
            else if (isBool(key)) {
                map.insert(QString::fromLatin1(profileKey(key)), value != 0);
            }
            else {
                map.insert(QString::fromLatin1(profileKey(key)), value);
            }
        }
        return map;
    }

    Profile fromSettings(const StreamingPreferences& prefs, bool asRunning = false)
    {
        // As the stream runs, the remote desktop's mouse is there only with Mac mouse
        bool absolute = prefs.absoluteMouseMode && (!asRunning || prefs.trackpadMode == StreamingPreferences::TM_MAC_MOUSE);
        return { { Key::Resolution, ReconnectRules::packSize({ prefs.width, prefs.height }) },
                 { Key::Fps, prefs.fps },
                 { Key::Hdr, prefs.enableHdr ? 1 : 0 },
                 { Key::Codec, prefs.videoCodecConfig },
                 { Key::Yuv444, prefs.enableYUV444 ? 1 : 0 },
                 { Key::Bitrate, prefs.bitrateKbps },
                 { Key::Fill, prefs.fullscreenStretch ? 1 : 0 },
                 { Key::Vsync, prefs.enableVsync ? 1 : 0 },
                 { Key::Pacing, prefs.framePacing ? 1 : 0 },
                 { Key::Mouse, absolute ? 1 : 0 },
                 { Key::Trackpad, prefs.trackpadMode } };
    }

    QString sizeText(int packed)
    {
        ReconnectRules::Size size = ReconnectRules::unpackSize(packed);
        return QStringLiteral("%1 × %2").arg(size.width).arg(size.height);
    }
}

ForkStreamSettings::ForkStreamSettings(const QString& hostUuid, const QString& hostName, const QString& appName,
                                       const std::optional<std::map<int, int>>& carriedBaseline)
    : m_HostUuid(hostUuid),
      m_HostName(hostName),
      m_AppName(appName),
      m_Display(AspectRatios::get()->defaultDisplay()),
      m_Global(fromSettings(*StreamingPreferences::get())),
      m_Saved(fromProfile(StreamProfiles::get()->profile(hostUuid, appName)))
{
    m_Baseline = carriedBaseline ? unpack(*carriedBaseline) : m_Saved;
    m_Draft = m_Baseline;
    // The Custom card's settings: what the stream applied, else what's saved, if either isn't a preset
    if (StreamSettingsRules::presetOf(m_Baseline) == StreamSettingsRules::Preset::Custom) {
        m_LastCustom = m_Baseline;
    }
    else if (StreamSettingsRules::presetOf(m_Saved) == StreamSettingsRules::Preset::Custom) {
        m_LastCustom = m_Saved;
    }
}

Profile ForkStreamSettings::fromPreferences(const StreamingPreferences& prefs)
{
    return fromSettings(prefs, true);
}

std::map<int, int> ForkStreamSettings::pack(const Profile& profile)
{
    std::map<int, int> packed;
    for (const auto& [key, value] : profile) {
        packed[static_cast<int>(key)] = value;
    }
    return packed;
}

Profile ForkStreamSettings::unpack(const std::map<int, int>& packed)
{
    Profile profile;
    for (const auto& [key, value] : packed) {
        profile[static_cast<Key>(key)] = value;
    }
    return profile;
}

// The ratio the resolution list is for: the ratio of the size the stream would get
QString ForkStreamSettings::effectiveRatioKey(const Profile& profile) const
{
    ReconnectRules::Size size = ReconnectRules::unpackSize(StreamSettingsRules::effective(profile, m_Global, Key::Resolution));
    return AspectRatios::get()->keyFor(size.width, size.height, m_Display);
}

QVariantList ForkStreamSettings::sizesFor(const QString& ratioKey) const
{
    double ratio = 0;
    if (ratioKey == QStringLiteral("custom")) {
        // A size of no standard ratio: its own ratio's sizes, as the dialog lists them
        ReconnectRules::Size size = ReconnectRules::unpackSize(StreamSettingsRules::effective(m_Draft, m_Global, Key::Resolution));
        ratio = size.height > 0 ? static_cast<double>(size.width) / size.height : 0;
    }
    return AspectRatios::get()->presets(ratioKey, ratio, m_Display);
}

// The size to pick for a ratio, as the dialog does: the one that fills the display, else the one
// nearest the draft's size by pixel count
std::optional<int> ForkStreamSettings::fillingSize(const QString& ratioKey) const
{
    ReconnectRules::Size current = ReconnectRules::unpackSize(StreamSettingsRules::effective(m_Draft, m_Global, Key::Resolution));
    QVariantList presets = sizesFor(ratioKey);
    std::optional<int> best;
    double bestDistance = 0;
    for (const QVariant& item : presets) {
        QVariantMap preset = item.toMap();
        int width = preset.value("width").toInt();
        int height = preset.value("height").toInt();
        int packed = ReconnectRules::packSize({ width, height });
        if (preset.value("fills").toBool()) {
            return packed;
        }
        double area = static_cast<double>(current.width) * current.height;
        double distance = area > 0 ? std::fabs(std::log(static_cast<double>(width) * height / area)) : 0;
        if (!best || distance < bestDistance) {
            best = packed;
            bestDistance = distance;
        }
    }
    return best;
}

std::vector<ForkStreamSettings::Option> ForkStreamSettings::options(RowId row) const
{
    std::vector<Option> result;
    auto onOff = [&] {
        result.push_back({ tr("On"), QString(), 1, QString() });
        result.push_back({ tr("Off"), QString(), 0, QString() });
    };
    switch (row) {
    case RowId::Aspect: {
        // The display's shapes and the standard ratios; typing a ratio is left to the dialog
        for (const QVariant& item : AspectRatios::get()->ratios(m_Display)) {
            QVariantMap ratio = item.toMap();
            QString key = ratio.value("key").toString();
            if (key != QStringLiteral("custom")) {
                result.push_back({ ratio.value("label").toString(), QString(), 0, key });
            }
        }
        if (effectiveRatioKey(m_Draft) == QStringLiteral("custom")) {
            ReconnectRules::Size size = ReconnectRules::unpackSize(StreamSettingsRules::effective(m_Draft, m_Global, Key::Resolution));
            result.push_back({ tr("Custom (%1)").arg(AspectRatios::get()->ratioLabel(size.width, size.height)), QString(), 0,
                               QStringLiteral("custom") });
        }
        break;
    }
    case RowId::Resolution: {
        // The sizes of the ratio, then the draft's own if it's another; typing one is left to the dialog
        for (const QVariant& item : sizesFor(effectiveRatioKey(m_Draft))) {
            QVariantMap preset = item.toMap();
            int packed = ReconnectRules::packSize({ preset.value("width").toInt(), preset.value("height").toInt() });
            result.push_back({ preset.value("text").toString(), sizeText(packed), packed, QString() });
        }
        auto set = m_Draft.find(Key::Resolution);
        if (set != m_Draft.end()) {
            bool listed = false;
            for (const Option& option : result) {
                listed = listed || option.value == set->second;
            }
            if (!listed) {
                result.push_back({ sizeText(set->second), QString(), set->second, QString() });
            }
        }
        break;
    }
    case RowId::Fps:
        for (int fps : { 30, 60, 90, 120 }) {
            result.push_back({ tr("%1 FPS").arg(fps), QString(), fps, QString() });
        }
        break;
    case RowId::Hdr:
    case RowId::Yuv444:
    case RowId::Vsync:
    case RowId::Pacing:
        onOff();
        break;
    case RowId::Codec:
        result.push_back({ tr("Automatic"), QString(), StreamingPreferences::VCC_AUTO, QString() });
        result.push_back({ QStringLiteral("H.264"), QString(), StreamingPreferences::VCC_FORCE_H264, QString() });
        result.push_back({ QStringLiteral("HEVC"), QString(), StreamingPreferences::VCC_FORCE_HEVC, QString() });
        result.push_back({ QStringLiteral("AV1"), QString(), StreamingPreferences::VCC_FORCE_AV1, QString() });
        break;
    case RowId::Bitrate: {
        std::vector<int> mbps = { 10, 20, 30, 40, 50, 60, 80, 100, 150 };
        for (int value : mbps) {
            result.push_back({ tr("%1 Mbps").arg(value), QString(), value * 1000, QString() });
        }
        // A bitrate set that isn't on the list stays choosable
        auto set = m_Draft.find(Key::Bitrate);
        if (set != m_Draft.end() && set->second % 1000 != 0) {
            result.push_back({ tr("%1 Mbps").arg(set->second / 1000.0, 0, 'f', 1), QString(), set->second, QString() });
        }
        else if (set != m_Draft.end() && std::find(mbps.begin(), mbps.end(), set->second / 1000) == mbps.end()) {
            result.push_back({ tr("%1 Mbps").arg(set->second / 1000), QString(), set->second, QString() });
        }
        break;
    }
    case RowId::Fill:
        // The canvas's names, shorter than the dialog's
        result.push_back({ tr("Fit"), QString(), 0, QString() });
        result.push_back({ tr("Stretch"), QString(), 1, QString() });
        break;
    case RowId::Mouse:
        result.push_back({ tr("Remote desktop"), QString(), 1, QString() });
        result.push_back({ tr("Games"), QString(), 0, QString() });
        break;
    case RowId::Trackpad:
        result.push_back({ tr("Mac trackpad"), QString(), ReconnectRules::k_TrackpadMacTrackpad, QString() });
        result.push_back({ tr("Windows touchpad"), QString(), ReconnectRules::k_TrackpadWindowsTouchpad, QString() });
        result.push_back({ tr("Mac mouse"), QString(), ReconnectRules::k_TrackpadMacMouse, QString() });
        break;
    }
    return result;
}

namespace
{
    Key keyOf(int row)
    {
        // Rows after the aspect ratio's, in order
        static const Key keys[] = { Key::Resolution, Key::Resolution, Key::Fps, Key::Hdr, Key::Codec, Key::Yuv444,
                                    Key::Bitrate, Key::Fill, Key::Vsync, Key::Pacing, Key::Mouse, Key::Trackpad };
        return keys[row];
    }
}

// A row's value as its capsule shows it: the option's short text, else its own
QString ForkStreamSettings::valueText(RowId row, const Profile& profile) const
{
    if (row == RowId::Aspect) {
        QString key = effectiveRatioKey(profile);
        for (const QVariant& item : AspectRatios::get()->ratios(m_Display)) {
            QVariantMap ratio = item.toMap();
            if (ratio.value("key").toString() == key && key != QStringLiteral("custom")) {
                return ratio.value("label").toString();
            }
        }
        ReconnectRules::Size size = ReconnectRules::unpackSize(StreamSettingsRules::effective(profile, m_Global, Key::Resolution));
        return tr("Custom (%1)").arg(AspectRatios::get()->ratioLabel(size.width, size.height));
    }
    Key key = keyOf(static_cast<int>(row));
    int value = StreamSettingsRules::effective(profile, m_Global, key);
    if (row == RowId::Resolution) {
        return sizeText(value);
    }
    if (row == RowId::Bitrate) {
        return value % 1000 == 0 ? tr("%1 Mbps").arg(value / 1000) : tr("%1 Mbps").arg(value / 1000.0, 0, 'f', 1);
    }
    for (const Option& option : options(row)) {
        if (option.value == value) {
            return option.shortText.isEmpty() ? option.text : option.shortText;
        }
    }
    return QString::number(value);
}

ForkStreamSettings::View ForkStreamSettings::view(const StreamSettingsRules::Stream& stream, const Profile& actual, bool open)
{
    using StreamSettingsRules::Preset;
    if (open) {
        m_Draft = m_Baseline;
        m_Touched.clear();
    }
    m_Stream = stream;

    View view;
    view.title = tr("Stream Settings for %1").arg(m_AppName);
    Preset preset = StreamSettingsRules::presetOf(m_Draft);
    view.preset = preset == Preset::Office ? 0 : preset == Preset::Gaming ? 1 : preset == Preset::Custom ? 2 : -1;
    QString profileName = preset == Preset::Office ? tr("Office profile") :
                          preset == Preset::Gaming ? tr("Gaming profile") :
                          preset == Preset::Custom ? tr("Custom profile") : tr("Follows Settings");
    view.subtitle = QStringLiteral("%1 · %2").arg(m_HostName, profileName);
    int count = static_cast<int>(m_Draft.size());
    view.countText = count == 0 ? tr("Every setting follows Settings.") :
                     count == 1 ? tr("1 setting is set for %1. The rest follow Settings.").arg(m_AppName)
                                : tr("%1 settings are set for %2. The rest follow Settings.").arg(count).arg(m_AppName);

    struct SectionRows {
        const char* title;
        std::vector<RowId> rows;
    };
    static const SectionRows layout[] = {
        { "Picture", { RowId::Aspect, RowId::Resolution, RowId::Fps, RowId::Hdr } },
        { "Video", { RowId::Codec, RowId::Yuv444, RowId::Bitrate } },
        { "Window", { RowId::Fill, RowId::Vsync, RowId::Pacing } },
        { "Mouse & trackpad", { RowId::Mouse, RowId::Trackpad } },
    };
    static const char* labels[] = { "Aspect ratio", "Resolution", "Frame rate", "HDR", "Video codec", "Full color (4:4:4)",
                                    "Bitrate", "Fullscreen fill", "V-Sync", "Frame pacing", "Mouse", "Trackpad" };

    for (const SectionRows& sectionRows : layout) {
        Section section;
        section.title = tr(sectionRows.title);
        for (RowId id : sectionRows.rows) {
            Key key = keyOf(static_cast<int>(id));
            Row row;
            row.label = tr(labels[static_cast<int>(id)]);
            row.value = valueText(id, m_Draft);
            // The aspect ratio isn't stored: it's set with the resolution
            row.set = m_Draft.count(key) != 0;
            int value = StreamSettingsRules::effective(m_Draft, m_Global, key);
            row.reconnects = StreamSettingsRules::reconnects(key, value, stream);
            row.accessibility = QStringLiteral("%1: %2, %3").arg(row.label, row.value,
                                                                  row.set ? tr("set for this app") : tr("follows Settings"));

            // Global first, with Settings' value
            Choice global;
            global.text = tr("Global (%1)").arg(valueText(id, Profile()));
            global.checked = !row.set;
            global.separatorAfter = true;
            row.choices.push_back(global);
            QString ratioKey = id == RowId::Aspect ? effectiveRatioKey(m_Draft) : QString();
            for (const Option& option : options(id)) {
                Choice choice;
                choice.text = option.text;
                if (id == RowId::Aspect) {
                    choice.checked = row.set && option.ratioKey == ratioKey;
                }
                else {
                    choice.checked = row.set && m_Draft.at(key) == option.value;
                }
                // Only where the row's other values don't: rows that always reconnect say so by their label
                choice.reconnects = !StreamSettingsRules::alwaysReconnects(key, stream) &&
                                    StreamSettingsRules::reconnects(key, option.value, stream);
                // A trackpad mode the PC's Apollo can't take is greyed, as in Control Center
                if (key == Key::Trackpad && !choice.checked) {
                    choice.enabled = option.value == ReconnectRules::k_TrackpadMacMouse ||
                                     (option.value == ReconnectRules::k_TrackpadWindowsTouchpad ? stream.touchpadSupported
                                                                                                 : stream.macTrackpadSupported);
                }
                row.choices.push_back(choice);
            }
            section.rows.push_back(row);
        }
        view.sections.push_back(section);
    }

    std::vector<Key> changed = changes(actual);
    view.canApply = !changed.empty();
    view.applyReconnects = StreamSettingsRules::anyReconnects(changed, m_Draft, m_Global, stream);
    view.canSave = m_Draft != m_Saved;
    return view;
}

std::vector<Key> ForkStreamSettings::changes(const Profile& actual) const
{
    return StreamSettingsRules::toApply(m_Draft, m_Global, actual, m_Touched);
}

void ForkStreamSettings::setDraft(const Profile& draft)
{
    // What changed is chosen, for Apply
    for (Key key : StreamSettingsRules::differences(m_Draft, draft)) {
        m_Touched.insert(key);
    }
    m_Draft = draft;
    if (StreamSettingsRules::presetOf(draft) == StreamSettingsRules::Preset::Custom) {
        m_LastCustom = draft;
    }
}

void ForkStreamSettings::pick(int row, int choice)
{
    if (row < 0 || row > static_cast<int>(RowId::Trackpad) || choice < 0) {
        return;
    }
    RowId id = static_cast<RowId>(row);
    Key key = keyOf(row);
    Profile draft = m_Draft;
    // Chosen, even the value it has: Apply makes the stream have it (StreamSettingsRules::toApply())
    m_Touched.insert(key);
    if (choice == 0) {
        // Global; the aspect ratio row only picks sizes, so the resolution follows Settings again
        draft.erase(key);
        setDraft(draft);
        return;
    }
    std::vector<Option> list = options(id);
    if (choice - 1 >= static_cast<int>(list.size())) {
        return;
    }
    const Option& option = list[static_cast<size_t>(choice - 1)];
    if (id == RowId::Aspect) {
        // A ratio picks its size that fills the display, as the dialog does
        if (option.ratioKey == QStringLiteral("custom")) {
            return;
        }
        std::optional<int> size = fillingSize(option.ratioKey);
        if (!size) {
            return;
        }
        draft[Key::Resolution] = *size;
    }
    else {
        if (key == Key::Trackpad && option.value != ReconnectRules::k_TrackpadMacMouse &&
            !(option.value == ReconnectRules::k_TrackpadWindowsTouchpad ? m_Stream.touchpadSupported : m_Stream.macTrackpadSupported)) {
            // Greyed in the list: the PC's Apollo can't take it
            return;
        }
        draft[key] = option.value;
    }
    setDraft(draft);
}

void ForkStreamSettings::choosePreset(int preset)
{
    if (preset == 0) {
        setDraft(StreamSettingsRules::office());
    }
    else if (preset == 1) {
        setDraft(StreamSettingsRules::gaming());
    }
    else if (preset == 2 && !m_LastCustom.empty()) {
        setDraft(m_LastCustom);
    }
}

void ForkStreamSettings::reset()
{
    setDraft(Profile());
}

QString ForkStreamSettings::save()
{
    StreamProfiles::get()->saveProfile(m_HostUuid, m_AppName, toProfile(m_Draft));
    m_Saved = m_Draft;
    using StreamSettingsRules::Preset;
    Preset preset = StreamSettingsRules::presetOf(m_Draft);
    if (preset == Preset::None) {
        return tr("%1 follows Settings again").arg(m_AppName);
    }
    QString name = preset == Preset::Office ? tr("office profile") : preset == Preset::Gaming ? tr("gaming profile") : tr("custom profile");
    return tr("Saved %1 for %2").arg(name, m_AppName);
}
