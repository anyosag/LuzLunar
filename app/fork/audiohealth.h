#pragma once

#include <string>

// [fork] What the stream's sound went through on its way to the speakers, for the log: plain C++,
// no SDL or Qt, so tests can build it alone. An audio renderer reports each decoded packet as it
// arrives (with how much sound was waiting for the speakers then), each packet it threw away
// because too much was waiting, and each time it had to wait for room. Every so often, and when
// the stream ends, it gives a line saying what happened, so a crackle can be told apart:
// - late packets (a gap between packets longer than the speakers' buffer, with nothing waiting):
//   the network, or the PC, delivered the sound late, and the speakers played silence
// - thrown away: sound backed up and packets were dropped, each a click
// - neither, while crackles are heard: the crackle is in the sound the PC sent
namespace AudioHealth
{
    // A gap this long isn't a late packet: the PC may send nothing while it's silent
    constexpr double k_PauseMs = 500;

    struct Counters {
        long packets = 0;
        long late = 0;          // came more than lateMs after the one before (and less than k_PauseMs)
        long pauses = 0;        // k_PauseMs or more after the one before: the PC sent nothing (silence)
        // Arrived with nothing queued for the speakers (after the first). The device takes sound in
        // chunks of its buffer, so now and then is normal; often, with late packets, means gaps
        long ranDry = 0;
        long thrownAway = 0;    // dropped because too much was waiting
        long waits = 0;         // had to wait for room
        double longestGapMs = 0;   // among the late, not the pauses
        double mostWaitingMs = 0;
        double leastWaitingMs = -1;     // after the first packet; -1 before
    };

    class Monitor
    {
    public:
        // lateMs: a gap longer than this between packets counts as late (the speakers' buffer, so
        // the speakers may have run out); reportEveryMs: how often report() may give a line
        explicit Monitor(double lateMs, double reportEveryMs = 10000);

        // A decoded packet, at nowMs (any steady clock), with waitingMs of sound waiting for the
        // speakers before it's added
        void packet(double nowMs, double waitingMs);
        void thrownAway();
        void waited();

        // A line for the log once reportEveryMs have passed since the last one and something
        // happened in that time (late, ran dry or thrown away); empty otherwise
        std::string report(double nowMs);

        // The whole stream, for its end; empty before the first packet
        std::string summary() const;

        const Counters& total() const { return m_Total; }

    private:
        static std::string describe(const Counters& counters, double seconds);

        double m_LateMs;
        double m_ReportEveryMs;
        double m_FirstMs = -1;
        double m_LastPacketMs = -1;
        double m_WindowStartMs = -1;
        double m_LastNowMs = -1;
        Counters m_Total;
        Counters m_Window;
    };
}
