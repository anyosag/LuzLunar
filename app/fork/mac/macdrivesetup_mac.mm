#include "macdrivesetup.h"

#include <cerrno>
#include <mutex>
#include <vector>

#include <arpa/inet.h>
#include <fcntl.h>
#include <grp.h>
#include <membership.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OpenDirectory/OpenDirectory.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>

namespace
{
    std::mutex s_ServiceMutex;
    std::string s_Service = "LuzLunar Mac drive";

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

    // The account's record in the local directory; autoreleased
    ODRecord* userRecord(NSArray* attributes)
    {
        ODNode* node = [ODNode nodeWithSession:[ODSession defaultSession] type:kODNodeTypeLocalNodes error:nil];
        return [node recordWithRecordType:kODRecordTypeUsers name:NSUserName() attributes:attributes error:nil];
    }

    // An attribute's first value as text, or nil; autoreleased
    NSString* firstValue(ODRecord* record, NSString* attribute)
    {
        NSArray* values = [record valuesForAttribute:attribute error:nil];
        id value = values.count > 0 ? values[0] : nil;
        if ([value isKindOfClass:[NSString class]]) {
            return value;
        }
        if ([value isKindOfClass:[NSData class]]) {
            return [[[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding] autorelease];
        }
        return nil;
    }

    // The keychain item's identity: LuzLunar's service and this account; autoreleased
    NSMutableDictionary* itemQuery()
    {
        std::string service;
        {
            std::lock_guard<std::mutex> lock(s_ServiceMutex);
            service = s_Service;
        }
        NSMutableDictionary* query = [NSMutableDictionary dictionary];
        query[(id)kSecClass] = (id)kSecClassGenericPassword;
        query[(id)kSecAttrService] = [NSString stringWithUTF8String:service.c_str()];
        query[(id)kSecAttrAccount] = NSUserName();
        return query;
    }
}

std::string MacDriveSetup::userName()
{
    @autoreleasepool {
        NSString* name = NSUserName();
        return name.length > 0 ? std::string(name.UTF8String) : std::string();
    }
}

std::string MacDriveSetup::computerName()
{
    CFStringRef name = SCDynamicStoreCopyComputerName(nullptr, nullptr);
    std::string text = utf8(name);
    if (name != nullptr) {
        CFRelease(name);
    }
    return text;
}

bool MacDriveSetup::isAdmin()
{
    struct group entry;
    struct group* found = nullptr;
    char buffer[4096];
    if (getgrnam_r("admin", &entry, buffer, sizeof(buffer), &found) != 0 || found == nullptr) {
        return false;
    }
    uuid_t user;
    uuid_t group;
    int member = 0;
    return mbr_uid_to_uuid(getuid(), user) == 0 && mbr_gid_to_uuid(found->gr_gid, group) == 0 &&
           mbr_check_membership(user, group, &member) == 0 && member != 0;
}

bool MacDriveSetup::fileSharingOn()
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return false;
    }
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);

    sockaddr_in address = {};
    address.sin_family = AF_INET;
    address.sin_port = htons(445);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    bool open = false;
    if (connect(fd, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == 0) {
        open = true;
    }
    else if (errno == EINPROGRESS) {
        // Loopback answers at once either way; this only bounds a firewall that drops it
        pollfd wait = { fd, POLLOUT, 0 };
        if (poll(&wait, 1, 200) == 1) {
            int error = 0;
            socklen_t size = sizeof(error);
            open = getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 && error == 0;
        }
    }
    close(fd);
    return open;
}

std::string MacDriveSetup::diskShareName()
{
    @autoreleasepool {
        ODNode* node = [ODNode nodeWithSession:[ODSession defaultSession] type:kODNodeTypeLocalNodes error:nil];
        NSArray* wanted = @[ @"dsAttrTypeNative:directory_path", @"dsAttrTypeNative:smb_name", @"dsAttrTypeNative:smb_shared" ];
        ODQuery* query = [ODQuery queryWithNode:node
                                 forRecordTypes:@"dsRecTypeStandard:SharePoints"
                                      attribute:kODAttributeTypeRecordName
                                      matchType:kODMatchAny
                                    queryValues:nil
                               returnAttributes:wanted
                                 maximumResults:0
                                          error:nil];
        for (ODRecord* record in [query resultsAllowingPartial:NO error:nil]) {
            NSString* path = firstValue(record, @"dsAttrTypeNative:directory_path");
            NSString* name = firstValue(record, @"dsAttrTypeNative:smb_name");
            NSString* shared = firstValue(record, @"dsAttrTypeNative:smb_shared");
            bool disk = [path isEqualToString:@"/"] || [path isEqualToString:@"/System/Volumes/Data"];
            if (disk && [shared isEqualToString:@"1"] && name.length > 0) {
                return std::string(name.UTF8String);
            }
        }
    }
    return std::string();
}

