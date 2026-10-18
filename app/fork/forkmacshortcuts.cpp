#include "forkmacshortcuts.h"

#include <algorithm>
#include <cctype>
#include <set>

namespace ForkMacShortcuts
{
    // Ids and names are macOS 27's (scripts/fork/hotkey-probe.mm list). Hot keys macOS won't turn
    // off per app are left out, except Cmd+Tab: the F3 Mission Control variants (110-117) and the
    // Spotlight, language and Do Not Disturb keys (187-189, 191).
    const std::vector<Group>& groups()
    {
        static const std::vector<Group> s_Groups = {
            { "spotlight", "Spotlight (⌘Space, ⌥⌘Space)", true, ScopeApp, {
                { 64, "Spotlight" }, { 65, "SpotlightResult" },
                { 100, "Spotlight Key" }, { 101, "Spotlight Key Prefs" } } },
            { "appSwitcher", "App switcher (⌘Tab)", false, ScopeGlobal, {
                { 1, "SwitchFwd" }, { 2, "SwitchBack" } } },
            { "missionControl", "Mission Control, App Exposé, Show Desktop and Launchpad (⌃↑, ⌃↓, F3, F11)", true, ScopeApp, {
                { 32, "WindowVousAll" }, { 33, "WindowVousFront" },
                { 34, "WindowVousAllSlow" }, { 35, "WindowVousFrontSlow" },
                { 36, "WindowVousShowDesktop" }, { 37, "WindowVousShowDesktop" },
                { 108, "Expose All" }, { 109, "Expose All Prefs" },
                { 160, "LaunchpadHotKey" }, { 161, "LaunchpadSlowHotKey" },
                { 173, "Launchpad Key" }, { 174, "Slow Launchpad Key" } } },
            { "spaces", "Spaces and desktops (⌃←, ⌃→, ⌃1–⌃9)", true, ScopeApp, {
                { 79, "WorkspacesLeft" }, { 80, "WorkspacesLeftSlow" },
                { 81, "WorkspacesRight" }, { 82, "WorkspacesRightSlow" },
                { 118, "Workspaces1" }, { 119, "Workspaces2" }, { 120, "Workspaces3" },
                { 121, "Workspaces4" }, { 122, "Workspaces5" }, { 123, "Workspaces6" },
                { 124, "Workspaces7" }, { 125, "Workspaces8" }, { 126, "Workspaces9" } } },
            { "windowManagement", "Window shortcuts (⌘`, ⌘M, ⇧⌘F, tiling)", true, ScopeApp, {
                { 27, "RotateWindows" }, { 220, "RotateWindowsBack" },
                { 157, "ToggleFullScreen" }, { 222, "ToggleStageManager" },
                { 233, "WindowMinimize" }, { 234, "WindowMinimizeAll" },
                { 237, "WindowFill" }, { 238, "WindowCenter" }, { 239, "WindowReturnToPreviousSize" },
                { 240, "WindowTileLeftHalf" }, { 241, "WindowTileRightHalf" },
                { 242, "WindowTileTopHalf" }, { 243, "WindowTileBottomHalf" },
                { 248, "WindowArrangeLeftAndRight" }, { 249, "WindowArrangeRightAndLeft" },
                { 250, "WindowArrangeTopAndBottom" }, { 251, "WindowArrangeBottomAndTop" },
                { 252, "WindowArrangeLeftAndQuarters" }, { 253, "WindowArrangeRightAndQuarters" },
                { 254, "WindowArrangeTopAndQuarters" }, { 255, "WindowArrangeBottomAndQuarters" } } },
            { "keyboardNavigation", "Keyboard navigation (⌃F1–⌃F8)", true, ScopeApp, {
                { 7, "AccessMenu" }, { 8, "AccessDock" }, { 9, "AccessWindow" },
                { 10, "AccesToolbar" }, { 11, "AccessUtilWin" }, { 12, "AccessOn" },
                { 13, "AccessHilite" }, { 51, "FKAccessDrawer" }, { 57, "FocusOnMenuExtras" },
                { 158, "FullKeyboardAccessPopupMenubar" }, { 159, "FullKeyboardAccessContextMenu" },
                { 221, "AccessWindowBack" } } },
            { "inputSources", "Input sources (⌃Space, ⌃⌥Space)", true, ScopeApp, {
                { 60, "TSMLastScript" }, { 61, "TSMRotateScript" } } },
            { "otherSystem", "Emoji, Look Up, Dock hiding and Help (⌃⌘Space, ⌃⌘D, ⌥⌘D, ⇧⌘/)", true, ScopeApp, {
                { 50, "ShowHideCharacterPalette" }, { 70, "DictionaryApp" },
                { 52, "FKAccessHideDock" }, { 97, "HelpHotKey" }, { 98, "HelpComboHotKey" },
                { 62, "Dashboard" }, { 63, "DashboardSlow" } } },
            { "gameOverlay", "Game Overlay (⌘Esc)", true, ScopeApp, {
                { 260, "GameOverlay" } } },
            { "globeKey", "Globe key shortcuts (🌐 with another key)", false, ScopeApp, {
                { 175, "NC Do Not Disturb" }, { 190, "CreateNoteHotKey" },
                { 192, "WorkspacesLeft" }, { 193, "WorkspacesRight" },
                { 194, "WorkspacesDown" }, { 195, "WorkspacesUp" },
                { 196, "WindowVousShowDesktop" }, { 197, "SplitViewFullscreen" },
                { 198, "SplitViewWindowPicker" }, { 199, "SplitViewMakeLeft" },
                { 200, "SplitViewMakeRight" }, { 201, "SplitViewNextWindow" },
                { 202, "SplitViewPreviousWindow" }, { 203, "SlideOverShow" },
                { 204, "SlideMakeSlideOver" }, { 205, "SlideLeftSlideOver" },
                { 206, "SlideRightSlideOver" }, { 207, "SlideNextSlideOver" },
                { 208, "SlidePreviousSlideOver" }, { 209, "SystemSiri" },
                { 210, "SystemDock" }, { 211, "SystemControlCenter" },
                { 212, "SystemNotificationCenter" }, { 213, "SystemMenuBar" },
                { 214, "SystemLaunchpad" } } },
            { "screenshots", "Screenshots and screen recording (⇧⌘3, ⇧⌘4, ⇧⌘5)", false, ScopeApp, {
                { 28, "CaptureScreenToFile" }, { 29, "CaptureScreenToScrap" },
                { 30, "CaptureSelectionToFile" }, { 31, "CaptureSelectionToScrap" },
                { 181, "CaptureTouchBarToFile" }, { 182, "CaptureTouchBarToScrap" },
                { 184, "CaptureSelectionToFile2" }, { 185, "CaptureSelectionToScrap2" } } },
            { "visualIntelligence", "Visual Intelligence (⇧⌘6, ⇧⌘Space)", false, ScopeApp, {
                { 261, "CaptureForVisualIntelligence" }, { 262, "CaptureForVisualIntelligenceToScrap" },
                { 263, "CaptureTopWindowForVisualIntelligence" },
                { 264, "CaptureTopWindowForVisualIntelligenceToScrap" } } },
        };
        return s_Groups;
    }

