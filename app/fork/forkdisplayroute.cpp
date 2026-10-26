#include "forkdisplayroute.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ForkDisplayRoute
{

namespace
{
    std::string ms(double value)
    {
        char buffer[32];
        std::snprintf(buffer, sizeof(buffer), "%.0f ms", std::max(0.0, value));
        return buffer;
    }

    // Waiting for the next refresh averages about half a refresh, plus presenting: 0.75 of one
    double frameWaitMs(int refreshHz)
    {
        return 0.75 * 1000.0 / (refreshHz > 0 ? refreshHz : 60);
    }

    bool usable(const Probe& probe)
    {
        return probe.count > 0 && probe.failures == 0 && probe.medianMs >= 0 &&
               probe.medianMs <= k_DirectMaxMedianMs && probe.maxMs <= k_DirectMaxWorstMs;
    }

    // Why the iMac can't stream straight from the PC; empty if it can. best is set to the fastest
    // usable probe.
    std::string ineligible(const Facts& facts, const Probe*& best)
    {
        best = nullptr;
        if (!facts.bridge) {
            return "DisplayExtend's Host isn't running, or is too old to hand the iMac over";
        }
        if (!facts.imacConnected) {
            return "the iMac isn't connected to DisplayExtend";
        }
        if (!facts.directSupported) {
            return "the iMac's DisplayExtend can't stream from the PC yet; update it from DisplayExtend's Host";
        }
        if (!facts.moonlightVerified) {
            return "Moonlight on the iMac is missing or failed its signature check";
        }
        if (!facts.paired) {
            return "the iMac isn't paired with this PC; use Set up the iMac in Settings";
        }

        const Probe* fastestReachable = nullptr;
        for (const Probe& probe : facts.imacToPc) {
            if (usable(probe) && (best == nullptr || probe.medianMs < best->medianMs)) {
                best = &probe;
            }
            if (probe.medianMs >= 0 && probe.failures < probe.count &&
                    (fastestReachable == nullptr || probe.medianMs < fastestReachable->medianMs)) {
                fastestReachable = &probe;
            }
        }
        if (best != nullptr) {
            return {};
        }
        if (fastestReachable == nullptr) {
            return "the iMac can't reach the PC";
        }
        if (fastestReachable->failures > 0) {
            return "the iMac's connection to the PC drops connects";
        }
        return "the iMac's connection to the PC is too slow (" + ms(fastestReachable->medianMs) + ", worst " +
               ms(fastestReachable->maxMs) + ")";
    }
}

double median(std::vector<double> values)
{
    if (values.empty()) {
        return -1;
    }
    std::sort(values.begin(), values.end());
    size_t middle = values.size() / 2;
    return values.size() % 2 == 1 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
}

Decision decide(Setting setting, const Facts& facts)
{
    Decision decision;

    if (setting == Setting::ViaMac) {
        decision.reason = "set to go through this Mac";
        return decision;
    }

    const Probe* best = nullptr;
    std::string why = ineligible(facts, best);
    if (!why.empty()) {
        decision.reason = setting == Setting::Direct ? "can't go straight from the PC: " + why : why;
        return decision;
    }

    double displayExtendMs = facts.displayExtendFrames >= k_MinDisplayExtendFrames && facts.displayExtendP50Ms > 0
                                 ? facts.displayExtendP50Ms
                                 : k_DefaultDisplayExtendMs;
    double macOneWay = facts.macToPc.medianMs >= 0 ? facts.macToPc.medianMs / 2 : 0;

    decision.address = best->address;
    decision.estDirectMs = best->medianMs / 2 + k_ImacDecodeMs + frameWaitMs(facts.imacRefreshHz);
    decision.estViaMs = macOneWay + k_MacDecodeMs + frameWaitMs(facts.virtualRefreshHz) + displayExtendMs;

    if (setting == Setting::Direct) {
        decision.route = Route::Direct;
        decision.reason = "set to go straight from the PC";
    }
    else if (decision.estDirectMs <= decision.estViaMs + k_DirectBiasMs) {
        decision.route = Route::Direct;
        decision.reason = "faster";
    }
    else {
        decision.reason = "faster";
    }
    return decision;
}

std::string describe(const Decision& decision, const Facts& facts)
{
    std::string text = decision.route == Route::Direct ? "straight from the PC" : "through this Mac";
    if (decision.estDirectMs < 0) {
        return text + " (" + decision.reason + ")";
    }

    const Probe* best = nullptr;
    for (const Probe& probe : facts.imacToPc) {
        if (probe.address == decision.address) {
            best = &probe;
        }
    }

    double first = decision.route == Route::Direct ? decision.estDirectMs : decision.estViaMs;
    double second = decision.route == Route::Direct ? decision.estViaMs : decision.estDirectMs;
    text += " (about " + ms(first) + " vs " + ms(second);
    if (best != nullptr) {
        text += "; iMac→PC " + ms(best->medianMs);
    }
    if (facts.macToPc.medianMs >= 0) {
        text += ", Mac→PC " + ms(facts.macToPc.medianMs);
    }
    bool measured = facts.displayExtendFrames >= k_MinDisplayExtendFrames && facts.displayExtendP50Ms > 0;
    text += ", DisplayExtend " + ms(measured ? facts.displayExtendP50Ms : k_DefaultDisplayExtendMs);
    if (!measured) {
        text += " assumed";
    }
    if (decision.reason != "faster") {
        text += "; " + decision.reason;
    }
    text += ")";
    return text;
}

}
