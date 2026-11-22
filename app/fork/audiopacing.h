#pragma once

// [fork] How SDL's audio renderer paces the stream's sound, without SDL, so tests can build it alone.
// Upstream played each packet as it came, with nothing kept in reserve: the device takes sound in
// 15 ms chunks, so a packet a few ms late (Wi-Fi behind the video's bursts, a lost packet waiting
// for FEC) left part of a chunk silent, a tick; and when sound backed up, the decoder was held
// until the queue passed 30 ms, then packets were thrown away, a click. Nothing matched the PC's
// clock to the speakers', so the queue drifted to one of those. Here:
// - the device plays once targetMs wait (and again after the PC paused, sending nothing while
//   silent), so a late packet takes from the reserve instead of leaving a gap
// - away from the target (under lowMs or over highMs), one frame in driftEveryFrames is played
//   twice or left out, which isn't heard and holds the reserve against the clocks' drift
// - a packet is thrown away only past capMs waiting, a burst after a long stall, and the decoder
//   is never held
namespace AudioPacing
{
    struct Settings {
        double targetMs = 30;
        double lowMs = 15;
        double highMs = 50;
        double capMs = 120;
        double pauseMs = 500;       // AudioHealth's pause: the PC sent nothing
        int driftEveryFrames = 1000;
    };

    struct Decision {
        bool start = false;     // unpause the device after queueing this packet: the reserve is there
        bool hold = false;      // pause the device before queueing this one: build the reserve again
        bool drop = false;      // too much waiting: throw this packet away
        int adjust = 0;         // +1: play this packet's last frame twice; -1: leave it out
    };

    class Pacer
    {
    public:
        Pacer(int sampleRate, Settings settings = Settings());

        // A packet of frames, at nowMs (a steady clock), with queuedMs waiting for the device
        Decision packet(double nowMs, double queuedMs, int frames);

        bool playing() const { return m_Playing; }

    private:
        Settings m_Settings;
        int m_SampleRate;
        bool m_Playing = false;
        double m_LastMs = -1;
        int m_SinceAdjust = 0;
    };
}