    const Group* findGroup(const std::string& key)
    {
        for (const Group& group : groups()) {
            if (key == group.key) {
                return &group;
            }
        }
        return nullptr;
    }

    bool isProtected(int id)
    {
        static const std::set<int> s_Protected = {
            0, 6,                                           // Force Quit (⌥⌘Esc, ⌥⇧⌘Esc)
            3, 5, 14,                                       // session interrupt, eject, force logout
            4, 99, 178,                                     // screen saver, sleep display, power button
            15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, // zoom and display accessibility
            58, 59, 162, 177, 179,                          // accessibility shortcuts, VoiceOver
            53, 54, 55, 56, 104, 105, 106, 107,             // brightness
            150, 151, 152, 153, 154, 155,
            165, 166, 167, 168, 169, 170, 171, 172,
            186, 215, 216, 217, 218, 219,                   // dictation and transcription
            225, 226, 227, 228, 229, 230, 231, 232, 259,    // Live Speech, Speak, Accessibility Reader
        };
        return s_Protected.count(id) != 0;
    }

    std::vector<Wanted> wantedHotKeys(const std::function<bool(const Group&)>& toHost)
    {
        std::vector<Wanted> wanted;
        std::set<int> seen;
        for (const Group& group : groups()) {
            if (!toHost(group)) {
                continue;
            }
            for (const HotKey& hotKey : group.hotKeys) {
                if (!isProtected(hotKey.id) && seen.insert(hotKey.id).second) {
                    wanted.push_back({ hotKey.id, group.scope, hotKey.name });
                }
            }
        }
        return wanted;
    }

