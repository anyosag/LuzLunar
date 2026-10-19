#pragma once

#include <string>
#include <vector>

#include "fork/clipbundle.h"

// The macOS clipboard (NSPasteboard) in clipbundle's formats, for rich clipboard sync with Apollo.
// Safe to call from a worker thread. Plain C++ interface, so tests can build it without Qt.
// Elsewhere supported() is false and the rest does nothing.
namespace MacPasteboard
{
    struct Snapshot {
        long changeCount = 0;            // NSPasteboard.changeCount when read
        bool concealed = false;          // a password manager marked the content as private
        bool fileCopy = false;           // files copied in Finder; no image is read
        std::vector<std::string> files;  // their full paths, in the order copied
        std::vector<clipbundle::item> items;   // in sending order
        std::vector<std::string> types;  // every type offered, for debug logs
    };

#ifdef __APPLE__
    bool supported();

    // pasteboardName: a named pasteboard for tests; empty for the general (system) clipboard
    long changeCount(const std::string& pasteboardName = std::string());

    Snapshot read(const std::string& pasteboardName = std::string());

    // Replaces the clipboard with the items. Returns the new change count, or 0 if writing failed.
    long write(const std::vector<clipbundle::item>& items, bool concealed, const std::string& pasteboardName = std::string());

    // Replaces the clipboard with files (full paths) as Finder's copy lists them, so a paste in
    // Finder copies them. Returns the new change count, or 0 if writing failed.
    long writeFiles(const std::vector<std::string>& paths, const std::string& pasteboardName = std::string());
#else
    inline bool supported() { return false; }
    inline long changeCount(const std::string& = std::string()) { return 0; }
    inline Snapshot read(const std::string& = std::string()) { return Snapshot(); }
    inline long write(const std::vector<clipbundle::item>&, bool, const std::string& = std::string()) { return 0; }
    inline long writeFiles(const std::vector<std::string>&, const std::string& = std::string()) { return 0; }
#endif
}
