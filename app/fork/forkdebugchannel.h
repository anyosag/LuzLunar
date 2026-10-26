#pragma once

#include <QString>

#include <cstdint>
#include <functional>

// [fork] A local socket through which tools on this Mac (scripts/fork/luz-debug.py) follow LuzLunar
// while it runs, streaming or not: its state and log file, a while at a more detailed log level, and
// marks in the log. ~/Library/Application Support/LuzLunar/debug.sock, mode 0600, for this user
// only. One JSON request per connection, one JSON line back:
//   {"op": "status"}
//   {"op": "level", "level": "debug" | "verbose" | "info", "minutes": 30}
//   {"op": "mark", "text": "..."}
// Every reply carries the state, {"ok", "app", "version", "pid", "logFile", "logBytes", "logLimit",
// "level", "secondsLeft", "streaming"}, and "error" when not ok. Served from a thread of its own,
// since the Qt loop waits while a stream runs. Only the main process serves; helpers don't.
namespace ForkDebugChannel
{
    // Lets the channel's thread change SDL's log priorities: SDL2 allocates a category's entry the
    // first time its priority is set, so every category gets one now, at its normal priority. Call
    // from the main thread after SDL_Init, before other threads log through SDL.
    void pinLogPriorities();

    // Starts serving, unless another LuzLunar already does. logBytes reports how much the log
    // holds; at logLimit it stops growing.
    void start(const QString& logFile, std::function<uint64_t()> logBytes, uint64_t logLimit);

    // Stops serving and puts the log level back; harmless if not started
    void stop();
}
