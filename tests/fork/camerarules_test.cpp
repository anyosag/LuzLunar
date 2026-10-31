// Tests for app/fork/camerarules.h: the Mac camera's bitrate on a slow connection, which frames go,
// and what Apollo's answer to the connection means. A standalone program:
//   clang++ -std=c++17 -Iapp tests/fork/camerarules_test.cpp app/fork/camerarules.cpp

#include "fork/camerarules.h"

#include <cstdio>

using namespace CameraRules;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

// Bytes that are ms milliseconds of video at kbps
static std::size_t bytesFor(int ms, std::uint32_t kbps)
{
    return static_cast<std::size_t>(ms) * kbps / 8;
}

static void testQueuedMs()
{
    CHECK(queuedMs(0, 2500) == 0);
    CHECK(queuedMs(312500, 2500) == 1000);
    CHECK(queuedMs(1000, 0) == 0);
    CHECK(queuedMs(bytesFor(300, 5000), 5000) == 300);
}

static void testBitrate()
{
    Bitrate bitrate;
    // Nothing before START
    CHECK(!bitrate.update(1 << 20, 0));
    CHECK(bitrate.current() == 0);

    bitrate.start(5000, 0);
    CHECK(bitrate.current() == 5000 && bitrate.ceiling() == 5000);

    // A short queue changes nothing
    CHECK(!bitrate.update(bytesFor(100, 5000), 500));
    CHECK(bitrate.current() == 5000);

    // A long one: down by a third, at most once a second
    CHECK(bitrate.update(bytesFor(400, 5000), 1000));
    CHECK(bitrate.current() == 3333);
    CHECK(!bitrate.update(bytesFor(400, 3333), 1500));
    CHECK(bitrate.update(bytesFor(400, 3333), 2000));
    CHECK(bitrate.current() == 2222);
    // down to a quarter of the most at the lowest
    for (int t = 3000; t < 20000; t += 1000) {
        bitrate.update(bytesFor(900, bitrate.current()), t);
    }
    CHECK(bitrate.current() == 1250);
    CHECK(!bitrate.update(bytesFor(900, 1250), 30000));

    // A short queue for 5 s: up by a quarter, and again after another 5 s
    CHECK(!bitrate.update(0, 40000));
    CHECK(!bitrate.update(0, 44999));
    CHECK(bitrate.update(0, 45000));
    CHECK(bitrate.current() == 1562);
    CHECK(!bitrate.update(0, 46000));
    CHECK(bitrate.update(0, 50000));
    CHECK(bitrate.current() == 1952);
    // A queue in between (50-300 ms) starts the wait again
    CHECK(!bitrate.update(bytesFor(100, 1952), 51000));
    CHECK(!bitrate.update(0, 52000));
    CHECK(!bitrate.update(0, 56000));
    CHECK(bitrate.update(0, 57000));
    // never above the most
    for (int t = 60000; t < 200000; t += 5000) {
        bitrate.update(0, t);
    }
    CHECK(bitrate.current() == 5000);

    // BITRATE lowers the most, and the bitrate with it
    bitrate.limit(2000);
    CHECK(bitrate.ceiling() == 2000 && bitrate.current() == 2000);
    bitrate.limit(0);
    CHECK(bitrate.ceiling() == 2000);
    // A small most keeps the floor at the most
    Bitrate small;
    small.start(200, 0);
    CHECK(!small.update(bytesFor(900, 200), 5000));
    CHECK(small.current() == 200);
    // 720p's floor is 625 kbps
    Bitrate hd;
    hd.start(2500, 0);
    for (int t = 1000; t < 20000; t += 1000) {
        hd.update(bytesFor(900, hd.current()), t);
    }
    CHECK(hd.current() == 625);
}

