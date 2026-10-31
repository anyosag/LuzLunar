#include "forkpreferences.h"

#include <algorithm>
#include <string>

#include <QCoreApplication>
#include <QDesktopServices>
#include <QSettings>
#include <QUrl>
#include <QVariantMap>

#include "forkdisplayroute.h"
#include "forkmacshortcuts.h"
#include "mac/camera_mac.h"
#include "mac/gesturesuppressor_mac.h"
#include "mac/macdrivesetup.h"
#include "mac/macintegration.h"
#include "mac/mic_mac.h"

#define SER_KEYTARGETS "fork/keyTargets"
#define SER_CLIPBOARDSYNC "fork/clipboardSync"
#define SER_NOTCHBAR "fork/notchBar"
#define SER_NOTCHBARSTATS "fork/notchBarStats"
#define SER_NOTCHBARHINTS "fork/notchBarHints"
#define SER_DESCRIBEDISPLAY "fork/describeDisplay"
#define SER_HDRPEAKOVERRIDE "fork/hdrPeakOverride"
#define SER_IMACROUTE "fork/imacRoute"
#define SER_IMACCODEC "fork/imacCodec"
#define SER_IMACBITRATE "fork/imacBitrateKbps"
#define SER_MACSHORTCUTS "fork/macShortcuts"
#define SER_MACSHORTCUTSALL "fork/macShortcutsAll"
#define SER_TRACKPADPAUSEMACSETTINGS "fork/trackpadPauseMacSettings"
#define SER_CLIPBOARDFILES "fork/clipboardFiles"
#define SER_TRACKPADSCROLLSPEED "fork/trackpadScrollSpeed"
#define SER_MACDRIVE "fork/macDrive"
#define SER_MACDRIVELAST "fork/macDriveLast"
#define SER_ADAPTIVEBITRATE "fork/adaptiveBitrate"
#define SER_DRAWPCPOINTER "fork/drawPcPointer"
#define SER_MACMICROPHONE "fork/macMicrophone"
#define SER_MACMICROPHONEDEVICE "fork/macMicrophoneDevice"
#define SER_CAMERA "fork/camera"
#define SER_CAMERADEVICE "fork/cameraDevice"

// Brighter than any display sold; HDR10 tops out at 10,000 nits
#define MAX_HDR_PEAK 10000

// From a quarter of the fingers' scrolling to three times it
#define MIN_TRACKPAD_SCROLL_SPEED 0.25
#define MAX_TRACKPAD_SCROLL_SPEED 3.0

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

// This build's ID, generated in the build folder by fork.pri
#include "forkbuildinfo.h"

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
      m_ClipboardFiles(true),
      m_NotchBar(true),
      m_NotchBarStats(true),
      m_NotchBarHints(0),
      m_DescribeDisplay(true),
      m_HdrPeakOverride(0),
      m_ImacRoute(IR_AUTOMATIC),
      m_ImacCodec(IC_AUTOMATIC),
      m_ImacBitrateKbps(0),
      m_MacShortcutsAll(false),
      m_TrackpadPauseMacSettings(true),
      m_TrackpadScrollSpeed(1.0),
      m_MacDrive(false),
      m_AdaptiveBitrate(true),
      m_DrawPcPointer(true),
      m_MacMicrophone(true),
      m_Camera(true)
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

    m_ClipboardFiles = settings.value(SER_CLIPBOARDFILES, m_ClipboardFiles).toBool();
    m_NotchBar = settings.value(SER_NOTCHBAR, m_NotchBar).toBool();
    m_NotchBarStats = settings.value(SER_NOTCHBARSTATS, m_NotchBarStats).toBool();
    m_NotchBarHints = settings.value(SER_NOTCHBARHINTS, m_NotchBarHints).toInt();
    m_DescribeDisplay = settings.value(SER_DESCRIBEDISPLAY, m_DescribeDisplay).toBool();

    int peak = settings.value(SER_HDRPEAKOVERRIDE, m_HdrPeakOverride).toInt();
    if (peak >= 0 && peak <= MAX_HDR_PEAK) {
        m_HdrPeakOverride = peak;
    }

    m_MacShortcutsAll = settings.value(SER_MACSHORTCUTSALL, m_MacShortcutsAll).toBool();
    int route = settings.value(SER_IMACROUTE, m_ImacRoute).toInt();
    if (route >= IR_AUTOMATIC && route <= IR_VIA_MAC) {
        m_ImacRoute = route;
    }
    int codec = settings.value(SER_IMACCODEC, m_ImacCodec).toInt();
    if (codec >= IC_AUTOMATIC && codec <= IC_AV1) {
        m_ImacCodec = codec;
    }
    int imacKbps = settings.value(SER_IMACBITRATE, m_ImacBitrateKbps).toInt();
    if (imacKbps == 0 || (imacKbps >= ForkDisplayRoute::k_ImacMinBitrateKbps && imacKbps <= ForkDisplayRoute::k_ImacMaxBitrateKbps)) {
        m_ImacBitrateKbps = imacKbps;
    }
    m_TrackpadPauseMacSettings = settings.value(SER_TRACKPADPAUSEMACSETTINGS, m_TrackpadPauseMacSettings).toBool();
    double scrollSpeed = settings.value(SER_TRACKPADSCROLLSPEED, m_TrackpadScrollSpeed).toDouble();
    if (scrollSpeed >= MIN_TRACKPAD_SCROLL_SPEED && scrollSpeed <= MAX_TRACKPAD_SCROLL_SPEED) {
        m_TrackpadScrollSpeed = scrollSpeed;
    }
    m_MacDrive = settings.value(SER_MACDRIVE, m_MacDrive).toBool();
    m_AdaptiveBitrate = settings.value(SER_ADAPTIVEBITRATE, m_AdaptiveBitrate).toBool();
    m_DrawPcPointer = settings.value(SER_DRAWPCPOINTER, m_DrawPcPointer).toBool();
    m_MacMicrophone = settings.value(SER_MACMICROPHONE, m_MacMicrophone).toBool();
    m_MacMicrophoneDevice = settings.value(SER_MACMICROPHONEDEVICE, m_MacMicrophoneDevice).toString();
    m_Camera = settings.value(SER_CAMERA, m_Camera).toBool();
    m_CameraDevice = settings.value(SER_CAMERADEVICE, m_CameraDevice).toString();
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

