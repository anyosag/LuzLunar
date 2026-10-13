// Tests for app/fork/mac/pasteboard_mac.mm on a private named pasteboard (never the real clipboard).
// A standalone program for the fork's CI:
//   clang++ -std=c++17 -DCLIPBUNDLE_WITH_ZLIB -Iapp tests/fork/pasteboard_test.mm app/fork/mac/pasteboard_mac.mm
//       app/fork/clipbundle.cpp -framework AppKit -framework ImageIO -lz -o pasteboard_test

#include "fork/mac/pasteboard.h"

#include <cstdio>
#include <cstring>
#include <string>

#import <AppKit/AppKit.h>
#include <unistd.h>

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static const clipbundle::item* find(const MacPasteboard::Snapshot& snapshot, const char* type)
{
    for (const clipbundle::item& it : snapshot.items) {
        if (it.type == type) {
            return &it;
        }
    }
    return nullptr;
}

// A 3x2 image with an alpha channel, encoded by AppKit
static NSData* makeImage(NSBitmapImageFileType type)
{
    NSBitmapImageRep* rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:3 pixelsHigh:2
                                                                  bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                       isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                    bytesPerRow:0 bitsPerPixel:0] autorelease];
    memset(rep.bitmapData, 0x80, rep.bytesPerRow * 2);
    return type == NSBitmapImageFileTypeTIFF ? [rep TIFFRepresentation] : [rep representationUsingType:type properties:@{}];
}

int main()
{
    @autoreleasepool {
        std::string name = "com.luzlunar.pasteboard-test." + std::to_string(getpid());
        NSPasteboard* pasteboard = [NSPasteboard pasteboardWithName:@(name.c_str())];

        // Formatted text
        long count = MacPasteboard::write({ { "text/rtf", "{\\rtf1 \\b bold\\b0 }" },
                                            { "text/html", "<p>caf\xC3\xA9</p>" },
                                            { "text/plain", "caf\xC3\xA9\nline 2" } },
                                          false, name);
        if (count == 0) {
            std::printf("skipped: no pasteboard service here\n");
            return 0;
        }
        CHECK(count == MacPasteboard::changeCount(name));

        MacPasteboard::Snapshot text = MacPasteboard::read(name);
        CHECK(text.changeCount == count);
        CHECK(!text.concealed && !text.fileCopy);
        const clipbundle::item* plain = find(text, "text/plain");
        const clipbundle::item* rtf = find(text, "text/rtf");
        const clipbundle::item* html = find(text, "text/html");
        CHECK(plain != nullptr && plain->data == "caf\xC3\xA9\nline 2");
        CHECK(rtf != nullptr && rtf->data == "{\\rtf1 \\b bold\\b0 }");
        // Written with a charset declaration so apps read the UTF-8 correctly
        CHECK(html != nullptr && html->data.find("<p>caf\xC3\xA9</p>") != std::string::npos && html->data.find("utf-8") != std::string::npos);
        CHECK(!text.items.empty() && text.items.back().type == "text/plain");

        // An image copy round-trips as PNG
        NSData* png = makeImage(NSBitmapImageFileTypePNG);
        std::string pngBytes(static_cast<const char*>(png.bytes), png.length);
        CHECK(MacPasteboard::write({ { "image/png", pngBytes } }, false, name) != 0);
        MacPasteboard::Snapshot image = MacPasteboard::read(name);
        const clipbundle::item* readPng = find(image, "image/png");
        CHECK(readPng != nullptr && readPng->data == pngBytes);

        // A TIFF-only image (what many Mac apps copy) is converted to PNG
        [pasteboard clearContents];
        [pasteboard setData:makeImage(NSBitmapImageFileTypeTIFF) forType:NSPasteboardTypeTIFF];
        MacPasteboard::Snapshot tiff = MacPasteboard::read(name);
        const clipbundle::item* converted = find(tiff, "image/png");
        CHECK(converted != nullptr && converted->data.compare(0, 8, std::string("\x89PNG\r\n\x1a\n", 8)) == 0);

        // An Excel-like copy (text before a rendered picture) doesn't send the picture
        [pasteboard clearContents];
        NSPasteboardItem* range = [[[NSPasteboardItem alloc] init] autorelease];
        [range setString:@"1\t2" forType:NSPasteboardTypeString];
        [range setData:makeImage(NSBitmapImageFileTypeTIFF) forType:NSPasteboardTypeTIFF];
        [pasteboard writeObjects:@[range]];
        MacPasteboard::Snapshot cells = MacPasteboard::read(name);
        CHECK(find(cells, "text/plain") != nullptr);
        CHECK(find(cells, "image/png") == nullptr);

        // Private content is marked and detected
        CHECK(MacPasteboard::write({ { "text/plain", "secret" } }, true, name) != 0);
        CHECK(MacPasteboard::read(name).concealed);

        // A Finder file copy sends only its text
        [pasteboard clearContents];
        [pasteboard writeObjects:@[[NSURL fileURLWithPath:@"/System"]]];
        MacPasteboard::Snapshot files = MacPasteboard::read(name);
        CHECK(files.fileCopy);
        CHECK(find(files, "image/png") == nullptr);

        // Office's drawing format keeps its Mac name
        CHECK(MacPasteboard::write({ { "ms/gvml", std::string("PK\x05\x06", 4) + std::string(18, '\0') } }, false, name) != 0);
        CHECK([[pasteboard types] containsObject:@"com.microsoft.Art--GVML-ClipFormat"]);
        CHECK(find(MacPasteboard::read(name), "ms/gvml") != nullptr);

        [pasteboard releaseGlobally];
    }

    if (s_Failures > 0) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("All pasteboard tests passed\n");
    return 0;
}
