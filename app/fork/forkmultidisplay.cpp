#include "forkmultidisplay.h"

#include <QMutex>
#include <QMutexLocker>
#include <QRandomGenerator>
#include <QReadLocker>

#include <condition_variable>
#include <mutex>
#include <thread>

#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "clientdisplay.h"
#include "clienthardware.h"
#include "forkdisplayextend.h"
#include "forkpreferences.h"
#include "settings/streamingpreferences.h"
#include "SDL_compat.h"

#ifdef Q_OS_DARWIN
#include <ApplicationServices/ApplicationServices.h>
#include <cmath>
#endif

namespace ForkMultiDisplay
{

namespace
{
    enum class Role { None, Main, Helper };

    // The route probes' result, filled in by their thread
    struct Probes {
        std::mutex lock;
        std::condition_variable changed;
        bool done = false;
        ForkDisplayRoute::Facts facts;
    };

    QMutex s_Lock;
    Role s_Role = Role::None;
    std::shared_ptr<const Group> s_Group;
    std::shared_ptr<Probes> s_Probes;
    uint32_t s_Target = 0;
    QString s_HelperGroupId;
    int s_HelperSlot = 0;

    // Connects each probe times; the iMac's go through DisplayExtend's Host
    constexpr int k_ProbeConnects = 10;
    constexpr int k_ProbeConnectTimeoutMs = 1000;

    QString newGroupId()
    {
        return QString::number(QRandomGenerator::global()->generate64(), 16).rightJustified(16, '0');
    }

    void logPlan(const Group& group)
    {
        QStringList parts;
        for (const ForkDisplayGroup::Slot& slot : group.plan.slotList) {
            parts << QString("slot %1 %2 %3x%4 %5 fps %6 kbps at %7,%8%9%10")
                     .arg(slot.slot)
                     .arg(QString::fromStdString(slot.name))
                     .arg(slot.width).arg(slot.height).arg(slot.fps).arg(slot.bitrateKbps)
                     .arg(slot.x).arg(slot.y)
                     .arg(slot.hdr ? " HDR" : "")
                     .arg(slot.external ? " (DisplayExtend's)" : "");
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Display group %s for \"%s\": %s",
                    qPrintable(QString::fromStdString(group.plan.id)), qPrintable(group.appName),
                    qPrintable(parts.join("; ")));
    }