static void testQueue()
{
    using V = Queue::Verdict;
    Queue queue;
    const std::uint32_t kbps = 2500;
    CHECK(queue.frame(true, 0, kbps) == V::Send);
    CHECK(queue.frame(false, bytesFor(900, kbps), kbps) == V::Send);
    // Over a second waiting: frames go until it's back under 300 ms
    CHECK(queue.frame(false, bytesFor(1100, kbps), kbps) == V::Drop);
    CHECK(queue.frame(true, bytesFor(800, kbps), kbps) == V::Drop);
    CHECK(queue.frame(false, bytesFor(400, kbps), kbps) == V::Drop);
    // then a keyframe is asked for, once, and only it goes first
    CHECK(queue.frame(false, bytesFor(200, kbps), kbps) == V::DropAndAskKeyframe);
    CHECK(queue.frame(false, bytesFor(100, kbps), kbps) == V::Drop);
    CHECK(queue.frame(true, bytesFor(100, kbps), kbps) == V::Send);
    CHECK(queue.frame(false, bytesFor(100, kbps), kbps) == V::Send);
    // A keyframe arriving just as the queue drains goes at once
    CHECK(queue.frame(false, bytesFor(1500, kbps), kbps) == V::Drop);
    CHECK(queue.frame(true, bytesFor(100, kbps), kbps) == V::Send);
    // reset() forgets dropping
    CHECK(queue.frame(false, bytesFor(1500, kbps), kbps) == V::Drop);
    queue.reset();
    CHECK(queue.frame(false, bytesFor(500, kbps), kbps) == V::Send);
}

static void testOffer()
{
    // Every permission Apollo gives today, with Camera
    CHECK(offer(true, true, 0x1FFF5F00) == Offer::Connect);
    CHECK(offer(true, true, 0x1FFF1F00) == Offer::NoPermission);
    CHECK(offer(true, false, 0x1FFF5F00) == Offer::NoCamera);
    // No answer: the connection finds out
    CHECK(offer(false, false, -1) == Offer::Connect);
    // An answer without <Permission> can't say
    CHECK(offer(true, true, -1) == Offer::Connect);
}

static void testAnswers()
{
    CHECK(answer("HTTP/1.1 101 Switching Protocols", "") == Answer::Upgraded);
    CHECK(answer("HTTP/1.1 401 Unauthorized", "permission") == Answer::NoPermission);
    CHECK(answer("HTTP/1.1 403 Forbidden", "not_streaming") == Answer::RetrySoon);
    CHECK(answer("HTTP/1.1 403 Forbidden", "") == Answer::NoPermission);
    CHECK(answer("HTTP/1.1 404 Not Found", "unsupported") == Answer::Unsupported);
    CHECK(answer("HTTP/1.1 409 Conflict", "in_use") == Answer::RetryLater);
    CHECK(answer("HTTP/1.1 500 Internal Server Error", "") == Answer::RetryLater);
    CHECK(answer("garbage", "") == Answer::RetryLater);
    CHECK(answer("", "") == Answer::RetryLater);

    CHECK(retryDelayMs(Answer::RetrySoon, 1) == 1000);
    CHECK(retryDelayMs(Answer::RetrySoon, 3) == 3000);
    CHECK(retryDelayMs(Answer::RetrySoon, 10) == 5000);
    CHECK(retryDelayMs(Answer::RetryLater, 1) == 5000);
    CHECK(retryDelayMs(Answer::RetryLater, 2) == 10000);
    CHECK(retryDelayMs(Answer::RetryLater, 3) == 20000);
    CHECK(retryDelayMs(Answer::RetryLater, 4) == 30000);
    CHECK(retryDelayMs(Answer::RetryLater, 40) == 30000);
    CHECK(retryDelayMs(Answer::RetryLater, 0) == 5000);
    CHECK(retryDelayMs(Answer::NoPermission, 1) < 0);
    CHECK(retryDelayMs(Answer::Unsupported, 1) < 0);
    CHECK(retryDelayMs(Answer::Upgraded, 1) < 0);
}

int main()
{
    testQueuedMs();
    testBitrate();
    testQueue();
    testOffer();
    testAnswers();
    if (s_Failures == 0) {
        std::printf("camerarules_test: all passed\n");
        return 0;
    }
    std::printf("camerarules_test: %d failed\n", s_Failures);
    return 1;
}
