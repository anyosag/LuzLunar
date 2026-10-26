#pragma once

#include <QString>
#include <QStringList>

#include <functional>
#include <memory>
#include <vector>

#include "forkdisplaygroup.h"
#include "forkdisplayroute.h"

class NvApp;
class NvComputer;
class StreamingPreferences;

// This process's part in a multi-display stream, "Desktop (multiple displays)" (forkdisplaygroup.*).
// The main process streams slot 0 and, once connected, brings up the other slots
// (forkdisplaycoordinator.*); a helper process streams one other slot (forkhelper.*). Every session
// is prepared here, so a stream that isn't part of a group clears what the last one set. A process
// runs one stream at a time (Session is a singleton), so this is process-wide.
namespace ForkMultiDisplay
{
    // What the coordinator needs to bring up the other slots, captured on the main thread
    struct Group {
        ForkDisplayGroup::Plan plan;
        QString hostUuid, hostName;
        QString address;                 // the address and HTTP port slot 0 streams from
        uint16_t httpPort = 0, httpsPort = 0;
        QStringList pcAddresses;         // every address of the PC, for the iMac's probes
        QString appName;
        int appId = 0;
        int videoCodecConfig = 0;        // slot 0's StreamingPreferences::VideoCodecConfig
        ForkDisplayRoute::Setting route = ForkDisplayRoute::Setting::Automatic;
    };

    // Whether app is the host's multi-display app (anyosag/Apollo's <LuzDisplayGroupApp>)
    bool isGroupApp(NvComputer* computer, const NvApp& app);

    // Whether this Mac and the host can stream several displays: two or more displays (mirrors
    // don't count), and a host that offers two or more slots. The app grid hides the app otherwise.
    // Displays beyond what the host offers are left out, DisplayExtend's first.
    bool canStreamGroup(NvComputer* computer);

    // This Mac's displays as the plan needs them (mirrors left out), from ClientHardware
    std::vector<ForkDisplayGroup::MacDisplay> macDisplays();

    // Called by StreamProfiles::createSession for every session, with the session's own settings:
    // the multi-display app gets a group planned from this Mac's displays, and its stream opens on
    // slot 0's display; anything else clears the last group. Logs the plan. Main thread.
    void prepareSession(NvComputer* computer, const NvApp& app, StreamingPreferences* prefs);

    // A helper process: which slot of which group it streams, on which display
    void setHelper(const QString& groupId, int slot, uint32_t displayId);

    bool isHelper();
    bool isGroupMain();

    // The group slot 0 streams, null outside one (and in helpers)
    std::shared_ptr<const Group> group();

    // The display this process's stream opens on; 0 for Moonlight's usual choice (where the window is)
    uint32_t targetDisplay();

    // Its index in CGGetActiveDisplayList's order (StreamUtils', ClientHardware's) and in SDL's;
    // -1 without a target, or when it's gone
    int targetDisplayIndex();
    int targetSdlDisplayIndex();

    // The fork's /launch and /resume arguments for the group: slot 0's declaration, or a helper's
    // join; empty outside a group
    QString launchArgs();

    // Whether the group has DisplayExtend's display and the setting lets it go straight from the
    // PC, so the launch screen checks the route before connecting (ForkGroupLaunch)
    bool routeCheckNeeded();

    // The check: DisplayExtend's status, then (when the iMac could go straight from the PC)
    // k_RouteRounds rounds of connects to the PC, from the iMac to each of its addresses and from
    // this Mac, k_RouteRoundMs apart: typical times and worst cases both count. Blocking, for a
    // worker thread; progress (0 to 1) is called after each step with the facts so far.
    constexpr int k_RouteRounds = 10;
    constexpr int k_RouteRoundConnects = 3;
    constexpr int k_RouteRoundMs = 250;
    ForkDisplayRoute::Facts checkRoute(const Group& group,
                                       const std::function<void(const ForkDisplayRoute::Facts&, double)>& progress);

    // The route chosen for this group, kept for the coordinator; false until chosen
    void setRouteDecision(const ForkDisplayRoute::Decision& decision, const ForkDisplayRoute::Facts& facts);
    bool routeDecision(ForkDisplayRoute::Decision* decision, ForkDisplayRoute::Facts* facts);
}