void ForkPreferences::setClipboardFiles(bool enabled)
{
    if (enabled == m_ClipboardFiles) {
        return;
    }

    m_ClipboardFiles = enabled;
    QSettings().setValue(SER_CLIPBOARDFILES, enabled);
    emit clipboardFilesChanged();
}

void ForkPreferences::setTrackpadScrollSpeed(double speed)
{
    if (!(speed >= MIN_TRACKPAD_SCROLL_SPEED && speed <= MAX_TRACKPAD_SCROLL_SPEED) || speed == m_TrackpadScrollSpeed) {
        return;
    }

    m_TrackpadScrollSpeed = speed;
    QSettings().setValue(SER_TRACKPADSCROLLSPEED, speed);
    emit trackpadScrollSpeedChanged();
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

void ForkPreferences::setImacRoute(int route)
{
    if (route < IR_AUTOMATIC || route > IR_VIA_MAC || route == m_ImacRoute) {
        return;
    }

    m_ImacRoute = route;
    QSettings().setValue(SER_IMACROUTE, route);
    emit imacRouteChanged();
}

void ForkPreferences::setImacCodec(int codec)
{
    if (codec < IC_AUTOMATIC || codec > IC_AV1 || codec == m_ImacCodec) {
        return;
    }

    m_ImacCodec = codec;
    QSettings().setValue(SER_IMACCODEC, codec);
    emit imacCodecChanged();
}

void ForkPreferences::setImacBitrateKbps(int kbps)
{
    // 0 is automatic; anything else is kept in the slider's range
    if (kbps != 0) {
        kbps = std::clamp(kbps, ForkDisplayRoute::k_ImacMinBitrateKbps, ForkDisplayRoute::k_ImacMaxBitrateKbps);
    }
    if (kbps == m_ImacBitrateKbps) {
        return;
    }

    m_ImacBitrateKbps = kbps;
    QSettings().setValue(SER_IMACBITRATE, kbps);
    emit imacBitrateChanged();
}

void ForkPreferences::setMacDrive(bool enabled)
{
    if (enabled == m_MacDrive) {
        return;
    }

    m_MacDrive = enabled;
    QSettings().setValue(SER_MACDRIVE, enabled);
    emit macDriveChanged();
}

void ForkPreferences::setAdaptiveBitrate(bool enabled)
{
    if (enabled == m_AdaptiveBitrate) {
        return;
    }

    m_AdaptiveBitrate = enabled;
    QSettings().setValue(SER_ADAPTIVEBITRATE, enabled);
    emit adaptiveBitrateChanged();
}

void ForkPreferences::setDrawPcPointer(bool enabled)
{
    if (enabled == m_DrawPcPointer) {
        return;
    }

    m_DrawPcPointer = enabled;
    QSettings().setValue(SER_DRAWPCPOINTER, enabled);
    emit drawPcPointerChanged();
}

void ForkPreferences::setMacMicrophone(bool enabled)
{
    if (enabled == m_MacMicrophone) {
        return;
    }

    m_MacMicrophone = enabled;
    QSettings().setValue(SER_MACMICROPHONE, enabled);
    emit macMicrophoneChanged();
}

void ForkPreferences::setMacMicrophoneDevice(const QString& uid)
{
    if (uid == m_MacMicrophoneDevice) {
        return;
    }

    m_MacMicrophoneDevice = uid;
    QSettings().setValue(SER_MACMICROPHONEDEVICE, uid);
    emit macMicrophoneDeviceChanged();
}

QVariantList ForkPreferences::macMicrophones() const
{
    std::vector<MicRules::Input> inputs = ForkMicMac::inputs();
    std::stable_sort(inputs.begin(), inputs.end(), [](const MicRules::Input& a, const MicRules::Input& b) {
        return a.builtIn && !b.builtIn;
    });
    QVariantList list;
    for (const MicRules::Input& input : inputs) {
        QVariantMap entry;
        entry.insert(QStringLiteral("uid"), QString::fromStdString(input.uid));
        entry.insert(QStringLiteral("name"), QString::fromStdString(input.name));
        entry.insert(QStringLiteral("builtIn"), input.builtIn);
        list.append(entry);
    }
    return list;
}

void ForkPreferences::setCamera(bool enabled)
{
    if (enabled == m_Camera) {
        return;
    }

    m_Camera = enabled;
    QSettings().setValue(SER_CAMERA, enabled);
    emit cameraChanged();
}

void ForkPreferences::setCameraDevice(const QString& id)
{
    if (id == m_CameraDevice) {
        return;
    }

    m_CameraDevice = id;
    QSettings().setValue(SER_CAMERADEVICE, id);
    emit cameraDeviceChanged();
}

QVariantList ForkPreferences::cameraDevices() const
{
    QVariantList list;
    for (const MacCamera::Device& device : MacCamera::devices()) {
        QVariantMap entry;
        entry.insert(QStringLiteral("id"), QString::fromStdString(device.id));
        entry.insert(QStringLiteral("name"), QString::fromStdString(device.name));
        list.append(entry);
    }
    return list;
}

QString ForkPreferences::macMicrophoneAccess() const
{
    switch (ForkMicMac::access()) {
    case MicRules::Access::Granted:
        return QStringLiteral("granted");
    case MicRules::Access::Denied:
        return QStringLiteral("denied");
    default:
        return QStringLiteral("undetermined");
    }
}

void ForkPreferences::openMicrophoneSettings()
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")));
}

