#include "forkroutememory.h"

#include <locale>
#include <sstream>

namespace ForkRouteMemory
{
namespace
{
    constexpr const char* k_Version = "1";

    // Numbers are written and read in the C locale: Qt sets the user's, whose decimal comma would
    // make "12.5" unreadable on the way back
    std::string probeText(const ForkDisplayRoute::Probe& probe)
    {
        std::ostringstream out;
        out.imbue(std::locale::classic());
        out << probe.address << ',' << probe.count << ',' << probe.failures << ',' << probe.medianMs << ',' << probe.maxMs;
        return out.str();
    }

    bool number(const std::string& text, double* value)
    {
        std::istringstream in(text);
        in.imbue(std::locale::classic());
        in >> *value;
        return !text.empty() && !in.fail() && in.peek() == std::char_traits<char>::eof();
    }

    bool parseProbe(const std::string& text, ForkDisplayRoute::Probe* probe)
    {
        std::vector<std::string> fields;
        std::string field;
        std::istringstream in(text);
        while (std::getline(in, field, ',')) {
            fields.push_back(field);
        }
        double count, failures, median, max;
        if (fields.size() != 5 || fields[0].empty() || !number(fields[1], &count) || !number(fields[2], &failures) ||
                !number(fields[3], &median) || !number(fields[4], &max)) {
            return false;
        }
        probe->address = fields[0];
        probe->count = static_cast<int>(count);
        probe->failures = static_cast<int>(failures);
        probe->medianMs = median;
        probe->maxMs = max;
        return true;
    }
}

bool worthKeeping(const ForkDisplayRoute::Facts& facts)
{
    return !facts.imacToPc.empty();
}

Memory remember(const Key& key, const ForkDisplayRoute::Facts& facts, long long measuredAt)
{
    Memory memory;
    memory.key = key;
    memory.imacToPc = facts.imacToPc;
    memory.macToPc = facts.macToPc;
    memory.measuredAt = measuredAt;
    return memory;
}

bool reusable(const Memory& memory, const Key& now)
{
    return !memory.imacToPc.empty() && !now.hostUuid.empty() && !now.imacAddress.empty() && !now.display.empty() &&
           memory.key.hostUuid == now.hostUuid && memory.key.imacAddress == now.imacAddress &&
           memory.key.display == now.display && memory.key.network == now.network;
}

ForkDisplayRoute::Facts recall(const Memory& memory, const ForkDisplayRoute::Facts& now)
{
    ForkDisplayRoute::Facts facts = now;
    facts.imacToPc = memory.imacToPc;
    facts.macToPc = memory.macToPc;
    return facts;
}

std::string encode(const Memory& memory)
{
    std::ostringstream out;
    out.imbue(std::locale::classic());
    out << "v=" << k_Version << '\n'
        << "host=" << memory.key.hostUuid << '\n'
        << "imac=" << memory.key.imacAddress << '\n'
        << "display=" << memory.key.display << '\n'
        << "network=" << memory.key.network << '\n'
        << "at=" << memory.measuredAt << '\n'
        << "mac=" << probeText(memory.macToPc) << '\n';
    for (const ForkDisplayRoute::Probe& probe : memory.imacToPc) {
        out << "probe=" << probeText(probe) << '\n';
    }
    return out.str();
}

bool decode(const std::string& text, Memory* memory)
{
    Memory read;
    bool version = false, mac = false;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        size_t equals = line.find('=');
        if (equals == std::string::npos) {
            continue;
        }
        std::string name = line.substr(0, equals), value = line.substr(equals + 1);
        double at;
        if (name == "v") {
            version = value == k_Version;
        }
        else if (name == "host") {
            read.key.hostUuid = value;
        }
        else if (name == "imac") {
            read.key.imacAddress = value;
        }
        else if (name == "display") {
            read.key.display = value;
        }
        else if (name == "network") {
            read.key.network = value;
        }
        else if (name == "at" && number(value, &at)) {
            read.measuredAt = static_cast<long long>(at);
        }
        else if (name == "mac") {
            mac = parseProbe(value, &read.macToPc);
        }
        else if (name == "probe") {
            ForkDisplayRoute::Probe probe;
            if (!parseProbe(value, &probe)) {
                return false;
            }
            read.imacToPc.push_back(probe);
        }
    }
    if (!version || !mac || read.key.hostUuid.empty() || read.imacToPc.empty()) {
        return false;
    }
    *memory = read;
    return true;
}
}
