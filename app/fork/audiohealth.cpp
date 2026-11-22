#include "audiohealth.h"

#include <algorithm>
#include <cstdio>

namespace AudioHealth
{

Monitor::Monitor(double lateMs, double reportEveryMs)
    : m_LateMs(lateMs),
      m_ReportEveryMs(reportEveryMs)
{
}

void Monitor::packet(double nowMs, double waitingMs)
{
    if (m_FirstMs < 0) {
        m_FirstMs = nowMs;
        m_WindowStartMs = nowMs;
    }
    else {
        double gap = nowMs - m_LastPacketMs;
        bool pause = gap >= k_PauseMs;
        if (pause) {
            m_Total.pauses++;
            m_Window.pauses++;
        }
        else {
            if (gap > m_LateMs) {
                m_Total.late++;
                m_Window.late++;
            }
            m_Total.longestGapMs = std::max(m_Total.longestGapMs, gap);
            m_Window.longestGapMs = std::max(m_Window.longestGapMs, gap);
        }
        // Nothing waiting: the speakers were down to their own buffer, or had already run out
        // (after a pause, expected)
        if (waitingMs <= 0 && !pause) {
            m_Total.ranDry++;
            m_Window.ranDry++;
        }
        for (Counters* c : {&m_Total, &m_Window}) {
            c->leastWaitingMs = c->leastWaitingMs < 0 ? waitingMs : std::min(c->leastWaitingMs, waitingMs);
        }
    }
    m_LastPacketMs = nowMs;
    m_LastNowMs = nowMs;
    m_Total.packets++;
    m_Window.packets++;
    m_Total.mostWaitingMs = std::max(m_Total.mostWaitingMs, waitingMs);
    m_Window.mostWaitingMs = std::max(m_Window.mostWaitingMs, waitingMs);
}

void Monitor::thrownAway()
{
    m_Total.thrownAway++;
    m_Window.thrownAway++;
}

void Monitor::waited()
{
    m_Total.waits++;
    m_Window.waits++;
}

std::string Monitor::describe(const Counters& c, double seconds)
{
    char line[360];
    std::snprintf(line, sizeof(line),
                  "%ld packets in %.0f s; %ld late (longest gap %.0f ms), %ld arrived with nothing queued, "
                  "%ld thrown away (too much waiting), %ld waited for room, %ld pauses; %.0f to %.0f ms queued",
                  c.packets, seconds, c.late, c.longestGapMs, c.ranDry, c.thrownAway, c.waits, c.pauses,
                  std::max(c.leastWaitingMs, 0.0), c.mostWaitingMs);
    return line;
}

std::string Monitor::report(double nowMs)
{
    if (m_WindowStartMs < 0 || nowMs - m_WindowStartMs < m_ReportEveryMs) {
        return std::string();
    }
    std::string line;
    if (m_Window.late > 0 || m_Window.ranDry > 0 || m_Window.thrownAway > 0) {
        line = describe(m_Window, (nowMs - m_WindowStartMs) / 1000.0);
    }
    m_Window = Counters();
    m_WindowStartMs = nowMs;
    return line;
}

std::string Monitor::rtpLine(unsigned audio, unsigned fec, unsigned recovered, unsigned failed, unsigned outOfOrder)
{
    char line[200];
    std::snprintf(line, sizeof(line), "RTP so far: %u audio and %u FEC packets, %u rebuilt by FEC, %u couldn't be, %u out of order",
                  audio, fec, recovered, failed, outOfOrder);
    return line;
}

std::string Monitor::summary() const
{
    if (m_FirstMs < 0) {
        return std::string();
    }
    return describe(m_Total, (m_LastNowMs - m_FirstMs) / 1000.0);
}

}