    std::string formatRecord(long pid, const std::vector<int>& ids)
    {
        if (ids.empty()) {
            return std::string();
        }

        std::string text = std::to_string(pid) + ":";
        for (size_t i = 0; i < ids.size(); i++) {
            if (i > 0) {
                text += ",";
            }
            text += std::to_string(ids[i]);
        }
        return text;
    }

    namespace
    {
        // A positive decimal number without signs or spaces, at most max
        bool parseNumber(const std::string& text, long max, long* value)
        {
            if (text.empty() || text.size() > 10) {
                return false;
            }
            long result = 0;
            for (char c : text) {
                if (!std::isdigit(static_cast<unsigned char>(c))) {
                    return false;
                }
                result = result * 10 + (c - '0');
            }
            if (result > max) {
                return false;
            }
            *value = result;
            return true;
        }
    }

    bool parseRecord(const std::string& text, long* pid, std::vector<int>* ids)
    {
        size_t colon = text.find(':');
        if (colon == std::string::npos) {
            return false;
        }

        long parsedPid;
        if (!parseNumber(text.substr(0, colon), 0x7fffffffL, &parsedPid) || parsedPid == 0) {
            return false;
        }

        std::vector<int> parsedIds;
        std::set<int> seen;
        std::string rest = text.substr(colon + 1);
        size_t start = 0;
        while (true) {
            size_t comma = rest.find(',', start);
            long id;
            if (!parseNumber(rest.substr(start, comma == std::string::npos ? std::string::npos : comma - start),
                             MaxHotKeyId, &id) ||
                    id == 0 || !seen.insert(static_cast<int>(id)).second) {
                return false;
            }
            parsedIds.push_back(static_cast<int>(id));
            if (comma == std::string::npos) {
                break;
            }
            start = comma + 1;
        }

        *pid = parsedPid;
        *ids = parsedIds;
        return true;
    }

    Controller::Controller(Backend backend, std::vector<Wanted> wanted)
        : m_Backend(std::move(backend)),
          m_Wanted(std::move(wanted)),
          m_Taken(false)
    {
    }

    std::vector<int> Controller::heldGlobalIds() const
    {
        std::vector<int> ids;
        for (const Wanted& hotKey : m_Held) {
            if (hotKey.scope == ScopeGlobal) {
                ids.push_back(hotKey.id);
            }
        }
        return ids;
    }

    void Controller::update(bool take)
    {
        if (take == m_Taken) {
            return;
        }

        if (take) {
            std::vector<Wanted> toTake;
            std::vector<int> globalIds;
            for (const Wanted& hotKey : m_Wanted) {
                if (m_Backend.isEnabled(hotKey.id)) {
                    toTake.push_back(hotKey);
                    if (hotKey.scope == ScopeGlobal) {
                        globalIds.push_back(hotKey.id);
                    }
                }
            }

            // Record global hot keys before turning them off, so a crash in between can't lose them
            if (!globalIds.empty()) {
                m_Backend.persist(globalIds);
            }

            for (const Wanted& hotKey : toTake) {
                if (m_Backend.setEnabled(hotKey.id, hotKey.scope, false)) {
                    m_Held.push_back(hotKey);
                }
            }

            // Drop the ones macOS refused from the record
            if (!globalIds.empty() && heldGlobalIds() != globalIds) {
                m_Backend.persist(heldGlobalIds());
            }
        }
        else {
            bool hadGlobal = !heldGlobalIds().empty();
            for (const Wanted& hotKey : m_Held) {
                m_Backend.setEnabled(hotKey.id, hotKey.scope, true);
            }
            m_Held.clear();

            if (hadGlobal) {
                m_Backend.persist({});
            }
        }

        m_Taken = take;
    }
}
