// Tests for app/fork/micrules.*: this Mac's microphone on the PC without CoreAudio, Opus or Qt: when
// a stream asks, speakers or headphones, which microphone, what Control Center's tile says and when
// the Mac records, the frames' numbers and times, the stream's sound as stereo, and the ring it
// waits in for the voice-processing engine. A standalone program, so CI builds it without the app:
//   clang++ -std=c++17 -Iapp tests/fork/micrules_test.cpp app/fork/micrules.cpp

#include "fork/micrules.h"

#include <cmath>
#include <cstdio>
#include <vector>

using namespace MicRules;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static bool near(float a, float b)
{
    return std::fabs(a - b) < 1e-5f;
}

static void testLaunch()
{
    CHECK(launchValue(true, 1, false) == "1");
    CHECK(launchValue(true, 2, false) == "1");
    CHECK(launchValue(false, 1, false).empty());
    CHECK(launchValue(true, 0, false).empty());  // an older Apollo, or fork_mic off
    CHECK(launchValue(true, 1, true).empty());   // a multi-display stream's other window
}

static void testOutput()
{
    CHECK(classifyOutput(Transport::BuiltIn, false) == Output::Speakers);
    CHECK(classifyOutput(Transport::BuiltIn, true) == Output::Headphones);
    CHECK(classifyOutput(Transport::Bluetooth, false) == Output::Headphones);
    CHECK(classifyOutput(Transport::BluetoothLE, false) == Output::Headphones);
    CHECK(classifyOutput(Transport::Usb, false) == Output::Headphones);
    CHECK(classifyOutput(Transport::Hdmi, false) == Output::Speakers);
    CHECK(classifyOutput(Transport::DisplayPort, false) == Output::Speakers);
    CHECK(classifyOutput(Transport::AirPlay, false) == Output::Speakers);
    CHECK(classifyOutput(Transport::Unknown, false) == Output::Speakers);

    CHECK(voiceProcessedPlayback(true, Output::Speakers));
    CHECK(!voiceProcessedPlayback(true, Output::Headphones));
    CHECK(!voiceProcessedPlayback(false, Output::Speakers));
}

static void testInput()
{
    std::vector<Input> inputs = {
        { "airpods", "AirPods Pro", false },
        { "builtin", "MacBook Pro Microphone", true },
        { "usb", "USB Microphone", false },
    };
    CHECK(chooseInput("", inputs) == "builtin");         // the built-in, AirPods or not
    CHECK(chooseInput("usb", inputs) == "usb");          // the one chosen
    CHECK(chooseInput("gone", inputs) == "builtin");     // chosen, but unplugged
    CHECK(chooseInput("", { { "usb", "USB", false } }).empty());  // a Mac mini: macOS's default
    CHECK(chooseInput("", {}).empty());
}

static void testStatus()
{
    Situation s;
    CHECK(status(s) == Status::Off);
    s.settingOn = true;
    CHECK(status(s) == Status::Off);  // the stream didn't ask
    s.asked = true;
    CHECK(status(s) == Status::NeedsApollo);
    s.hostOffers = true;
    CHECK(status(s) == Status::NotOnPc);
    s.hostReady = true;
    CHECK(status(s) == Status::Standby);
    CHECK(!shouldCapture(s));
    s.hostRecording = true;
    CHECK(status(s) == Status::Live);
    CHECK(shouldCapture(s));  // macOS asks the first time
    s.access = Access::Granted;
    CHECK(shouldCapture(s));
    s.muted = true;
    CHECK(status(s) == Status::Muted);
    CHECK(!shouldCapture(s));
    s.muted = false;
    s.access = Access::Denied;
    CHECK(status(s) == Status::NoAccess);
    CHECK(!shouldCapture(s));
    s.access = Access::Granted;
    s.settingOn = false;
    CHECK(!shouldCapture(s));
}

