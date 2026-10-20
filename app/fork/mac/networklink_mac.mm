#include "networklink.h"

#include <algorithm>
#include <cstring>
#include <vector>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_media.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/sockio.h>
#include <unistd.h>

#import <CoreWLAN/CoreWLAN.h>
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>

using ForkLinkRules::Kind;
using ForkLinkRules::Link;

namespace
{
    std::string utf8(CFStringRef text)
    {
        if (text == nullptr) {
            return std::string();
        }
        if (const char* direct = CFStringGetCStringPtr(text, kCFStringEncodingUTF8)) {
            return direct;
        }
        CFIndex size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(text), kCFStringEncodingUTF8) + 1;
        std::vector<char> buffer(static_cast<size_t>(size), '\0');
        if (!CFStringGetCString(text, buffer.data(), size, kCFStringEncodingUTF8)) {
            return std::string();
        }
        return buffer.data();
    }

    std::string stringValue(CFDictionaryRef dictionary, CFStringRef key)
    {
        CFTypeRef value = CFDictionaryGetValue(dictionary, key);
        return value != nullptr && CFGetTypeID(value) == CFStringGetTypeID() ? utf8(static_cast<CFStringRef>(value)) : std::string();
    }

    bool hasPrefix(const std::string& text, const char* prefix)
    {
        return text.compare(0, strlen(prefix), prefix) == 0;
    }

    // Tunnels: VPNs (utun, ipsec, ppp, WireGuard, OpenVPN's tun and tap) and ZeroTier's feth
    bool tunnelName(const std::string& name)
    {
        for (const char* prefix : { "utun", "ipsec", "ppp", "wg", "tun", "tap", "feth" }) {
            if (hasPrefix(name, prefix)) {
                return true;
            }
        }
        return false;
    }

    // The local address the system would send to peer from: connecting a UDP socket picks a route
    // without sending anything
    bool localAddressTo(const sockaddr* peer, socklen_t peerLength, sockaddr_storage& local)
    {
        int fd = socket(peer->sa_family, SOCK_DGRAM, IPPROTO_UDP);
        if (fd < 0) {
            return false;
        }
        socklen_t length = sizeof(local);
        bool ok = connect(fd, peer, peerLength) == 0 && getsockname(fd, reinterpret_cast<sockaddr*>(&local), &length) == 0;
        close(fd);
        return ok;
    }

    // An address's bytes, and how many there are; null for other families
    const uint8_t* addressBytes(const sockaddr* address, size_t& count)
    {
        if (address->sa_family == AF_INET) {
            count = sizeof(in_addr);
            return reinterpret_cast<const uint8_t*>(&reinterpret_cast<const sockaddr_in*>(address)->sin_addr);
        }
        if (address->sa_family == AF_INET6) {
            count = sizeof(in6_addr);
            return reinterpret_cast<const uint8_t*>(&reinterpret_cast<const sockaddr_in6*>(address)->sin6_addr);
        }
        count = 0;
        return nullptr;
    }

    bool sameAddress(const sockaddr* a, const sockaddr* b)
    {
        size_t countA, countB;
        const uint8_t* bytesA = addressBytes(a, countA);
        const uint8_t* bytesB = addressBytes(b, countB);
        return bytesA != nullptr && bytesB != nullptr && a->sa_family == b->sa_family && memcmp(bytesA, bytesB, countA) == 0;
    }

    // Whether peer is in the subnet of local and mask. A netmask from getifaddrs() can be shorter
    // than its family's sockaddr, with the rest zero.
    bool inSubnet(const sockaddr* local, const sockaddr* mask, const sockaddr* peer)
    {
        size_t count, peerCount;
        const uint8_t* localBytes = addressBytes(local, count);
        const uint8_t* peerBytes = addressBytes(peer, peerCount);
        if (mask == nullptr || localBytes == nullptr || peerBytes == nullptr || local->sa_family != peer->sa_family) {
            return false;
        }

        sockaddr_storage fullMask;
        memset(&fullMask, 0, sizeof(fullMask));
        memcpy(&fullMask, mask, std::min<size_t>(mask->sa_len, sizeof(fullMask)));
        fullMask.ss_family = local->sa_family;
        size_t maskCount;
        const uint8_t* maskBytes = addressBytes(reinterpret_cast<const sockaddr*>(&fullMask), maskCount);

        for (size_t i = 0; i < count; i++) {
            if ((localBytes[i] ^ peerBytes[i]) & maskBytes[i]) {
                return false;
            }
        }
        return true;
    }

    struct Interface {
        std::string name;
        bool pointToPoint = false;
        bool onLink = false;
    };

    // The interface that has local, and whether peer is in its subnet
    Interface interfaceWith(const sockaddr* local, const sockaddr* peer)
    {
        Interface found;
        ifaddrs* list = nullptr;
        if (getifaddrs(&list) != 0) {
            return found;
        }
        for (ifaddrs* it = list; it != nullptr; it = it->ifa_next) {
            if (it->ifa_addr != nullptr && sameAddress(it->ifa_addr, local)) {
                found.name = it->ifa_name;
                found.pointToPoint = (it->ifa_flags & IFF_POINTOPOINT) != 0;
                found.onLink = !found.pointToPoint && inSubnet(local, it->ifa_netmask, peer);
                break;
            }
        }
        freeifaddrs(list);
        return found;
    }

    // What System Settings calls the interface
    Link kindOf(const std::string& name, bool pointToPoint)
    {
        Link link;
        if (pointToPoint || tunnelName(name)) {
            link.kind = Kind::Vpn;
            return link;
        }
        if (name == "bridge0") {
            // A Mac's Thunderbolt ports, bridged; the later bridges are Internet Sharing's and VMs'
            link.kind = Kind::ThunderboltBridge;
            return link;
        }

        CFArrayRef all = SCNetworkInterfaceCopyAll();
        if (all != nullptr) {
            for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
                SCNetworkInterfaceRef interface = static_cast<SCNetworkInterfaceRef>(CFArrayGetValueAtIndex(all, i));
                if (utf8(SCNetworkInterfaceGetBSDName(interface)) != name) {
                    continue;
                }
                CFStringRef type = SCNetworkInterfaceGetInterfaceType(interface);
                std::string display = utf8(SCNetworkInterfaceGetLocalizedDisplayName(interface));
                if (type != nullptr && CFEqual(type, kSCNetworkInterfaceTypeIEEE80211)) {
                    link.kind = Kind::WiFi;
                }
                else if (type != nullptr && CFEqual(type, kSCNetworkInterfaceTypeEthernet) &&
                         !hasPrefix(display, "iPhone") && !hasPrefix(display, "iPad")) {
                    // Any wired adapter; Personal Hotspot over USB is an Ethernet interface too
                    link.kind = Kind::Ethernet;
                }
                else {
                    link.kind = Kind::Other;
                    link.name = display.empty() ? name : display;
                }
                break;
            }
            CFRelease(all);
        }
        if (link.kind == Kind::Unknown) {
            // Not a network service, like a VM's interface
            link.kind = Kind::Other;
            link.name = name;
        }
        return link;
    }

    double ethernetMbps(const std::string& name)
    {
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0) {
            return 0;
        }
        struct ifmediareq request;
        memset(&request, 0, sizeof(request));
        strlcpy(request.ifm_name, name.c_str(), sizeof(request.ifm_name));
        double mbps = 0;
        if (ioctl(fd, SIOCGIFMEDIA, &request) == 0 && (request.ifm_status & IFM_AVALID) && (request.ifm_status & IFM_ACTIVE)) {
            mbps = MacNetworkLink::mediaMbps(request.ifm_active);
        }
        close(fd);
        return mbps;
    }

    // Without Location access macOS may leave these out; the badge then just says Wi-Fi
    void addWiFiDetails(const std::string& name, Link& link)
    {
        CWInterface* wifi = [[CWWiFiClient sharedWiFiClient] interfaceWithName:[NSString stringWithUTF8String:name.c_str()]];
        if (wifi == nil) {
            return;
        }
        link.mbps = wifi.transmitRate;
        CWChannel* channel = wifi.wlanChannel;
        if (channel != nil) {
            switch (channel.channelBand) {
            case kCWChannelBand2GHz:
                link.bandGHz = 2.4;
                break;
            case kCWChannelBand5GHz:
                link.bandGHz = 5;
                break;
            case kCWChannelBand6GHz:
                link.bandGHz = 6;
                break;
            default:
                break;
            }
        }
    }

    Link linkOf(const std::string& name, bool pointToPoint)
    {
        Link link = kindOf(name, pointToPoint);
        if (link.kind == Kind::Ethernet || link.kind == Kind::ThunderboltBridge) {
            link.mbps = ethernetMbps(name);
        }
        else if (link.kind == Kind::WiFi) {
            addWiFiDetails(name, link);
        }
        return link;
    }

    // The Mac's main connection, which a VPN runs over
    std::string primaryInterface(SCDynamicStoreRef store)
    {
        CFStringRef key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nullptr, kSCDynamicStoreDomainState, kSCEntNetIPv4);
        CFPropertyListRef value = SCDynamicStoreCopyValue(store, key);
        CFRelease(key);
        std::string name;
        if (value != nullptr) {
            if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                name = stringValue(static_cast<CFDictionaryRef>(value), kSCDynamicStorePropNetPrimaryInterface);
            }
            CFRelease(value);
        }
        return name;
    }

    // macOS's identity for the IPv4 network an interface is on: its NetworkSignature, which names
    // the router by address and hardware address, or those two from the ARP state. Empty without a
    // router.
    std::string signatureOf(SCDynamicStoreRef store, const std::string& interfaceName)
    {
        CFStringRef pattern = SCDynamicStoreKeyCreateNetworkServiceEntity(nullptr, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv4);
        CFArrayRef patterns = CFArrayCreate(nullptr, reinterpret_cast<const void**>(&pattern), 1, &kCFTypeArrayCallBacks);
        CFDictionaryRef services = SCDynamicStoreCopyMultiple(store, nullptr, patterns);
        CFRelease(patterns);
        CFRelease(pattern);

        std::string signature;
        if (services != nullptr) {
            CFIndex count = CFDictionaryGetCount(services);
            std::vector<const void*> keys(static_cast<size_t>(count)), values(static_cast<size_t>(count));
            CFDictionaryGetKeysAndValues(services, keys.data(), values.data());
            for (CFIndex i = 0; i < count && signature.empty(); i++) {
                CFTypeRef value = values[static_cast<size_t>(i)];
                if (CFGetTypeID(value) != CFDictionaryGetTypeID()) {
                    continue;
                }
                CFDictionaryRef ipv4 = static_cast<CFDictionaryRef>(value);
                if (stringValue(ipv4, kSCPropInterfaceName) != interfaceName) {
                    continue;
                }
                signature = stringValue(ipv4, CFSTR("NetworkSignature"));
                if (signature.empty()) {
                    std::string router = stringValue(ipv4, kSCPropNetIPv4Router);
                    std::string hardware = stringValue(ipv4, CFSTR("ARPResolvedHardwareAddress"));
                    if (!router.empty() && !hardware.empty()) {
                        signature = "IPv4.Router=" + router + ";IPv4.RouterHardwareAddress=" + hardware;
                    }
                }
            }
            CFRelease(services);
        }
        return signature;
    }
}

