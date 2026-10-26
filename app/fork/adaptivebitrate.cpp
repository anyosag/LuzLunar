#include "adaptivebitrate.h"

#include <chrono>
#include <mutex>

#include "SDL_compat.h"
#include "bitrateclient.h"
#include "streamstats.h"

struct AdaptiveBitrate::Shared
{
    Shared(std::shared_ptr<BitrateClient> client, int chosenKbps, bool hdr, int startKbps)
        : client(std::move(client)),
          controller(chosenKbps, hdr, startKbps)
    {
    }

    std::shared_ptr<BitrateClient> client;
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();

    // The decode thread's alone
    BitrateRules::Controller controller;

    // What the decode thread copies out of it after each tick, for state()
    mutable std::mutex mutex;
    State state;
};

namespace
{
    double secondsSince(std::chrono::steady_clock::time_point start)
    {
        return std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    }
}

AdaptiveBitrate::AdaptiveBitrate(std::shared_ptr<BitrateClient> client, int chosenKbps, bool hdr, int startKbps)
    : m_Shared(std::make_shared<Shared>(client, chosenKbps, hdr, startKbps))
{
    m_Shared->state.chosenKbps = chosenKbps;
    m_Shared->state.currentKbps = m_Shared->controller.currentKbps();

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Adaptive bitrate: between %d and %d kbps, from %d kbps",
                m_Shared->controller.floorKbps(), chosenKbps, m_Shared->controller.currentKbps());

    // Never above the user's own: down to it at once from a bitrate raised by hand
    if (startKbps > chosenKbps) {
        client->request(chosenKbps);
    }

    std::shared_ptr<Shared> shared = m_Shared;
    ForkStreamStats::setBitrateListener([shared](const ForkStreamStats::Snapshot& stats) {
        // The decode thread, about once a second
        if (!shared->client->state().live) {
            return;
        }

        BitrateRules::Sample sample;
        sample.seconds = secondsSince(shared->start);
        sample.dropPercent = stats.dropPercent;
        sample.lostFrames = stats.droppedFrames;
        sample.rttMs = stats.rttMs;
        bool suggestLowerBitrate;
        sample.poor = ForkStreamStats::connectionPoor(&suggestLowerBitrate);

        int previous = shared->controller.currentKbps();
        uint32_t previousBase = shared->controller.baseRttMs();
        int kbps = shared->controller.tick(sample);
        if (previousBase > 0 && shared->controller.baseRttMs() > previousBase) {
            // Only a route that got slower raises it
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Adaptive bitrate: the route got slower, base %u ms (was %u ms)",
                        shared->controller.baseRttMs(), previousBase);
        }
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            shared->state.currentKbps = shared->controller.currentKbps();
            shared->state.lastChange = shared->controller.lastChange();
        }
        if (kbps == 0) {
            return;
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Adaptive bitrate: %d -> %d kbps (%.1f%% of frames lost, %u ms, base %u ms%s)",
                    previous, kbps, sample.dropPercent, sample.rttMs, shared->controller.baseRttMs(),
                    sample.poor ? ", poor connection" : "");
        shared->client->request(kbps);
    });
}

AdaptiveBitrate::~AdaptiveBitrate()
{
    // No listener runs after this returns; the bitrate stays where it got to
    ForkStreamStats::setBitrateListener(nullptr);
}

AdaptiveBitrate::State AdaptiveBitrate::state() const
{
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    State state = m_Shared->state;
    if (state.lastChange.reason != BitrateRules::Reason::None) {
        state.changeAgoSeconds = secondsSince(m_Shared->start) - state.lastChange.seconds;
    }
    return state;
}