QString ForkPreferences::cameraAccess() const
{
    switch (MacCamera::access()) {
    case MacCamera::Access::Allowed:
        return QStringLiteral("allowed");
    case MacCamera::Access::Denied:
        return QStringLiteral("denied");
    case MacCamera::Access::Undetermined:
        break;
    }
    return QStringLiteral("undetermined");
}

void ForkPreferences::openCameraSettings()
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")));
}

QVariantMap ForkPreferences::macDriveSetup() const
{
    QVariantMap setup;
    MacDriveSetup::WindowsSharing sharing = MacDriveSetup::windowsSharing();
    setup.insert(QStringLiteral("fileSharing"), MacDriveSetup::fileSharingOn());
    setup.insert(QStringLiteral("windowsSharing"), sharing == MacDriveSetup::WindowsSharing::On    ? QStringLiteral("on")
                                                   : sharing == MacDriveSetup::WindowsSharing::Off ? QStringLiteral("off")
                                                                                                   : QStringLiteral("unknown"));
    setup.insert(QStringLiteral("diskShare"), QString::fromStdString(MacDriveSetup::diskShareName()));
    setup.insert(QStringLiteral("admin"), MacDriveSetup::isAdmin());
    setup.insert(QStringLiteral("volumeName"), QString::fromStdString(MacDriveSetup::startupVolumeName()));
    setup.insert(QStringLiteral("userName"), QString::fromStdString(MacDriveSetup::userName()));
    setup.insert(QStringLiteral("passwordSaved"), MacDriveSetup::hasPassword());
    setup.insert(QStringLiteral("last"), QSettings().value(SER_MACDRIVELAST).toString());
    return setup;
}

bool ForkPreferences::saveMacDrivePassword(const QString& password)
{
    std::string secret = password.toStdString();
    bool saved = MacDriveSetup::verifyPassword(secret) && MacDriveSetup::savePassword(secret);
    std::fill(secret.begin(), secret.end(), '\0');
    return saved;
}

void ForkPreferences::forgetMacDrivePassword()
{
    MacDriveSetup::forgetPassword();
}

void ForkPreferences::openSharingSettings()
{
    MacDriveSetup::openSharingSettings();
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

void ForkPreferences::setNotchBarStats(bool shown)
{
    if (shown == m_NotchBarStats) {
        return;
    }

    m_NotchBarStats = shown;
    QSettings().setValue(SER_NOTCHBARSTATS, shown);
}

void ForkPreferences::setNotchBarHints(int count)
{
    if (count == m_NotchBarHints) {
        return;
    }

    m_NotchBarHints = count;
    QSettings().setValue(SER_NOTCHBARHINTS, count);
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
