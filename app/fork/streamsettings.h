#pragma once

#include <optional>
#include <vector>

#include <QString>

#include "streamsettingsrules.h"

// [fork] The notch bar's Stream Settings for an app, during its stream: a draft of the app's stream
// profile over Settings, as StreamProfileDialog.qml edits it, which the stream can apply now and the
// next stream can start with. One per stream with the bar (ForkStreamExtensions), main thread.
//
// Three profiles: the one saved for the app; the baseline, what this stream applied (the saved one
// it started with, or what a reconnect carried over); and the draft, the baseline again each time
// the panel opens. Apply takes what the draft changed from the baseline; Save for Next Time saves
// the draft.
class ForkStreamSettings
{
public:
    // One choice of a row's list
    struct Choice {
        QString text;
        bool checked = false;
        bool reconnects = false;    // ↻: this choice takes a reconnect where the row's others don't
        bool separatorAfter = false;
    };

    struct Row {
        QString label;
        QString value;              // the value it has in the draft, as the row's capsule shows it
        QString accessibility;      // "Frame rate: 120 FPS, set for this app"
        bool set = false;           // set for this app, rather than following Settings: a gold dot
        bool reconnects = false;    // ↻ by the label: the row's value takes a reconnect
        std::vector<Choice> choices;
    };

    struct Section {
        QString title;
        std::vector<Row> rows;
    };

    struct View {
        QString title;              // "Stream Settings for Desktop"
        QString subtitle;           // "GAMING-PC · Office profile"
        int preset = -1;            // the lit card: 0 Office, 1 Gaming, 2 Custom; -1 for none
        QString countText;          // "2 settings are set for Desktop. The rest follow Settings."
        std::vector<Section> sections;  // rows numbered across them, as pick() takes them
        bool canApply = false;      // the draft changed what the stream applied
        bool applyReconnects = false;
        bool canSave = false;       // the draft isn't the saved profile
    };

    // carriedBaseline: what the stream before a reconnect applied, as ReconnectRules::Choices
    // carries it; without one, the profile saved for the app
    ForkStreamSettings(const QString& hostUuid, const QString& hostName, const QString& appName,
                       const std::optional<std::map<int, int>>& carriedBaseline);

    // The panel's contents; open starts the draft from the baseline again
    View view(const StreamSettingsRules::Stream& stream, bool open);

    // A row's choice, rows numbered across the sections and choice 0 being Global
    void pick(int row, int choice);
    // A preset card: 0 Office, 1 Gaming, 2 the last custom settings
    void choosePreset(int preset);
    // Reset to Global: every row follows Settings, in the draft
    void reset();

    const StreamSettingsRules::Profile& draft() const { return m_Draft; }
    const StreamSettingsRules::Profile& global() const { return m_Global; }
    const StreamSettingsRules::Profile& baseline() const { return m_Baseline; }

    // What Apply takes: the settings the draft changed from what the stream applied
    std::vector<StreamSettingsRules::Key> changes() const;
    // The stream applied the draft
    void applied() { m_Baseline = m_Draft; }
    // Save for Next Time: the draft becomes the app's profile; its name for a toast
    QString save();

    static std::map<int, int> pack(const StreamSettingsRules::Profile& profile);
    static StreamSettingsRules::Profile unpack(const std::map<int, int>& packed);

private:
    // A row's options, after Global
    struct Option {
        QString text;
        QString shortText;          // in the capsule, when the list's is longer
        int value = 0;
        QString ratioKey;           // the aspect ratio row's, which picks a resolution
    };

    enum class RowId { Aspect, Resolution, Fps, Hdr, Codec, Yuv444, Bitrate, Fill, Vsync, Pacing, Mouse, Trackpad };

    std::vector<Option> options(RowId row) const;
    QString valueText(RowId row, const StreamSettingsRules::Profile& profile) const;
    QString effectiveRatioKey(const StreamSettingsRules::Profile& profile) const;
    std::optional<int> fillingSize(const QString& ratioKey) const;
    void setDraft(const StreamSettingsRules::Profile& draft);

    QString m_HostUuid;
    QString m_HostName;
    QString m_AppName;
    int m_Display;
    StreamSettingsRules::Profile m_Global;
    StreamSettingsRules::Profile m_Saved;
    StreamSettingsRules::Profile m_Baseline;
    StreamSettingsRules::Profile m_Draft;
    StreamSettingsRules::Profile m_LastCustom;  // the Custom card's: the last settings that weren't a preset
};
