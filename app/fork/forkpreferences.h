#pragma once

#include <QHash>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>

#include "forkkeymap.h"

// Settings added by this fork. Stored next to Moonlight's own settings under "fork/".
class ForkPreferences : public QObject
{
    Q_OBJECT

public:
    enum ModifierTarget {
        MT_NONE = ForkKeymap::TargetNone,
        MT_CTRL = ForkKeymap::TargetCtrl,
        MT_ALT = ForkKeymap::TargetAlt,
        MT_WIN = ForkKeymap::TargetWin,
    };
    Q_ENUM(ModifierTarget)

    enum ClipboardSyncMode {
        CSM_OFF,
        CSM_MANUAL,     // only with Ctrl+Option+Shift+U / G
        CSM_AUTOMATIC,  // also when the stream starts, gains and loses focus, and ends
    };
    Q_ENUM(ClipboardSyncMode)

    // Where the iMac's picture comes from in a multi-display stream (ForkDisplayRoute::Setting)
    enum ImacRoute {
        IR_AUTOMATIC,   // the faster of the two, measured at each launch
        IR_DIRECT,      // straight from the PC: Moonlight on the iMac streams it from Apollo
        IR_VIA_MAC,     // through this Mac: shown on DisplayExtend's display, which streams it on
    };
    Q_ENUM(ImacRoute)

    // The codec of the iMac's display's stream from the PC (ForkDisplayRoute::Codec)
    enum ImacCodec {
        IC_AUTOMATIC,   // straight from the PC: one the iMac decodes in hardware; through this Mac: the main stream's
        IC_H264,
        IC_HEVC,
        IC_AV1,
    };
    Q_ENUM(ImacCodec)

    // What the Command (GUI), Control and Option (Alt) keys send to the host
    Q_PROPERTY(int commandKeyTarget READ commandKeyTarget WRITE setCommandKeyTarget NOTIFY keyTargetsChanged)
    Q_PROPERTY(int controlKeyTarget READ controlKeyTarget WRITE setControlKeyTarget NOTIFY keyTargetsChanged)
    Q_PROPERTY(int optionKeyTarget READ optionKeyTarget WRITE setOptionKeyTarget NOTIFY keyTargetsChanged)

    // Left Option+M types µ on the PC, as right Option+M does (ForkKeymap::leftAltMicro())
    Q_PROPERTY(bool leftOptionMicro READ leftOptionMicro WRITE setLeftOptionMicro NOTIFY leftOptionMicroChanged)

    // Clipboard sync with Apollo hosts
    Q_PROPERTY(int clipboardSyncMode READ clipboardSyncMode WRITE setClipboardSyncMode NOTIFY clipboardSyncModeChanged)

    // Files copied in Finder or Explorer cross with the clipboard too (clipfiles.*, clipboardsync.cpp)
    Q_PROPERTY(bool clipboardFiles READ clipboardFiles WRITE setClipboardFiles NOTIFY clipboardFilesChanged)

    // The app name and stream stats beside the camera notch in fullscreen (macOS)
    Q_PROPERTY(bool notchBar READ notchBar WRITE setNotchBar NOTIFY notchBarChanged)

    // Tell hosts about the Mac screen a stream shows on, for Apollo's virtual display (clientdisplay.*)
    Q_PROPERTY(bool describeDisplay READ describeDisplay WRITE setDescribeDisplay NOTIFY describeDisplayChanged)

    // The HDR peak brightness in nits to tell hosts; 0 works it out from the screen
    Q_PROPERTY(int hdrPeakOverride READ hdrPeakOverride WRITE setHdrPeakOverride NOTIFY hdrPeakOverrideChanged)

    // "Desktop (multiple displays)": where the iMac's picture comes from when one of the Mac's
    // displays is DisplayExtend's (forkdisplayroute.*)
    Q_PROPERTY(int imacRoute READ imacRoute WRITE setImacRoute NOTIFY imacRouteChanged)

