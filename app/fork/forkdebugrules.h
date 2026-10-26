#pragma once

// [fork] The debug channel's rules, apart from sockets, SDL and Qt (forkdebugchannel.h): the log
// levels it takes, SDL's priority for a category at each, how long a level lasts, and marks.
// Header-only, so tests/fork/debugrules_test.cpp builds it on its own.

#include <optional>
#include <string>
#include <string_view>

namespace ForkDebugRules
{
    // What the app logs normally, then more detail
    enum class Level { Info, Debug, Verbose };

    // SDL2's priorities (SDL_LogPriority), kept free of SDL for the tests
    constexpr int k_SdlVerbose = 1;
    constexpr int k_SdlDebug = 2;

    // A changed level lasts this many minutes unless the request says, and at most
    constexpr int k_DefaultMinutes = 30;
    constexpr int k_MaxMinutes = 240;

    // A mark's text, at most
    constexpr size_t k_MaxMark = 200;

    // "configured" is "info", as Apollo's /actions/log names it
    inline std::optional<Level> parseLevel(std::string_view name)
    {
        if (name == "info" || name == "configured") {
            return Level::Info;
        }
        if (name == "debug") {
            return Level::Debug;
        }
        if (name == "verbose") {
            return Level::Verbose;
        }
        return std::nullopt;
    }

    inline const char* levelName(Level level)
    {
        switch (level) {
        case Level::Debug:
            return "debug";
        case Level::Verbose:
            return "verbose";
        case Level::Info:
            break;
        }
        return "info";
    }

    // SDL's priority for a category whose normal priority is `normal`: only ever more detail
    inline int sdlPriority(Level level, int normal)
    {
        switch (level) {
        case Level::Debug:
            return normal < k_SdlDebug ? normal : k_SdlDebug;
        case Level::Verbose:
            return k_SdlVerbose;
        case Level::Info:
            break;
        }
        return normal;
    }

    // The minutes a request asks for: the default when absent, nullopt when out of range
    inline std::optional<int> minutes(bool given, double value)
    {
        if (!given) {
            return k_DefaultMinutes;
        }
        if (value != static_cast<int>(value) || value < 1 || value > k_MaxMinutes) {
            return std::nullopt;
        }
        return static_cast<int>(value);
    }

    // A mark's text as it goes in the log: one line, control characters as spaces, cut to
    // k_MaxMark bytes without splitting a UTF-8 character
    inline std::string cleanMark(std::string_view text)
    {
        std::string out;
        for (char c : text) {
            out.push_back(static_cast<unsigned char>(c) < 0x20 || c == 0x7F ? ' ' : c);
        }
        if (out.size() > k_MaxMark) {
            size_t end = k_MaxMark;
            while (end > 0 && (static_cast<unsigned char>(out[end]) & 0xC0) == 0x80) {
                end--;
            }
            out.resize(end);
        }
        return out;
    }
}
