#include "pasteboard.h"

#include <algorithm>
#include <utility>

#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>

namespace
{
    NSString* const k_ConcealedType = @"org.nspasteboard.ConcealedType";
    NSString* const k_TransientType = @"org.nspasteboard.TransientType";

    NSPasteboard* pasteboardNamed(const std::string& name)
    {
        return name.empty() ? [NSPasteboard generalPasteboard] : [NSPasteboard pasteboardWithName:@(name.c_str())];
    }

    clipbundle::kind kindOf(NSString* type)
    {
        static NSSet<NSString*>* textTypes = [[NSSet alloc] initWithArray:@[
            @"public.utf8-plain-text", @"public.utf16-external-plain-text", @"public.utf16-plain-text",
            @"NSStringPboardType", @"public.rtf", @"public.html", @"com.apple.flat-rtfd", @"public.rtfd",
            @"public.utf8-tab-separated-values-text",
        ]];
        static NSSet<NSString*>* imageTypes = [[NSSet alloc] initWithArray:@[
            @"public.png", @"public.tiff", @"public.jpeg", @"public.heic", @"com.adobe.pdf",
            @"NeXT TIFF v4.0 pasteboard type", @"Apple PNG pasteboard type",
        ]];
        if ([textTypes containsObject:type]) {
            return clipbundle::kind::text;
        }
        if ([imageTypes containsObject:type]) {
            return clipbundle::kind::image;
        }
        return clipbundle::kind::other;
    }

    std::string bytesOf(NSData* data)
    {
        return data != nil ? std::string(static_cast<const char*>(data.bytes), data.length) : std::string();
    }

    std::string utf8Of(NSString* string)
    {
        return bytesOf([string dataUsingEncoding:NSUTF8StringEncoding]);
    }

    // HTML on the pasteboard is usually UTF-8, but may be UTF-16 or (rarely) Windows-1252
    std::string htmlToUtf8(NSData* data)
    {
        const unsigned char* bytes = static_cast<const unsigned char*>(data.bytes);
        NSUInteger length = data.length;
        if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
            return std::string(reinterpret_cast<const char*>(bytes) + 3, length - 3);
        }
        if (length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
            NSString* html = [[[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding] autorelease];
            return html != nil ? utf8Of(html) : std::string();
        }
        if ([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] != nil) {
            return bytesOf(data);
        }
        NSString* html = [[[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding] autorelease];
        return html != nil ? utf8Of(html) : std::string();
    }

    // TIFF or HEIC to PNG or JPEG with ImageIO (thread-safe, keeps color profiles)
    std::string convertImage(NSData* data, CFStringRef targetType, bool lossy)
    {
        CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, nullptr);
        if (source == nullptr) {
            return std::string();
        }

        std::string result;
        NSMutableData* output = [NSMutableData data];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)output, targetType, 1, nullptr);
        if (destination != nullptr) {
            NSDictionary* properties = lossy ? @{ (NSString*)kCGImageDestinationLossyCompressionQuality: @0.9 } : nil;
            CGImageDestinationAddImageFromSource(destination, source, 0, (CFDictionaryRef)properties);
            if (CGImageDestinationFinalize(destination)) {
                result = bytesOf(output);
            }
            CFRelease(destination);
        }
        CFRelease(source);
        return result;
    }

    MacPasteboard::Snapshot readOnce(NSPasteboard* pasteboard)
    {
        MacPasteboard::Snapshot snapshot;
        snapshot.changeCount = pasteboard.changeCount;

        NSArray<NSPasteboardType>* types = pasteboard.types;
        std::vector<clipbundle::kind> kinds;
        for (NSUInteger i = 0; i < types.count; i++) {
            NSString* type = types[i];
            snapshot.types.push_back(type.UTF8String);
            if ([type isEqualToString:k_ConcealedType] || [type isEqualToString:k_TransientType]) {
                snapshot.concealed = true;
            }
            if ([type isEqualToString:NSPasteboardTypeFileURL]) {
                snapshot.fileCopy = true;
            }
            kinds.push_back(kindOf(type));
        }

        std::vector<std::pair<size_t, clipbundle::item>> items;
        auto add = [&items](size_t position, const char* type, std::string data) {
            items.push_back({position, clipbundle::item { type, std::move(data) }});
        };

        std::string plainText;
        NSString* text = [pasteboard stringForType:NSPasteboardTypeString];
        if (text.length > 0) {
            plainText = clipbundle::to_lf(utf8Of(text));
            add(types.count, "text/plain", plainText);
        }

        // The HTML too, which tells a picture copy (a browser's <img> tag) from a text copy
        std::string html;
        bool haveHtml = false;
        if ([types containsObject:NSPasteboardTypeHTML]) {
            NSData* data = [pasteboard dataForType:NSPasteboardTypeHTML];
            if (data != nil) {
                html = htmlToUtf8(data);
                haveHtml = !html.empty();
            }
        }

        // Decided before reading any image, so the app that copied isn't asked to render one that won't be sent
        bool wantImage = !snapshot.fileCopy && clipbundle::include_image(kinds, plainText, html);
        bool imageFirst = wantImage;

        bool haveImage = false;
        NSString* convertible = nil;   // a TIFF or HEIC image, converted if there's no PNG or JPEG
        size_t convertiblePosition = 0;
        if (!snapshot.fileCopy) {
            for (NSUInteger i = 0; i < types.count; i++) {
                NSString* type = types[i];
                if ([type isEqualToString:@"public.tiff"] || [type isEqualToString:@"public.heic"]) {
                    if (wantImage && convertible == nil) {
                        convertible = type;
                        convertiblePosition = i;
                    }
                    continue;
                }

                const clipbundle::type_info* info = clipbundle::find_mac(type.UTF8String);
                if (info == nullptr || std::string(info->type) == "text/plain") {
                    continue;
                }
                bool image = clipbundle::is_image_type(info->type);
                if (image && (!wantImage || haveImage)) {
                    continue;
                }

                std::string kindName = info->type;
                if (kindName == "text/html") {
                    // Already read for the image rule
                    if (haveHtml) {
                        add(i, info->type, std::move(html));
                        haveHtml = false;
                    }
                    continue;
                }

                NSData* data = [pasteboard dataForType:type];
                if (data == nil) {
                    continue;
                }

                if (kindName == "image/png") {
                    std::string png = bytesOf(data);
                    png.resize(clipbundle::png_length(png));
                    add(i, info->type, std::move(png));
                    haveImage = true;
                }
                else if (kindName == "image/jpeg") {
                    add(i, info->type, bytesOf(data));
                    haveImage = true;
                }
                else if (kindName == "ms/gvml") {
                    std::string zip = bytesOf(data);
                    zip.resize(clipbundle::zip_length(zip));
                    add(i, info->type, std::move(zip));
                }
                else {
                    add(i, info->type, bytesOf(data));
                }
            }
        }

        if (convertible != nil && !haveImage) {
            NSData* data = [pasteboard dataForType:convertible];
            if (data != nil) {
                // A HEIC photo goes as JPEG, so it doesn't become a huge PNG
                bool photo = [convertible isEqualToString:@"public.heic"];
                std::string image = convertImage(data, photo ? CFSTR("public.jpeg") : CFSTR("public.png"), photo);
                if (!image.empty()) {
                    add(convertiblePosition, photo ? "image/jpeg" : "image/png", std::move(image));
                }
            }
        }

        std::stable_sort(items.begin(), items.end(), [](const auto& a, const auto& b) {
            return a.first < b.first;
        });
        for (auto& entry : items) {
            snapshot.items.push_back(std::move(entry.second));
        }
        clipbundle::prepare_for_send(snapshot.items, imageFirst);
        return snapshot;
    }
}