    // ...and the codec and bitrate of that display's stream from the PC, on either route; a bitrate
    // of 0 is automatic (ForkDisplayRoute::imacStream())
    Q_PROPERTY(int imacCodec READ imacCodec WRITE setImacCodec NOTIFY imacCodecChanged)
    Q_PROPERTY(int imacBitrateKbps READ imacBitrateKbps WRITE setImacBitrateKbps NOTIFY imacBitrateChanged)

    // This build, like "6.2.0-fork.ee5b3ba" (not a preference; shown in Settings)
    Q_PROPERTY(QString buildId READ buildId CONSTANT)

    // While system key capture is on, send every Mac shortcut to the host (screenshots included),
    // as Moonlight does, instead of only the groups chosen in Settings (forkmacshortcuts.*)
    Q_PROPERTY(bool macShortcutsAll READ macShortcutsAll WRITE setMacShortcutsAll NOTIFY macShortcutsChanged)

    // Whether this macOS lets LuzLunar choose shortcuts one group at a time
    Q_PROPERTY(bool macShortcutsSelectable READ macShortcutsSelectable CONSTANT)

    // While trackpad passthrough runs, also turn off the macOS gestures the event tap can't hold
    // back (Notification Center's edge swipe, three-finger drag) through System Settings' own code,
    // and turn them back on afterwards (forktrackpadgestures.*)
    Q_PROPERTY(bool trackpadPauseMacSettings READ trackpadPauseMacSettings WRITE setTrackpadPauseMacSettings NOTIFY trackpadPauseMacSettingsChanged)

    // Mac trackpad mode: how far Windows scrolls for the fingers' scrolling, in wheel units per
    // point (120 a notch), 0.25 to 3
    Q_PROPERTY(double trackpadScrollSpeed READ trackpadScrollSpeed WRITE setTrackpadScrollSpeed NOTIFY trackpadScrollSpeedChanged)

    // On LAN streams, have Apollo show this Mac's disk on the PC as a network drive (macdrive.*)
    Q_PROPERTY(bool macDrive READ macDrive WRITE setMacDrive NOTIFY macDriveChanged)

    // Lower the stream's bitrate while the network struggles, and raise it back (adaptivebitrate.*)
    Q_PROPERTY(bool adaptiveBitrate READ adaptiveBitrate WRITE setAdaptiveBitrate NOTIFY adaptiveBitrateChanged)

    // Draw the PC's pointer on this Mac, in remote desktop and Mac trackpad modes, with an Apollo
    // that lets it (forkcursor.*)
    Q_PROPERTY(bool drawPcPointer READ drawPcPointer WRITE setDrawPcPointer NOTIFY drawPcPointerChanged)

    static ForkPreferences* get();

    bool trackpadPauseMacSettings() const { return m_TrackpadPauseMacSettings; }
    void setTrackpadPauseMacSettings(bool pause);

    double trackpadScrollSpeed() const { return m_TrackpadScrollSpeed; }
    void setTrackpadScrollSpeed(double speed);

    bool macDrive() const { return m_MacDrive; }
    void setMacDrive(bool enabled);

    bool adaptiveBitrate() const { return m_AdaptiveBitrate; }
    void setAdaptiveBitrate(bool enabled);

    bool drawPcPointer() const { return m_DrawPcPointer; }
    void setDrawPcPointer(bool enabled);

    // What the Mac drive needs from macOS, for Settings › This Mac: { "fileSharing": bool,
    // "windowsSharing": "on" | "off" | "unknown", "diskShare": the startup disk's share or "",
    // "admin": bool, "volumeName", "userName", "passwordSaved": bool, "last": the last LAN
    // stream's outcome or "" }. Reading it never asks the user anything.
    Q_INVOKABLE QVariantMap macDriveSetup() const;

    // Keeps the account's password in the login keychain, if it opens the account
    Q_INVOKABLE bool saveMacDrivePassword(const QString& password);
    Q_INVOKABLE void forgetMacDrivePassword();

    // System Settings › General › Sharing
    Q_INVOKABLE void openSharingSettings();

    // Whether macOS lets LuzLunar hold back its trackpad gestures (Privacy & Security › Accessibility)
    Q_INVOKABLE bool accessibilityTrusted() const;

    // Asks macOS for that permission and opens its page in System Settings
    Q_INVOKABLE void requestAccessibility();

