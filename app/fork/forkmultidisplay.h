#pragma once

#include <QString>
#include <QStringList>

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

    // The route probes for DisplayExtend's slot, started by prepareSession: DisplayExtend's status
    // and the iMac's and this Mac's connects to the PC. Waits up to timeoutMs for them; done (if
    // given) says whether they finished, since until then the facts are empty.
    ForkDisplayRoute::Facts routeFacts(int timeoutMs, bool* done = nullptr);
}