static void testFrameClock()
{
    FrameClock clock;
    clock.startRecording(5000);
    luzmic::frame_t a = clock.next();
    luzmic::frame_t b = clock.next();
    CHECK(a.start() && !b.start());
    CHECK(a.sequence == 0 && b.sequence == 1);
    CHECK(a.time_ms == 5000 && b.time_ms == 5020);

    // A new recording: numbers go on, the time starts again from the clock, the first says so
    clock.startRecording(90000);
    luzmic::frame_t c = clock.next();
    CHECK(c.start());
    CHECK(c.sequence == 2);
    CHECK(c.time_ms == 90000);

    // Both wrap
    FrameClock wrap;
    wrap.startRecording(0xFFFFFFF0u);
    for (int i = 0; i < 70000; i++) {
        wrap.next();
    }
    luzmic::frame_t later = wrap.next();
    CHECK(later.sequence == static_cast<std::uint16_t>(70000));
    CHECK(later.time_ms == static_cast<std::uint32_t>(0xFFFFFFF0u + 70000u * 20u));
}

static void testDownmix()
{
    float stereo[] = { 0.5f, -0.25f, 0.1f, 0.2f };
    float out[4];
    downmixToStereo(stereo, 2, 2, out);
    CHECK(near(out[0], 0.5f) && near(out[1], -0.25f) && near(out[2], 0.1f) && near(out[3], 0.2f));

    // 5.1: the centre into both, each surround into its side, LFE nowhere
    float surround[] = { 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f };
    downmixToStereo(surround, 6, 1, out);
    CHECK(out[0] > 0 && near(out[0], out[1]));
    float lfe[] = { 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f };
    downmixToStereo(lfe, 6, 1, out);
    CHECK(near(out[0], 0) && near(out[1], 0));
    float leftSurround[] = { 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f };
    downmixToStereo(leftSurround, 6, 1, out);
    CHECK(out[0] > 0 && near(out[1], 0));

    // Everything at full scale stays within it
    float loud[8] = { 1, 1, 1, 1, 1, 1, 1, 1 };
    downmixToStereo(loud, 8, 1, out);
    CHECK(out[0] <= 1.0f + 1e-5f && out[1] <= 1.0f + 1e-5f);
    downmixToStereo(loud, 6, 1, out);
    CHECK(out[0] <= 1.0f + 1e-5f && out[1] <= 1.0f + 1e-5f);

    // Mono stays centred
    float mono[] = { 0.3f };
    downmixToStereo(mono, 1, 1, out);
    CHECK(near(out[0], 0.3f) && near(out[1], 0.3f));
}

static void testRing()
{
    PcmRing ring(8);
    float left[16];
    float right[16];
    CHECK(ring.pull(left, right, 4) == 0);
    CHECK(left[0] == 0 && right[3] == 0);

    float in[12];
    for (int i = 0; i < 6; i++) {
        in[2 * i] = static_cast<float>(i);
        in[2 * i + 1] = static_cast<float>(-i);
    }
    ring.push(in, 6);
    CHECK(ring.queued() == 6);
    CHECK(ring.pull(left, right, 4) == 4);
    CHECK(left[0] == 0 && left[3] == 3 && right[3] == -3);

    // Past the capacity, the oldest go
    ring.push(in, 6);  // 2 left + 6 = 8: full
    ring.push(in, 3);  // 3 more: the 3 oldest go
    CHECK(ring.queued() == 8);
    CHECK(ring.pull(left, right, 10) == 8);
    // What's left: the first push's two (4, 5) and the second's first (0) went; then 1..5, 0..2
    CHECK(left[0] == 1 && left[4] == 5 && left[5] == 0);
    CHECK(left[7] == 2 && right[7] == -2);
    CHECK(left[8] == 0 && left[9] == 0);  // dry: silence

    // Far more than fits at once: only the newest
    float big[40];
    for (int i = 0; i < 20; i++) {
        big[2 * i] = static_cast<float>(i);
        big[2 * i + 1] = 0;
    }
    ring.push(big, 20);
    CHECK(ring.queued() == 8);
    ring.pull(left, right, 8);
    CHECK(left[0] == 12 && left[7] == 19);

    ring.push(in, 3);
    ring.clear();
    CHECK(ring.queued() == 0);
}

// Frames numbered from start, in the left channel; the right is their negative
static void pushNumbered(PcmRing& ring, int start, int frames)
{
    std::vector<float> in(static_cast<size_t>(frames) * 2);
    for (int i = 0; i < frames; i++) {
        in[2 * static_cast<size_t>(i)] = static_cast<float>(start + i);
        in[2 * static_cast<size_t>(i) + 1] = -static_cast<float>(start + i);
    }
    ring.push(in.data(), frames);
}