    QString buildId() const;

    // The shortcut groups for Settings, in order: [{ "key": ..., "label": ... }]
    Q_INVOKABLE QVariantList macShortcutGroups() const;

    // Whether a group of Mac shortcuts goes to the host while capture is on
    Q_INVOKABLE bool macShortcutToHost(const QString& key) const;
    Q_INVOKABLE void setMacShortcutToHost(const QString& key, bool toHost);

    bool macShortcutsAll() const { return m_MacShortcutsAll; }
    void setMacShortcutsAll(bool all);

    bool macShortcutsSelectable() const;

    int clipboardSyncMode() const { return m_ClipboardSyncMode; }
    void setClipboardSyncMode(int mode);

    bool clipboardFiles() const { return m_ClipboardFiles; }
    void setClipboardFiles(bool enabled);

    bool notchBar() const { return m_NotchBar; }
    void setNotchBar(bool enabled);

    // The notch bar's stream stats beside the notch, or only their icon: Stream Control Center's
    // Notch Stats switch, during a stream. No signal, as QML isn't running then.
    bool notchBarStats() const { return m_NotchBarStats; }
    void setNotchBarStats(bool shown);

    // The streams that have shown how to reach the notch bar while the PC has the mouse (⌃⌥⇧N); the
    // bar stops after a few, and once ⌃⌥⇧N has been used. No signal, as QML isn't running then.
    int notchBarHints() const { return m_NotchBarHints; }
    void setNotchBarHints(int count);

    bool describeDisplay() const { return m_DescribeDisplay; }
    void setDescribeDisplay(bool enabled);

    bool leftOptionMicro() const { return m_LeftOptionMicro; }
    void setLeftOptionMicro(bool enabled);

    int hdrPeakOverride() const { return m_HdrPeakOverride; }
    void setHdrPeakOverride(int nits);

    int imacRoute() const { return m_ImacRoute; }
    void setImacRoute(int route);

    int imacCodec() const { return m_ImacCodec; }
    void setImacCodec(int codec);

    int imacBitrateKbps() const { return m_ImacBitrateKbps; }
    void setImacBitrateKbps(int kbps);

    int commandKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalGui]; }
    int controlKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalCtrl]; }
    int optionKeyTarget() const { return m_KeyMap.target[ForkKeymap::PhysicalAlt]; }

    void setCommandKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalGui, target); }
    void setControlKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalCtrl, target); }
    void setOptionKeyTarget(int target) { setKeyTarget(ForkKeymap::PhysicalAlt, target); }

    const ForkKeymap::Map& keyMap() const { return m_KeyMap; }

signals:
    void keyTargetsChanged();
    void clipboardSyncModeChanged();
    void clipboardFilesChanged();
    void notchBarChanged();
    void describeDisplayChanged();
    void leftOptionMicroChanged();
    void hdrPeakOverrideChanged();
    void imacRouteChanged();
    void imacCodecChanged();
    void imacBitrateChanged();
    void macShortcutsChanged();
    void trackpadPauseMacSettingsChanged();
    void trackpadScrollSpeedChanged();
    void macDriveChanged();
    void adaptiveBitrateChanged();
    void drawPcPointerChanged();

private:
    explicit ForkPreferences(QObject* parent = nullptr);

    void setKeyTarget(ForkKeymap::Physical key, int target);

    ForkKeymap::Map m_KeyMap;
    int m_ClipboardSyncMode;
    bool m_ClipboardFiles;
    bool m_NotchBar;
    bool m_NotchBarStats;
    int m_NotchBarHints;
    bool m_DescribeDisplay;
    bool m_LeftOptionMicro;
    int m_HdrPeakOverride;
    int m_ImacRoute;
    int m_ImacCodec;
    int m_ImacBitrateKbps;
    bool m_MacShortcutsAll;
    bool m_TrackpadPauseMacSettings;
    double m_TrackpadScrollSpeed;
    bool m_MacDrive;
    bool m_AdaptiveBitrate;
    bool m_DrawPcPointer;
    // Saved choices by group key; groups not in it use the table's default
    QHash<QString, bool> m_MacShortcutsToHost;
};
