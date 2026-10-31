#pragma once

#include <QString>

#include <Limelight.h>

#include "micrules.h"

class IAudioRenderer;
class NvComputer;
union SDL_Event;

// [fork] This Mac's microphone on the PC. "Use this Mac's microphone on the PC" in Settings › Audio,
// with an Apollo whose /serverinfo says <LuzMic>1: the stream launches with luzMic=1, Apollo makes
// the Steam Streaming Microphone Windows' default recording device, and says (luzmic.h's STATE) when
// an app on the PC records. Only then does this Mac record: 20 ms Opus frames, sent as input packets
// (LiSendForkInputPacket(), unreliable) on their own channel. From the built-in microphone unless
// Settings chose another, so AirPods keep their sound.
// - On headphones the stream's sound stays with SDL's renderer, untouched; the microphone records
//   alone.
// - On speakers the stream's sound plays through the microphone's own AVAudioEngine
//   (mac/mic_mac.mm), so while it records, voice processing cancels the echo of the game.
// Control Center's Microphone mutes it for the stream, and a dot beside the notch shows while it's
// live.
namespace ForkMic
{
    // Session, on the main thread before the stream starts: whether to ask, from the setting and
    // what the PC's Apollo can do; helperWindow: a multi-display stream's other window, which never
    // does
    void prepare(NvComputer* computer, bool helperWindow);

    // On the thread that starts the stream: what the launch adds ("&luzMic=1"), or nothing
    QString launchArgument();

    // Session, around the stream's connection (with ForkHostMessages): before LiStartConnection(),
    // and after LiStopConnection()
    void connectionStarting();
    void connectionStopped();

    // Session::createAudioRenderer(), on the audio thread: the renderer that plays the stream through
    // the microphone's engine, while the stream asked and this Mac plays on speakers; nullptr for
    // the usual one
    IAudioRenderer* createAudioRenderer(const OPUS_MULTISTREAM_CONFIGURATION* opusConfig);

    // Session::arDecodeAndPlaySample(): the renderer no longer suits where this Mac plays
    // (headphones came or went), or the engine failed: it's made again
    bool rendererStale(IAudioRenderer* renderer);

    // Control Center's Microphone and the notch's dot
    MicRules::Status status();
    bool muted();
    void setMuted(bool muted);
    bool live();

    // The status changed: the stream's event loop shows it on the bar
    bool isStatusEvent(const SDL_Event& event);
}
