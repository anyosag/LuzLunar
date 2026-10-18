#include "forkpreferences.h"

#include <QCoreApplication>
#include <QSettings>
#include <QVariantMap>

#include "forkmacshortcuts.h"
#include "mac/gesturesuppressor_mac.h"
#include "mac/macintegration.h"

#define SER_KEYTARGETS "fork/keyTargets"
#define SER_CLIPBOARDSYNC "fork/clipboardSync"
#define SER_NOTCHBAR "fork/notchBar"
#define SER_DESCRIBEDISPLAY "fork/describeDisplay"
#define SER_HDRPEAKOVERRIDE "fork/hdrPeakOverride"
#define SER_MACSHORTCUTS "fork/macShortcuts"
#define SER_MACSHORTCUTSALL "fork/macShortcutsAll"
#define SER_TRACKPADPAUSEMACSETTINGS "fork/trackpadPauseMacSettings"

// Brighter than any display sold; HDR10 tops out at 10,000 nits
#define MAX_HDR_PEAK 10000

namespace
{
    // QSettings keys, indexed by ForkKeymap::Physical
    const char* const k_KeyTargetNames[] = { "control", "option", "command" };

    ForkKeymap::Map defaultKeyMap()
    {
#ifdef Q_OS_DARWIN
        // Make a Mac keyboard behave like a Windows one: Command does what Ctrl does on Windows,
        // and Control (the key in the Windows key's position) acts as the Windows key.
        return ForkKeymap::Map { { ForkKeymap::TargetWin, ForkKeymap::TargetAlt, ForkKeymap::TargetCtrl } };
#else
        return ForkKeymap::identity();
#endif
    }

    bool isValidTarget(int target)
    {
        return target >= ForkKeymap::TargetNone && target <= ForkKeymap::TargetWin;
    }
}

ForkPreferences* ForkPreferences::get()
{
    static ForkPreferences* s_Instance = new ForkPreferences();
    return s_Instance;
}

QString ForkPreferences::buildId() const
{
#ifdef FORK_BUILD_ID
    return QStringLiteral(FORK_BUILD_ID);
#else
    return QStringLiteral(VERSION_STR);
#endif
}

ForkPreferences::ForkPreferences(QObject* parent)
    : QObject(parent),
      m_KeyMap(defaultKeyMap()),
      m_ClipboardSyncMode(CSM_MANUAL),
      m_NotchBar(true),
      m_DescribeDisplay(true),
      m_HdrPeakOverride(0),
      m_MacShortcutsAll(false),
      m_TrackpadPauseMacSettings(true)
{
    QSettings settings;

    settings.beginGroup(SER_KEYTARGETS);
    for (int key = ForkKeymap::PhysicalCtrl; key <= ForkKeymap::PhysicalGui; key++) {
        int target = settings.value(k_KeyTargetNames[key], m_KeyMap.target[key]).toInt();
        if (isValidTarget(target)) {
            m_KeyMap.target[key] = static_cast<ForkKeymap::Target>(target);
        }
    }
    settings.endGroup();

    if (!settings.contains(SER_CLIPBOARDSYNC)) {
        // New installs only sync with the shortcuts. Automatic was the default before, so installs that
        // already have hosts keep it; the choice is saved so pairing a host later doesn't change it.
        bool existingInstall = settings.contains("hosts/size") || settings.contains("hostsbackup/size");
        settings.setValue(SER_CLIPBOARDSYNC, existingInstall ? CSM_AUTOMATIC : CSM_MANUAL);
    }
    int mode = settings.value(SER_CLIPBOARDSYNC, m_ClipboardSyncMode).toInt();
    if (mode >= CSM_OFF && mode <= CSM_AUTOMATIC) {
        m_ClipboardSyncMode = mode;
    }

    m_NotchBar = settings.value(SER_NOTCHBAR, m_NotchBar).toBool();
    m_DescribeDisplay = settings.value(SER_DESCRIBEDISPLAY, m_DescribeDisplay).toBool();

    int peak = settings.value(SER_HDRPEAKOVERRIDE, m_HdrPeakOverride).toInt();
    if (peak >= 0 && peak <= MAX_HDR_PEAK) {
        m_HdrPeakOverride = peak;
    }

    m_MacShortcutsAll = settings.value(SER_MACSHORTCUTSALL, m_MacShortcutsAll).toBool();
    m_TrackpadPauseMacSettings = settings.value(SER_TRACKPADPAUSEMACSETTINGS, m_TrackpadPauseMacSettings).toBool();
    settings.beginGroup(SER_MACSHORTCUTS);
    for (const ForkMacShortcuts::Group& group : ForkMacShortcuts::groups()) {
        QString key = QString::fromUtf8(group.key);
        if (settings.contains(key)) {
            m_MacShortcutsToHost.insert(key, settings.value(key).toBool());
        }
    }
    settings.endGroup();
}