std::string MacNetworkLink::numericAddress(const std::string& host)
{
    std::string name = host;
    if (name.size() > 2 && name.front() == '[' && name.back() == ']') {
        name = name.substr(1, name.size() - 2);
    }
    if (name.empty()) {
        return std::string();
    }

    addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    addrinfo* info = nullptr;
    if (getaddrinfo(name.c_str(), nullptr, &hints, &info) != 0 || info == nullptr) {
        return std::string();
    }
    char text[NI_MAXHOST] = {};
    bool ok = getnameinfo(info->ai_addr, info->ai_addrlen, text, sizeof(text), nullptr, 0, NI_NUMERICHOST) == 0;
    freeaddrinfo(info);
    return ok ? std::string(text) : std::string();
}

MacNetworkLink::Probe MacNetworkLink::probe(const std::string& address)
{
    Probe result;
    @autoreleasepool {
        addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_flags = AI_NUMERICHOST;
        hints.ai_socktype = SOCK_DGRAM;
        addrinfo* info = nullptr;
        // Moonlight's video port; any port gives the same route
        if (address.empty() || getaddrinfo(address.c_str(), "47998", &hints, &info) != 0 || info == nullptr) {
            return result;
        }

        sockaddr_storage local;
        bool pointToPoint = false;
        if (localAddressTo(info->ai_addr, info->ai_addrlen, local)) {
            Interface interface = interfaceWith(reinterpret_cast<const sockaddr*>(&local), info->ai_addr);
            result.interfaceName = interface.name;
            result.onLink = interface.onLink;
            pointToPoint = interface.pointToPoint;
        }
        freeaddrinfo(info);
        if (result.interfaceName.empty()) {
            return result;
        }
        result.link = linkOf(result.interfaceName, pointToPoint);

        SCDynamicStoreRef store = SCDynamicStoreCreate(nullptr, CFSTR("LuzLunar"), nullptr, nullptr);
        if (store == nullptr) {
            return result;
        }
        std::string networkInterface = result.interfaceName;
        if (result.link.kind == Kind::Vpn) {
            // The network is the one the VPN runs over
            networkInterface = primaryInterface(store);
            if (networkInterface == result.interfaceName || tunnelName(networkInterface)) {
                networkInterface.clear();
            }
            if (!networkInterface.empty()) {
                result.link.underlying = kindOf(networkInterface, false).kind;
            }
        }
        if (!networkInterface.empty()) {
            result.networkId = signatureOf(store, networkInterface);
        }
        CFRelease(store);
    }
    return result;
}

