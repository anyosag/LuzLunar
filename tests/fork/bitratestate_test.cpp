// Unit tests for app/fork/bitratestate.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/bitratestate_test.cpp
#include "fork/bitratestate.h"

#include <cstdio>

using namespace BitrateState;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Reply status(int http, int target, bool live, bool pending, int knownState = -1)
{
    Reply reply;
    reply.httpStatus = http;
    reply.hasStatus = true;
    reply.target = target;
    reply.min = 1000;
    reply.max = 25000;
    reply.live = live;
    reply.pending = pending;
    reply.hasKnown = knownState >= 0;
    reply.known = knownState > 0;
    return reply;
}

static void testServerInfo()
{
    State state;
    serverInfo(state, true, 0x7fffffff, "1");
    CHECK(state.live && !state.known && state.why == Why::None);

    serverInfo(state, false, -1, "");
    CHECK(state.live && !state.known);      // no answer: /actions/bitrate says

    State notApollo;
    serverInfo(notApollo, true, -1, "");
    CHECK(!notApollo.live && notApollo.known && notApollo.why == Why::NotApollo);
    State older;
    serverInfo(older, true, 0x7fffffff, "");
    CHECK(older.why == Why::OlderApollo);
    State off;
    serverInfo(off, true, 0x7fffffff, "0");
    CHECK(off.why == Why::OffInApollo);
}

static void testApolloThatTellsAtOnce()
{
    // Before the encoder exists: live is a guess, ask again
    State state;
    CHECK(apply(state, status(200, 20000, true, false, 0)) == Next::AskAgain);
    CHECK(state.live && !state.known && state.targetKbps == 20000 && state.maxKbps == 25000);

    // An encoder that can
    CHECK(apply(state, status(200, 20000, true, false, 1)) == Next::Done);
    CHECK(state.live && state.known);

    // A change taken, then applied
    CHECK(apply(state, status(202, 15000, true, true, 1)) == Next::AskAgain);
    CHECK(state.pending && state.targetKbps == 15000);
    CHECK(apply(state, status(200, 15000, true, false, 1)) == Next::Done);
    CHECK(!state.pending);

    // An encoder that can't, said at once
    State fixed;
    CHECK(apply(fixed, status(200, 20000, false, false, 1)) == Next::Done);
    CHECK(!fixed.live && fixed.known && fixed.why == Why::Encoder);
}

static void testOlderApollo()
{
    // live:true and no "known" until a change is tried
    State state;
    CHECK(apply(state, status(200, 20000, true, false)) == Next::Done);
    CHECK(state.live && !state.known);

    // The first change is taken (202), then the encode thread finds it can't
    CHECK(apply(state, status(202, 15000, true, true)) == Next::AskAgain);
    CHECK(apply(state, status(200, 15000, false, false)) == Next::Done);
    CHECK(!state.live && state.known && state.why == Why::Encoder);
    CHECK(state.targetKbps == 15000);

    // From then on, 409 with the status
    CHECK(apply(state, status(409, 15000, false, false)) == Next::Done);
    CHECK(!state.live && state.why == Why::Encoder);
}

static void testRefusals()
{
    State state;
    Reply reply;
    reply.httpStatus = 401;
    apply(state, reply);
    CHECK(!state.live && state.why == Why::NoPermission);
    reply.httpStatus = 403;
    apply(state, reply);
    CHECK(state.why == Why::NotStreaming);
    reply.httpStatus = 404;
    apply(state, reply);
    CHECK(state.why == Why::OffInApollo);

    // 409 without a status: nothing to change on this stream
    State none;
    reply.httpStatus = 409;
    apply(none, reply);
    CHECK(!none.live && none.why == Why::Encoder);

    // No answer, or a bad request, changes nothing
    State kept;
    kept.targetKbps = 18000;
    reply.httpStatus = 0;
    CHECK(apply(kept, reply) == Next::Done);
    reply.httpStatus = 400;
    apply(kept, reply);
    CHECK(kept.live && kept.targetKbps == 18000);
}

int main()
{
    testServerInfo();
    testApolloThatTellsAtOnce();
    testOlderApollo();
    testRefusals();

    if (s_Failures == 0) {
        std::printf("bitratestate: all tests passed\n");
        return 0;
    }
    std::printf("bitratestate: %d failure(s)\n", s_Failures);
    return 1;
}