    // DisplayExtend's status and both connects to the PC, on a thread of their own: the iMac's
    // probe takes a second or so, and the stream is still connecting meanwhile
    void startProbes(const std::shared_ptr<Probes>& probes, const QStringList& pcAddresses, uint16_t httpsPort,
                     const QString& macAddress, const QString& hostUuid)
    {
        std::thread([probes, pcAddresses, httpsPort, macAddress, hostUuid]() {
            ForkDisplayRoute::Facts facts;

            std::thread mac([&facts, macAddress, httpsPort]() {
                facts.macToPc = ForkRouteProbe::tcpConnects(macAddress, httpsPort, k_ProbeConnects, k_ProbeConnectTimeoutMs);
            });

            if (ForkDisplayExtend::available()) {
                ForkDisplayExtend bridge;
                if (bridge.open(1000)) {
                    ForkDisplayExtend::Status status = bridge.status(2000);
                    facts.bridge = status.ok;
                    facts.imacConnected = status.imacConnected;
                    facts.directSupported = status.directSupported;
                    facts.moonlightVerified = status.moonlightVerified;
                    facts.paired = status.pairedHostIds.contains(hostUuid, Qt::CaseInsensitive);
                    facts.displayExtendP50Ms = status.p50Ms;
                    facts.displayExtendFrames = status.frames;
                    if (status.hz > 0) {
                        facts.virtualRefreshHz = status.hz;
                    }

                    if (status.ok && status.imacConnected && status.directSupported) {
                        facts.imacToPc = bridge.probe(pcAddresses, httpsPort, k_ProbeConnects,
                                                      (k_ProbeConnects + 1) * k_ProbeConnectTimeoutMs * pcAddresses.size() + 2000);
                    }
                }
            }

            mac.join();

            std::lock_guard<std::mutex> lock(probes->lock);
            probes->facts = facts;
            probes->done = true;
            probes->changed.notify_all();
        }).detach();
    }
}

bool isGroupApp(NvComputer* computer, const NvApp& app)
{
    QReadLocker lock(&computer->lock);
    return computer->forkDisplayGroupAppId != 0 && app.id == computer->forkDisplayGroupAppId;
}

std::vector<ForkDisplayGroup::MacDisplay> macDisplays()
{
    std::vector<ForkDisplayGroup::MacDisplay> displays;
    int peakOverride = ForkPreferences::get()->hdrPeakOverride();

    for (const ClientHardware::Display& display : ClientHardware::get()->info().displays) {
        if (display.isMirror) {
            continue;
        }

        const ForkHwRules::Display& rules = display.rules;
        ForkDisplayGroup::MacDisplay mac;
        mac.id = display.displayId;
        mac.x = display.originX;
        mac.y = display.originY;
        mac.pointWidth = display.pointWidth;
        mac.pointHeight = display.pointHeight;
        // Below the notch on a notched display; the panel elsewhere
        mac.width = rules.safeWidth > 0 ? rules.safeWidth : rules.nativeWidth;
        mac.height = rules.safeHeight > 0 ? rules.safeHeight : rules.nativeHeight;
        mac.maxRefresh = rules.maxRefresh;
        mac.isMain = display.isMain;
        mac.isBuiltin = display.isBuiltin;
        mac.isDisplayExtend = display.isDisplayExtend;
        mac.hdr = rules.hdr;
        mac.vendor = display.vendor;
        mac.model = display.model;
        mac.serial = display.serial;
        mac.name = rules.name;
        mac.screen = ClientDisplay::describe(rules, display.isBuiltin, peakOverride);
        displays.push_back(mac);
    }
    return displays;
}

bool canStreamGroup(NvComputer* computer)
{
    int slotCount;
    {
        QReadLocker lock(&computer->lock);
        slotCount = computer->forkDisplayGroupSlots;
    }
    return slotCount >= 2 && macDisplays().size() >= 2;
}

void prepareSession(NvComputer* computer, const NvApp& app, StreamingPreferences* prefs)
{
    QMutexLocker lock(&s_Lock);

    // A helper's slot was set from its command line
    if (s_Role == Role::Helper) {
        return;
    }

    s_Role = Role::None;
    s_Group.reset();
    s_Probes.reset();
    s_Target = 0;

    if (!isGroupApp(computer, app)) {
        return;
    }

    auto group = std::make_shared<Group>();
    QStringList pcAddresses;
    int slotCount;
    {
        QReadLocker computerLock(&computer->lock);
        slotCount = computer->forkDisplayGroupSlots;
        group->hostUuid = computer->uuid;
        group->hostName = computer->name;
        group->address = computer->activeAddress.address();
        group->httpPort = computer->activeAddress.port();
        group->httpsPort = computer->activeHttpsPort;
    }
    // Takes the computer's lock itself
    for (const NvAddress& address : computer->uniqueAddresses()) {
        pcAddresses.append(address.address());
    }
    group->appName = app.name;
    group->appId = app.id;
    group->videoCodecConfig = prefs->videoCodecConfig;
    group->route = static_cast<ForkDisplayRoute::Setting>(ForkPreferences::get()->imacRoute());

    ForkDisplayGroup::Stream stream;
    stream.width = prefs->width;
    stream.height = prefs->height;
    stream.fps = prefs->fps;
    stream.bitrateKbps = prefs->bitrateKbps;
    stream.hdr = prefs->enableHdr;

    group->plan = ForkDisplayGroup::plan(macDisplays(), stream, slotCount, newGroupId().toStdString());
    if (group->plan.slotList.size() < 2) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] \"%s\" with one display (the host offers %d): streaming it like a single display",
                    qPrintable(app.name), slotCount);
        return;
    }

    logPlan(*group);
    size_t displayCount = macDisplays().size();
    if (group->plan.slotList.size() < displayCount) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] The host streams %d displays at most: %zu of this Mac's %zu displays are left out",
                    slotCount, displayCount - group->plan.slotList.size(), displayCount);
    }

    s_Role = Role::Main;
    s_Target = group->plan.slotList[0].displayId;

    bool hasExternal = false;
    for (const ForkDisplayGroup::Slot& slot : group->plan.slotList) {
        hasExternal = hasExternal || slot.external;
    }
    if (hasExternal && group->route != ForkDisplayRoute::Setting::ViaMac) {
        s_Probes = std::make_shared<Probes>();
        startProbes(s_Probes, pcAddresses, group->httpsPort, group->address, group->hostUuid);
    }

    s_Group = group;
}

