#pragma once

#include <string>

// [fork] What LuzLunar knows about changing its stream's bitrate on the PC while streaming
// (bitrateclient.*), from the PC's answers to serverinfo and /actions/bitrate. Free of Qt, so tests
// can build it alone (tests/fork/bitratestate_test.cpp).
//
// An Apollo with "known" in its answers says as soon as its encoder exists whether it can change the
// bitrate. An older one says live:true until a change has been tried, then live:false, so a change
// it took (202) is asked about again until it's applied or refused.
namespace BitrateState
{
    // Why the bitrate can't change during the stream
    enum class Why {
        None,
        NotApollo,      // the PC isn't LuzLunar's Apollo
        OlderApollo,    // an Apollo from before live bitrate changes
        OffInApollo,    // fork_adaptive_bitrate is off
        Encoder,        // the PC's encoder can't (live:false)
        NoPermission,   // this Mac may not view the PC's streams
        NotStreaming,   // Apollo doesn't see this stream
    };

    struct State {
        bool known = false;     // the PC said whether it can: Apollo's "known", or a refusal
        bool live = true;       // it can, as far as known
        Why why = Why::None;
        int minKbps = 0;        // what a request can set, in the client's units; 0 while unknown
        int maxKbps = 0;
        int targetKbps = 0;     // the bitrate the PC runs at or is changing to; 0 while unknown
        bool pending = false;   // a change waits for the PC's encode thread
    };

    // serverinfo's answer: whether there was one, Apollo's permissions (-1 for a PC that isn't
    // Apollo) and LuzBitrate
    inline void serverInfo(State& state, bool answered, long long permissions, const std::string& luzBitrate)
    {
        if (!answered || luzBitrate == "1") {
            // Without an answer, /actions/bitrate says
            return;
        }
        state.known = true;
        state.live = false;
        state.why = permissions < 0 ? Why::NotApollo : luzBitrate.empty() ? Why::OlderApollo : Why::OffInApollo;
    }

    // An answer to GET or POST /actions/bitrate, as parsed
    struct Reply {
        int httpStatus = 0;     // 0: no answer
        bool hasStatus = false; // the body had the status fields
        int target = 0;
        int min = 0;
        int max = 0;
        bool live = true;
        bool hasKnown = false;  // an Apollo that says at once whether its encoder can change
        bool known = false;
        bool pending = false;
    };

    enum class Next {
        Done,       // nothing more to ask about this
        AskAgain,   // ask again in a moment: a change waits, or the encoder hasn't said yet
    };

    inline Next apply(State& state, const Reply& reply)
    {
        switch (reply.httpStatus) {
        case 0:
            return Next::Done;
        case 401:
            state = State { true, false, Why::NoPermission };
            return Next::Done;
        case 403:
            state = State { true, false, Why::NotStreaming };
            return Next::Done;
        case 404:
            state = State { true, false, Why::OffInApollo };
            return Next::Done;
        case 200:
        case 202:
        case 409:
            break;
        default:
            // A request it didn't understand changes nothing
            return Next::Done;
        }

        if (!reply.hasStatus) {
            // 409 without a status: this stream has nothing to change
            if (reply.httpStatus == 409) {
                state.known = true;
                state.live = false;
                state.why = Why::Encoder;
            }
            return Next::Done;
        }

        state.minKbps = reply.min;
        state.maxKbps = reply.max;
        if (reply.target > 0) {
            state.targetKbps = reply.target;
        }
        state.pending = reply.pending;
        state.live = reply.live;
        state.why = reply.live ? Why::None : Why::Encoder;
        // A refusal is an answer, even from an Apollo that doesn't say "known"
        state.known = reply.hasKnown ? reply.known || !reply.live : !reply.live;

        if (reply.live && (reply.pending || (reply.hasKnown && !reply.known))) {
            return Next::AskAgain;
        }
        return Next::Done;
    }
}
