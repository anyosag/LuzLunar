#include "forkmultidisplay.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QMutex>
#include <QMutexLocker>
#include <QRandomGenerator>
#include <QReadLocker>
#include <QSettings>

#include <chrono>
#include <thread>

#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "clientdisplay.h"
#include "clienthardware.h"
#include "forkdisplayextend.h"
#include "forkpreferences.h"
#include "mac/networklink.h"
#include "settings/streamingpreferences.h"
#include "SDL_compat.h"

#ifdef Q_OS_DARWIN
#include <ApplicationServices/ApplicationServices.h>
#include <cmath>
#endif

// A group with the last launch's iMac route measurements per PC (by uuid), as ForkRouteMemory::encode() writes them
#define SER_ROUTEMEMORY "fork/imacRouteMemory"

namespace ForkMultiDisplay
{

namespace
{
    enum class Role { None, Main, Helper };

    QMutex s_Lock;
    Role s_Role = Role::None;
    std::shared_ptr<const Group> s_Group;
    bool s_RouteDecided = false;
    ForkDisplayRoute::Decision s_RouteDecision;
    ForkDisplayRoute::Facts s_RouteFacts;
    uint32_t s_Target = 0;
    QString s_HelperGroupId;
    int s_HelperSlot = 0;

    QString newGroupId()
    {
        return QString::number(QRandomGenerator::global()->generate64(), 16).rightJustified(16, '0');
    }