QVariantList ForkPreferences::macShortcutGroups() const
{
    QVariantList list;
    for (const ForkMacShortcuts::Group& group : ForkMacShortcuts::groups()) {
        QVariantMap entry;
        entry.insert(QStringLiteral("key"), QString::fromUtf8(group.key));
        entry.insert(QStringLiteral("label"), QCoreApplication::translate("ForkMacShortcuts", group.label));
        list.append(entry);
    }
    return list;
}

bool ForkPreferences::macShortcutToHost(const QString& key) const
{
    const ForkMacShortcuts::Group* group = ForkMacShortcuts::findGroup(key.toStdString());
    if (group == nullptr) {
        return false;
    }
    return m_MacShortcutsToHost.value(key, group->defaultToHost);
}

void ForkPreferences::setMacShortcutToHost(const QString& key, bool toHost)
{
    if (ForkMacShortcuts::findGroup(key.toStdString()) == nullptr || macShortcutToHost(key) == toHost) {
        return;
    }

    m_MacShortcutsToHost.insert(key, toHost);

    QSettings settings;
    settings.beginGroup(SER_MACSHORTCUTS);
    settings.setValue(key, toHost);
    settings.endGroup();

    emit macShortcutsChanged();
}

void ForkPreferences::setMacShortcutsAll(bool all)
{
    if (all == m_MacShortcutsAll) {
        return;
    }

    m_MacShortcutsAll = all;
    QSettings().setValue(SER_MACSHORTCUTSALL, all);
    emit macShortcutsChanged();
}

bool ForkPreferences::macShortcutsSelectable() const
{
    return MacIntegration::symbolicHotKeysAvailable();
}

void ForkPreferences::setTrackpadPauseMacSettings(bool pause)
{
    if (pause == m_TrackpadPauseMacSettings) {
        return;
    }

    m_TrackpadPauseMacSettings = pause;
    QSettings().setValue(SER_TRACKPADPAUSEMACSETTINGS, pause);
    emit trackpadPauseMacSettingsChanged();
}

bool ForkPreferences::accessibilityTrusted() const
{
    return ForkGestureSuppressor::accessibilityTrusted();
}

void ForkPreferences::requestAccessibility()
{
    ForkGestureSuppressor::requestAccessibility();
}

void ForkPreferences::setDescribeDisplay(bool enabled)
{
    if (enabled == m_DescribeDisplay) {
        return;
    }

    m_DescribeDisplay = enabled;
    QSettings().setValue(SER_DESCRIBEDISPLAY, enabled);
    emit describeDisplayChanged();
}

void ForkPreferences::setHdrPeakOverride(int nits)
{
    if (nits < 0 || nits > MAX_HDR_PEAK || nits == m_HdrPeakOverride) {
        return;
    }

    m_HdrPeakOverride = nits;
    QSettings().setValue(SER_HDRPEAKOVERRIDE, nits);
    emit hdrPeakOverrideChanged();
}

void ForkPreferences::setNotchBar(bool enabled)
{
    if (enabled == m_NotchBar) {
        return;
    }

    m_NotchBar = enabled;
    QSettings().setValue(SER_NOTCHBAR, enabled);
    emit notchBarChanged();
}

void ForkPreferences::setClipboardSyncMode(int mode)
{
    if (mode < CSM_OFF || mode > CSM_AUTOMATIC || mode == m_ClipboardSyncMode) {
        return;
    }

    m_ClipboardSyncMode = mode;
    QSettings().setValue(SER_CLIPBOARDSYNC, mode);
    emit clipboardSyncModeChanged();
}

void ForkPreferences::setKeyTarget(ForkKeymap::Physical key, int target)
{
    if (!isValidTarget(target) || m_KeyMap.target[key] == target) {
        return;
    }

    m_KeyMap.target[key] = static_cast<ForkKeymap::Target>(target);

    QSettings settings;
    settings.beginGroup(SER_KEYTARGETS);
    settings.setValue(k_KeyTargetNames[key], target);
    settings.endGroup();

    emit keyTargetsChanged();
}
