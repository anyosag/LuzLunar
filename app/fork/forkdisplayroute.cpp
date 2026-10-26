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
            return std::to_string(fastestReachable->failures) + " of " + std::to_string(fastestReachable->count) +
                   " connects from the iMac to the PC failed";
        }
        return "the iMac's connection to the PC is too slow (" + ms(fastestReachable->medianMs) + ", worst " +
               ms(fastestReachable->maxMs) + ")";
    }
}

Probe combine(const std::vector<Probe>& rounds)
{
    Probe out;
    std::vector<double> medians;
    for (const Probe& round : rounds) {
        if (out.address.empty()) {
            out.address = round.address;
        }
        out.count += round.count;
        out.failures += round.failures;
        if (round.medianMs >= 0) {
            medians.push_back(round.medianMs);
            out.maxMs = std::max(out.maxMs, round.maxMs);
        }
    }
    out.medianMs = median(medians);
    if (medians.empty()) {
        out.maxMs = -1;
    }
    return out;
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

    bool measured = facts.displayExtendFrames >= k_MinDisplayExtendFrames && facts.displayExtendP50Ms > 0;
    double displayExtendMs = measured ? facts.displayExtendP50Ms : k_DefaultDisplayExtendMs;
    double displayExtendWorstMs = measured && facts.displayExtendP95Ms > 0 ? facts.displayExtendP95Ms : k_DefaultDisplayExtendWorstMs;
    double macOneWay = facts.macToPc.medianMs >= 0 ? facts.macToPc.medianMs / 2 : 0;
    double macWorstOneWay = facts.macToPc.maxMs >= 0 ? facts.macToPc.maxMs / 2 : 0;

    // Through this Mac once its connects were timed, also when the iMac can't go straight from
    // the PC, so the launch screen can show it
    if (facts.macToPc.medianMs >= 0) {
        decision.estViaMs = macOneWay + k_MacDecodeMs + frameWaitMs(facts.virtualRefreshHz) + displayExtendMs;
        decision.estViaWorstMs = macWorstOneWay + k_MacDecodeMs + frameWaitMs(facts.virtualRefreshHz) + displayExtendWorstMs;
    }

    const Probe* best = nullptr;
    std::string why = ineligible(facts, best);
    if (!why.empty()) {
        decision.reason = setting == Setting::Direct ? "can't go straight from the PC: " + why : why;
        return decision;
    }

    decision.address = best->address;
    decision.estDirectMs = best->medianMs / 2 + k_ImacDecodeMs + frameWaitMs(facts.imacRefreshHz);
    decision.estDirectWorstMs = best->maxMs / 2 + k_ImacDecodeMs + frameWaitMs(facts.imacRefreshHz);
    decision.estViaMs = macOneWay + k_MacDecodeMs + frameWaitMs(facts.virtualRefreshHz) + displayExtendMs;
    decision.estViaWorstMs = macWorstOneWay + k_MacDecodeMs + frameWaitMs(facts.virtualRefreshHz) + displayExtendWorstMs;

    bool fasterTypically = decision.estDirectMs <= decision.estViaMs + k_DirectBiasMs;
    bool fasterAtWorst = decision.estDirectWorstMs <= decision.estViaWorstMs + k_DirectWorstBiasMs;
    if (setting == Setting::Direct) {
        decision.route = Route::Direct;
        decision.reason = "set to go straight from the PC";
    }
    else if (fasterTypically && fasterAtWorst) {
        decision.route = Route::Direct;
        decision.reason = "faster";
    }
    else {
        decision.reason = fasterTypically ? "steadier at its worst" : "faster";
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

    bool direct = decision.route == Route::Direct;
    double first = direct ? decision.estDirectMs : decision.estViaMs;
    double second = direct ? decision.estViaMs : decision.estDirectMs;
    double firstWorst = direct ? decision.estDirectWorstMs : decision.estViaWorstMs;
    double secondWorst = direct ? decision.estViaWorstMs : decision.estDirectWorstMs;
    text += " (about " + ms(first) + " vs " + ms(second) + ", worst " + ms(firstWorst) + " vs " + ms(secondWorst);
    if (best != nullptr) {
        text += "; iMac→PC " + ms(best->medianMs) + ", worst " + ms(best->maxMs);
    }
    if (facts.macToPc.medianMs >= 0) {
        text += "; Mac→PC " + ms(facts.macToPc.medianMs) + ", worst " + ms(facts.macToPc.maxMs);
    }
    bool measured = facts.displayExtendFrames >= k_MinDisplayExtendFrames && facts.displayExtendP50Ms > 0;
    text += "; DisplayExtend " + ms(measured ? facts.displayExtendP50Ms : k_DefaultDisplayExtendMs);
    if (measured && facts.displayExtendP95Ms > 0) {
        text += ", worst " + ms(facts.displayExtendP95Ms);
    }
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