double MacNetworkLink::mediaMbps(int activeMedia)
{
    if (IFM_TYPE(activeMedia) != IFM_ETHER) {
        return 0;
    }
    switch (IFM_SUBTYPE(activeMedia)) {
    case IFM_10_T:
    case IFM_10_2:
    case IFM_10_5:
        return 10;
    case IFM_100_TX:
    case IFM_100_FX:
    case IFM_100_T4:
        return 100;
    case IFM_1000_SX:
    case IFM_1000_T:
        return 1000;
#ifdef IFM_1000_LX
    case IFM_1000_LX:
        return 1000;
#endif
#ifdef IFM_1000_CX
    case IFM_1000_CX:
        return 1000;
#endif
#ifdef IFM_2500_T
    case IFM_2500_T:
        return 2500;
#endif
#ifdef IFM_5000_T
    case IFM_5000_T:
        return 5000;
#endif
#ifdef IFM_10G_T
    case IFM_10G_T:
        return 10000;
#endif
#ifdef IFM_10G_SR
    case IFM_10G_SR:
        return 10000;
#endif
#ifdef IFM_10G_LR
    case IFM_10G_LR:
        return 10000;
#endif
#ifdef IFM_10G_CX4
    case IFM_10G_CX4:
        return 10000;
#endif
    default:
        return 0;
    }
}
