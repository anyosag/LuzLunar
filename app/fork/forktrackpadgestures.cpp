#include "forktrackpadgestures.h"

#include <cctype>
#include <cstdlib>
#include <utility>

namespace ForkTrackpadGestures
{
namespace
{
    bool parseInt(const std::string& text, long* value)
    {
        if (text.empty()) {
            return false;
        }
        char* end = nullptr;
        long v = std::strtol(text.c_str(), &end, 10);
        if (end == nullptr || *end != '\0') {
            return false;
        }
        *value = v;
        return true;
    }

    bool validName(const std::string& name)
    {
        if (name.empty()) {
            return false;
        }
        for (char c : name) {
            if (!std::isalnum(static_cast<unsigned char>(c))) {
                return false;
            }
        }
        return true;
    }
}

bool DockGestureFilter::swallow(std::uint32_t timeMs)
{
    std::int32_t sinceLast = static_cast<std::int32_t>(timeMs - m_Last);
    bool continuing = m_InGesture && sinceLast < static_cast<std::int32_t>(k_QuietMs);
    if (!continuing) {
        // A new gesture: dropped or passed whole
        m_Swallowing = m_Armed;
    }
    m_InGesture = true;
    if (!continuing || sinceLast > 0) {
        m_Last = timeMs;
    }
    return m_Swallowing;
}

std::string formatRecord(long pid, const std::vector<Held>& held)
{
    std::string text = std::to_string(pid) + ":";
    for (std::size_t i = 0; i < held.size(); i++) {
        if (i > 0) {
            text += ",";
        }
        text += held[i].name + "=" + std::to_string(held[i].original) + "/" + std::to_string(held[i].written);
    }
    return text;
}

bool parseRecord(const std::string& text, long* pid, std::vector<Held>* held)
{
    std::size_t colon = text.find(':');
    if (colon == std::string::npos || !parseInt(text.substr(0, colon), pid)) {
        return false;
    }

    std::vector<Held> out;
    std::string rest = text.substr(colon + 1);
    std::size_t start = 0;
    while (start <= rest.size()) {
        std::size_t comma = rest.find(',', start);
        std::string entry = rest.substr(start, comma == std::string::npos ? std::string::npos : comma - start);

        std::size_t equals = entry.find('=');
        std::size_t slash = entry.find('/', equals == std::string::npos ? 0 : equals);
        long original = 0, written = 0;
        if (equals == std::string::npos || slash == std::string::npos ||
                !validName(entry.substr(0, equals)) ||
                !parseInt(entry.substr(equals + 1, slash - equals - 1), &original) ||
                !parseInt(entry.substr(slash + 1), &written)) {
            return false;
        }
        Held h;
        h.name = entry.substr(0, equals);
        h.original = static_cast<int>(original);
        h.written = static_cast<int>(written);
        out.push_back(h);

        if (comma == std::string::npos) {
            break;
        }
        start = comma + 1;
    }

    if (out.empty()) {
        return false;
    }
    *held = std::move(out);
    return true;
}

void restore(const HoldBackend& backend, const std::vector<Held>& held)
{
    for (const Held& h : held) {
        std::optional<int> now = backend.read(h.name);
        // Leave alone a setting the user changed meanwhile
        if (now && *now == h.written) {
            backend.write(h.name, h.original);
        }
    }
    backend.persist(std::string());
}

bool restoreRecord(const std::string& record, const HoldBackend& backend,
                   const std::function<bool(long pid)>& isRunningCopy)
{
    if (record.empty()) {
        return false;
    }
    long pid = 0;
    std::vector<Held> held;
    if (!parseRecord(record, &pid, &held)) {
        backend.persist(std::string());
        return false;
    }
    if (isRunningCopy(pid)) {
        // That copy (a stream from the command line, say) puts them back itself
        return false;
    }
    restore(backend, held);
    return true;
}

SettingsHold::SettingsHold(HoldBackend backend, std::vector<Setting> settings, long pid)
    : m_Backend(std::move(backend)),
      m_Settings(std::move(settings)),
      m_Pid(pid)
{
}

void SettingsHold::want(bool on, std::uint32_t timeMs)
{
    if (on) {
        m_ReleasePending = false;
        if (m_Held.empty()) {
            hold();
        }
    }
    else if (!m_Held.empty() && !m_ReleasePending) {
        m_ReleasePending = true;
        m_ReleaseAt = timeMs + k_ReleaseDelayMs;
    }
}

void SettingsHold::tick(std::uint32_t timeMs)
{
    if (m_ReleasePending && static_cast<std::int32_t>(timeMs - m_ReleaseAt) >= 0) {
        releaseNow();
    }
}

void SettingsHold::releaseNow()
{
    m_ReleasePending = false;
    if (m_Held.empty()) {
        return;
    }
    restore(m_Backend, m_Held);
    m_Held.clear();
}

void SettingsHold::hold()
{
    std::vector<Held> wanted;
    for (const Setting& s : m_Settings) {
        std::optional<int> value = m_Backend.read(s.name);
        if (value && *value != s.off) {
            Held h;
            h.name = s.name;
            h.original = *value;
            h.written = s.off;
            wanted.push_back(h);
        }
    }
    if (wanted.empty()) {
        return;
    }

    // The record goes first, so a crash between the writes still gets them put back
    m_Backend.persist(formatRecord(m_Pid, wanted));
    for (const Held& h : wanted) {
        if (m_Backend.write(h.name, h.written)) {
            m_Held.push_back(h);
        }
    }
    if (m_Held.size() != wanted.size()) {
        m_Backend.persist(m_Held.empty() ? std::string() : formatRecord(m_Pid, m_Held));
    }
}
}