void setHelper(const QString& groupId, int slot, uint32_t displayId)
{
    QMutexLocker lock(&s_Lock);
    s_Role = Role::Helper;
    s_Group.reset();
    s_Probes.reset();
    s_Target = displayId;
    s_HelperGroupId = groupId;
    s_HelperSlot = slot;
}

bool isHelper()
{
    QMutexLocker lock(&s_Lock);
    return s_Role == Role::Helper;
}

bool isGroupMain()
{
    QMutexLocker lock(&s_Lock);
    return s_Role == Role::Main;
}

std::shared_ptr<const Group> group()
{
    QMutexLocker lock(&s_Lock);
    return s_Group;
}

uint32_t targetDisplay()
{
    QMutexLocker lock(&s_Lock);
    return s_Target;
}

int targetDisplayIndex()
{
#ifdef Q_OS_DARWIN
    uint32_t target = targetDisplay();
    if (target == 0) {
        return -1;
    }

    constexpr uint32_t maxDisplays = 16;
    CGDirectDisplayID displayIds[maxDisplays];
    uint32_t displayCount = 0;
    if (CGGetActiveDisplayList(maxDisplays, displayIds, &displayCount) != kCGErrorSuccess) {
        return -1;
    }
    for (uint32_t i = 0; i < displayCount; i++) {
        if (displayIds[i] == target) {
            return static_cast<int>(i);
        }
    }
#endif
    return -1;
}

int targetSdlDisplayIndex()
{
#ifdef Q_OS_DARWIN
    uint32_t target = targetDisplay();
    if (target == 0 || !SDL_WasInit(SDL_INIT_VIDEO)) {
        return -1;
    }

    // SDL lists displays in its own order (and leaves mirrors out), so match it by position: SDL
    // and CoreGraphics both use points with the main display's top-left corner at 0,0
    CGRect bounds = CGDisplayBounds(target);
    for (int i = 0; i < SDL_GetNumVideoDisplays(); i++) {
        SDL_Rect sdlBounds;
        if (SDL_GetDisplayBounds(i, &sdlBounds) == 0 &&
                std::abs(sdlBounds.x - bounds.origin.x) < 1 && std::abs(sdlBounds.y - bounds.origin.y) < 1) {
            return i;
        }
    }
#endif
    return -1;
}

QString launchArgs()
{
    QMutexLocker lock(&s_Lock);
    switch (s_Role) {
    case Role::Main:
        return QString::fromStdString(ForkDisplayGroup::launchArgs(s_Group->plan));
    case Role::Helper:
        return QString::fromStdString(ForkDisplayGroup::joinArgs(s_HelperGroupId.toStdString(), s_HelperSlot));
    default:
        return QString();
    }
}

ForkDisplayRoute::Facts routeFacts(int timeoutMs, bool* done)
{
    std::shared_ptr<Probes> probes;
    {
        QMutexLocker lock(&s_Lock);
        probes = s_Probes;
    }
    if (!probes) {
        // None were started: nothing to wait for
        if (done != nullptr) {
            *done = true;
        }
        return ForkDisplayRoute::Facts();
    }

    std::unique_lock<std::mutex> lock(probes->lock);
    probes->changed.wait_for(lock, std::chrono::milliseconds(timeoutMs), [&probes]() { return probes->done; });
    if (done != nullptr) {
        *done = probes->done;
    }
    return probes->facts;
}

}