bool MacPasteboard::supported()
{
    return true;
}

long MacPasteboard::changeCount(const std::string& pasteboardName)
{
    @autoreleasepool {
        return pasteboardNamed(pasteboardName).changeCount;
    }
}

MacPasteboard::Snapshot MacPasteboard::read(const std::string& pasteboardName)
{
    @autoreleasepool {
        NSPasteboard* pasteboard = pasteboardNamed(pasteboardName);
        Snapshot snapshot = readOnce(pasteboard);
        // Copied again while reading: read the new content instead of a mix
        if (pasteboard.changeCount != snapshot.changeCount) {
            snapshot = readOnce(pasteboard);
        }
        return snapshot;
    }
}

long MacPasteboard::write(const std::vector<clipbundle::item>& items, bool concealed, const std::string& pasteboardName)
{
    @autoreleasepool {
        NSPasteboardItem* item = [[[NSPasteboardItem alloc] init] autorelease];
        bool any = false;
        for (const clipbundle::item& it : items) {
            const clipbundle::type_info* info = clipbundle::find_type(it.type);
            // Images must be the format they claim: the app that pastes decodes whatever the bytes are
            if (info == nullptr || !clipbundle::data_matches_type(it.type, it.data)) {
                continue;
            }

            if (it.type == "text/plain") {
                NSString* text = [[[NSString alloc] initWithBytes:it.data.data() length:it.data.size() encoding:NSUTF8StringEncoding] autorelease];
                if (text != nil && [item setString:text forType:NSPasteboardTypeString]) {
                    any = true;
                }
                continue;
            }

            std::string bytes = it.type == "text/html" ? clipbundle::ensure_utf8_meta(it.data) : it.data;
            NSData* data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
            if ([item setData:data forType:@(info->mac_type)]) {
                any = true;
            }
        }
        if (!any) {
            return 0;
        }
        if (concealed) {
            [item setData:[NSData data] forType:k_ConcealedType];
        }

        NSPasteboard* pasteboard = pasteboardNamed(pasteboardName);
        [pasteboard clearContents];
        if (![pasteboard writeObjects:@[item]]) {
            return 0;
        }
        return pasteboard.changeCount;
    }
}