    // What a measurement is for: the PC, the iMac and the Mac's DisplayExtend display as DisplayExtend
    // reports them, and the network this Mac reaches the PC over (hashed, like ForkNetworkLink's)
    ForkRouteMemory::Key routeKey(const Group& group, const ForkDisplayExtend::Status& status)
    {
        ForkRouteMemory::Key key;
        if (!status.ok) {
            return key;
        }
        key.hostUuid = group.hostUuid.toStdString();
        key.imacAddress = status.imacAddress.toStdString();
        if (status.width > 0 && status.height > 0) {
            key.display = std::to_string(status.width) + "x" + std::to_string(status.height);
        }
        std::string network = MacNetworkLink::probe(MacNetworkLink::numericAddress(group.address.toStdString())).networkId;
        if (!network.empty()) {
            key.network = QCryptographicHash::hash(QByteArray::fromStdString(network), QCryptographicHash::Sha256)
                              .toHex().left(32).toStdString();
        }
        return key;
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
    s_RouteDecided = false;
    s_Target = 0;

    if (!isGroupApp(computer, app)) {
        return;
    }

    auto group = std::make_shared<Group>();
    int slotCount;
    {
        QReadLocker computerLock(&computer->lock);
        slotCount = computer->forkDisplayGroupSlots;
        group->hostUuid = computer->uuid;
        group->hostName = computer->name;
        group->address = computer->activeAddress.address();
        group->httpPort = computer->activeAddress.port();
        group->httpsPort = computer->activeHttpsPort;
        // As AppView decides between Launch and Resume
        group->resume = computer->currentGameId != 0 && computer->currentGameId == app.id;
    }
    // Takes the computer's lock itself
    for (const NvAddress& address : computer->uniqueAddresses()) {
        group->pcAddresses.append(address.address());
    }
    group->appName = app.name;
    group->appId = app.id;
    group->videoCodecConfig = prefs->videoCodecConfig;
    group->route = static_cast<ForkDisplayRoute::Setting>(ForkPreferences::get()->imacRoute());
    group->imacCodec = static_cast<ForkDisplayRoute::CodecSetting>(ForkPreferences::get()->imacCodec());
    group->imacBitrateKbps = ForkPreferences::get()->imacBitrateKbps();

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

    s_Group = group;
}

void setHelper(const QString& groupId, int slot, uint32_t displayId)
{
    QMutexLocker lock(&s_Lock);
    s_Role = Role::Helper;
    s_Group.reset();
    s_RouteDecided = false;
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

bool routeCheckNeeded()
{
    std::shared_ptr<const Group> current = group();
    if (!current || current->route == ForkDisplayRoute::Setting::ViaMac) {
        return false;
    }
    for (const ForkDisplayGroup::Slot& slot : current->plan.slotList) {
        if (slot.external) {
            return true;
        }
    }
    return false;
}

RouteCheck checkRoute(const Group& group, const ForkRouteMemory::Memory* remembered,
                      const std::function<void(const ForkDisplayRoute::Facts&, double)>& progress)
{
    RouteCheck check;
    ForkDisplayRoute::Facts& facts = check.facts;
    if (!ForkDisplayExtend::available()) {
        progress(facts, 1);
        return check;
    }

    ForkDisplayExtend bridge;
    if (!bridge.open(1000)) {
        progress(facts, 1);
        return check;
    }

    ForkDisplayExtend::Status status = bridge.status(2000);
    facts.bridge = status.ok;
    facts.imacConnected = status.imacConnected;
    facts.directSupported = status.directSupported;
    facts.moonlightVerified = status.moonlightVerified;
    facts.paired = status.pairedHostIds.contains(group.hostUuid, Qt::CaseInsensitive);
    facts.displayExtendP50Ms = status.p50Ms;
    facts.displayExtendP95Ms = status.p95Ms;
    facts.displayExtendFrames = status.frames;
    if (status.hz > 0) {
        facts.virtualRefreshHz = status.hz;
    }
    facts.imacCodecs = status.codecs;
    check.key = routeKey(group, status);

    // A Resume: the launch measured for the same PC, iMac, display and network, so its connect
    // times stand; whether the iMac can still go straight from the PC is as DisplayExtend says now
    if (remembered != nullptr && ForkRouteMemory::reusable(*remembered, check.key)) {
        facts = ForkRouteMemory::recall(*remembered, facts);
        check.recalled = true;
        check.measuredAt = remembered->measuredAt;
        progress(facts, 1);
        return check;
    }

    // Probing only matters when the iMac could go straight from the PC
    if (!(facts.bridge && facts.imacConnected && facts.directSupported && facts.moonlightVerified && facts.paired) ||
            group.pcAddresses.isEmpty()) {
        progress(facts, 1);
        return check;
    }
    progress(facts, 0.04);
    check.measuredAt = QDateTime::currentSecsSinceEpoch();

    std::vector<std::vector<ForkDisplayRoute::Probe>> imacRounds(static_cast<size_t>(group.pcAddresses.size()));
    std::vector<ForkDisplayRoute::Probe> macRounds;
    QStringList probed = group.pcAddresses;   // the addresses the iMac still tries
    for (int round = 0; round < k_RouteRounds && !probed.isEmpty(); round++) {
        auto started = std::chrono::steady_clock::now();

        // This Mac's connects at the same moment as the iMac's
        ForkDisplayRoute::Probe macRound;
        std::thread mac([&macRound, &group]() {
            macRound = ForkRouteProbe::tcpConnects(group.address, group.httpsPort, k_RouteRoundConnects, 1000);
        });
        std::vector<ForkDisplayRoute::Probe> imac = bridge.probe(probed, group.httpsPort, k_RouteRoundConnects,
                                                                 (k_RouteRoundConnects + 1) * 1000 + 1000);
        mac.join();

        macRounds.push_back(macRound);
        std::vector<ForkDisplayRoute::Probe> answers;
        for (int i = 0; i < group.pcAddresses.size(); i++) {
            if (!probed.contains(group.pcAddresses[i])) {
                continue;
            }
            ForkDisplayRoute::Probe answer;
            answer.address = group.pcAddresses[i].toStdString();
            answer.count = k_RouteRoundConnects;
            answer.failures = k_RouteRoundConnects;   // no answer for it counts as connects that failed
            for (const ForkDisplayRoute::Probe& probe : imac) {
                if (probe.address == answer.address) {
                    answer = probe;
                }
            }
            imacRounds[static_cast<size_t>(i)].push_back(answer);
            answers.push_back(answer);
        }

        // After the first round, only the addresses that answered: one the iMac can't reach waits
        // out a timeout on every connect
        if (round == 0) {
            QStringList answering;
            for (size_t i : ForkDisplayRoute::answering(answers)) {
                answering.append(QString::fromStdString(answers[i].address));
            }
            for (const QString& address : probed) {
                if (!answering.contains(address)) {
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] iMac route: the iMac can't reach %s, so it isn't timed again",
                                qPrintable(address));
                }
            }
            probed = answering;
        }

        facts.macToPc = ForkDisplayRoute::combine(macRounds);
        facts.imacToPc.clear();
        for (const std::vector<ForkDisplayRoute::Probe>& rounds : imacRounds) {
            facts.imacToPc.push_back(ForkDisplayRoute::combine(rounds));
        }
        progress(facts, 0.04 + 0.96 * (round + 1) / k_RouteRounds);

        std::this_thread::sleep_until(started + std::chrono::milliseconds(k_RouteRoundMs));
    }
    progress(facts, 1);
    return check;
}

bool rememberedRoute(const QString& hostUuid, ForkRouteMemory::Memory* memory)
{
    QString text = QSettings().value(QStringLiteral(SER_ROUTEMEMORY "/") + hostUuid).toString();
    return !text.isEmpty() && ForkRouteMemory::decode(text.toStdString(), memory) &&
           memory->key.hostUuid == hostUuid.toStdString();
}

void rememberRoute(const RouteCheck& check)
{
    if (check.recalled || check.key.hostUuid.empty() || !ForkRouteMemory::worthKeeping(check.facts)) {
        return;
    }
    QSettings().setValue(QStringLiteral(SER_ROUTEMEMORY "/") + QString::fromStdString(check.key.hostUuid),
                         QString::fromStdString(ForkRouteMemory::encode(ForkRouteMemory::remember(check.key, check.facts, check.measuredAt))));
}

void setRouteDecision(const ForkDisplayRoute::Decision& decision, const ForkDisplayRoute::Facts& facts)
{
    QMutexLocker lock(&s_Lock);
    s_RouteDecision = decision;
    s_RouteFacts = facts;
    s_RouteDecided = true;
}

bool routeDecision(ForkDisplayRoute::Decision* decision, ForkDisplayRoute::Facts* facts)
{
    QMutexLocker lock(&s_Lock);
    if (s_RouteDecided) {
        if (decision != nullptr) {
            *decision = s_RouteDecision;
        }
        if (facts != nullptr) {
            *facts = s_RouteFacts;
        }
    }
    return s_RouteDecided;
}

}