static void testRingCushion()
{
    float left[16];
    float right[16];

    // Nothing plays until the cushion is full
    PcmRing ring(16, 4);
    pushNumbered(ring, 0, 3);
    CHECK(ring.pull(left, right, 2) == 0);
    CHECK(left[0] == 0 && left[1] == 0 && ring.queued() == 3);
    pushNumbered(ring, 3, 3);   // 6 waiting
    CHECK(ring.pull(left, right, 4) == 4);
    CHECK(left[0] == 0 && left[3] == 3 && right[3] == -3);

    // Running dry: what's left, then silence, and the cushion fills again before it plays
    CHECK(ring.pull(left, right, 4) == 2);
    CHECK(left[0] == 4 && left[1] == 5 && left[2] == 0 && left[3] == 0);
    pushNumbered(ring, 6, 2);
    CHECK(ring.pull(left, right, 1) == 0);
    pushNumbered(ring, 8, 2);   // 4 waiting
    CHECK(ring.pull(left, right, 4) == 4);
    CHECK(left[0] == 6 && left[3] == 9);

    // clear() empties the cushion too
    pushNumbered(ring, 0, 8);
    ring.clear();
    pushNumbered(ring, 0, 2);
    CHECK(ring.pull(left, right, 2) == 0);

    // The capacity caps the cushion at half of it
    PcmRing small(8, 100);
    pushNumbered(small, 0, 4);
    CHECK(small.pull(left, right, 4) == 4);

    // Coming up short while playing is counted; waiting for the cushion isn't
    PcmRing counted(16, 4);
    pushNumbered(counted, 0, 3);
    counted.pull(left, right, 4);           // filling the cushion
    CHECK(counted.stats().shortPulls == 0);
    pushNumbered(counted, 3, 3);            // 6 waiting
    counted.pull(left, right, 4);           // plays 4
    counted.pull(left, right, 4);           // 2, then silence: short
    counted.pull(left, right, 4);           // nothing: filling again, not counted twice
    CHECK(counted.stats().shortPulls == 1);
    pushNumbered(counted, 0, 20);           // 4 more than fit
    CHECK(counted.stats().overflowFrames == 4);

    // The real sizes: 20 ms of cushion within 60 ms
    CHECK(k_RingPrimeFrames == 960 && k_RingFrames == 2880 && k_RingPrimeFrames * 2 <= k_RingFrames);
}

static void testRingDrift()
{
    std::vector<float> left(1000);
    std::vector<float> right(1000);

    // The PC runs ahead (over twice the cushion waiting): the 1000th frame played takes its next one along
    PcmRing ahead(4000, 100);
    pushNumbered(ahead, 0, 1500);
    CHECK(ahead.pull(left.data(), right.data(), 1000) == 1000);
    CHECK(left[0] == 0 && left[999] == 999);
    CHECK(ahead.queued() == 1500 - 1001);
    CHECK(ahead.pull(left.data(), right.data(), 1) == 1 && left[0] == 1001);

    // The speakers run ahead (under half the cushion waiting): the 1000th frame plays twice
    PcmRing behind(4000, 100);
    pushNumbered(behind, 0, 1040);
    CHECK(behind.pull(left.data(), right.data(), 1000) == 1000);
    CHECK(left[998] == 998 && left[999] == 999);
    CHECK(behind.queued() == 1040 - 999);
    CHECK(behind.pull(left.data(), right.data(), 1) == 1 && left[0] == 999 && right[0] == -999);

    // Near the cushion: nothing left out or repeated
    PcmRing steady(4000, 100);
    pushNumbered(steady, 0, 1150);
    CHECK(steady.pull(left.data(), right.data(), 1000) == 1000);
    CHECK(steady.queued() == 150);
    CHECK(steady.pull(left.data(), right.data(), 1) == 1 && left[0] == 1000);

    // Without a cushion (the tests above, and anything else): never
    PcmRing plain(4000);
    pushNumbered(plain, 0, 1500);
    CHECK(plain.pull(left.data(), right.data(), 1000) == 1000);
    CHECK(plain.queued() == 500);
}

int main()
{
    testLaunch();
    testOutput();
    testInput();
    testStatus();
    testFrameClock();
    testDownmix();
    testRing();
    testRingCushion();
    testRingDrift();
    if (s_Failures) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("micrules: all checks passed\n");
    return 0;
}