std::string MacDriveSetup::startupVolumeName()
{
    @autoreleasepool {
        id name = nil;
        [[NSURL fileURLWithPath:@"/"] getResourceValue:&name forKey:NSURLVolumeNameKey error:nil];
        return [name isKindOfClass:[NSString class]] && [name length] > 0 ? std::string([name UTF8String]) : std::string();
    }
}

MacDriveSetup::WindowsSharing MacDriveSetup::windowsSharing()
{
    @autoreleasepool {
        ODRecord* record = userRecord(@[ kODAttributeTypeAuthenticationAuthority ]);
        // ";ShadowHash;HASHLIST:<SALTED-SHA512-PBKDF2,SRP-RFC5054-4096-SHA512-PBKDF2,SMB-NT>": macOS keeps
        // the NT hash only while Windows File Sharing is on for the account
        for (id value in [record valuesForAttribute:kODAttributeTypeAuthenticationAuthority error:nil]) {
            if (![value isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString* text = value;
            if ([text rangeOfString:@";ShadowHash;"].location != NSNotFound && [text rangeOfString:@"HASHLIST:<"].location != NSNotFound) {
                return [text rangeOfString:@"SMB-NT"].location != NSNotFound ? WindowsSharing::On : WindowsSharing::Off;
            }
        }
    }
    return WindowsSharing::Unknown;
}

bool MacDriveSetup::verifyPassword(const std::string& password)
{
    if (password.empty()) {
        return false;
    }
    @autoreleasepool {
        ODRecord* record = userRecord(nil);
        NSString* text = [NSString stringWithUTF8String:password.c_str()];
        return record != nil && text != nil && [record verifyPassword:text error:nil];
    }
}

bool MacDriveSetup::savePassword(const std::string& password)
{
    if (password.empty()) {
        return false;
    }
    @autoreleasepool {
        NSMutableDictionary* query = itemQuery();
        SecItemDelete((CFDictionaryRef)query);

        NSMutableDictionary* item = [[query mutableCopy] autorelease];
        item[(id)kSecValueData] = [NSData dataWithBytes:password.data() length:password.size()];
        item[(id)kSecAttrLabel] = @"LuzLunar Mac drive";
        item[(id)kSecAttrDescription] = @"Mac password for the PC's drive of this Mac";
        return SecItemAdd((CFDictionaryRef)item, nullptr) == errSecSuccess;
    }
}

std::string MacDriveSetup::loadPassword()
{
    @autoreleasepool {
        NSMutableDictionary* query = itemQuery();
        query[(id)kSecReturnData] = @YES;
        query[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
        CFTypeRef result = nullptr;
        if (SecItemCopyMatching((CFDictionaryRef)query, &result) != errSecSuccess || result == nullptr) {
            return std::string();
        }
        std::string password;
        if (CFGetTypeID(result) == CFDataGetTypeID()) {
            CFDataRef data = static_cast<CFDataRef>(result);
            password.assign(reinterpret_cast<const char*>(CFDataGetBytePtr(data)), static_cast<size_t>(CFDataGetLength(data)));
        }
        CFRelease(result);
        return password;
    }
}

bool MacDriveSetup::hasPassword()
{
    @autoreleasepool {
        // Only the item's attributes: reading them never asks the user anything
        NSMutableDictionary* query = itemQuery();
        query[(id)kSecReturnAttributes] = @YES;
        query[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
        CFTypeRef result = nullptr;
        OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);
        if (result != nullptr) {
            CFRelease(result);
        }
        return status == errSecSuccess;
    }
}

void MacDriveSetup::forgetPassword()
{
    @autoreleasepool {
        SecItemDelete((CFDictionaryRef)itemQuery());
    }
}

void MacDriveSetup::openSharingSettings()
{
    @autoreleasepool {
        NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
        // The pane's id isn't documented; macOS 13 and later know the first, older ones the second
        for (NSString* url in @[ @"x-apple.systempreferences:com.apple.Sharing-Settings.extension",
                                 @"x-apple.systempreferences:com.apple.preferences.sharing" ]) {
            if ([workspace openURL:[NSURL URLWithString:url]]) {
                return;
            }
        }
        [workspace openURL:[NSURL fileURLWithPath:@"/System/Applications/System Settings.app"]];
    }
}

void MacDriveSetup::setKeychainServiceForTests(const std::string& service)
{
    std::lock_guard<std::mutex> lock(s_ServiceMutex);
    s_Service = service;
}
