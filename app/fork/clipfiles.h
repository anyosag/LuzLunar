#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "clipbundle.h"

// Files copied to the clipboard, on the Mac's side of clipboard sync (clipbundle.h, "File copies",
// and clipboardsync.cpp): a Finder copy's files walked into a manifest and read in chunks, a copy
// from the PC written chunk by chunk into LuzLunar's cache, and old copies cleared away. Plain C++
// on POSIX, so tests/fork/clipfiles_test.cpp runs anywhere.
namespace ClipFiles
{
    // A copy to send: the manifest, and each entry's full path
    struct Outgoing {
        clipbundle::file_manifest manifest;
        std::vector<std::string> paths;
        size_t unreadable = 0;  // copied files or folders that couldn't be read, left out
    };

    // Walks the copied files and folders (full paths) into a manifest. Symbolic links inside folders
    // are left out, so a copy can't leave them or loop. False when it's over clipbundle's limits.
    bool share(const std::vector<std::string>& roots, Outgoing& out);

    enum class ReadResult { Ok, Changed, Failed };

    // Up to k_file_chunk_bytes of a listed file from offset. Changed when its size or time
    // differ from the manifest's: it changed since it was copied.
    ReadResult readChunk(const std::string& path, const clipbundle::file_entry& entry, uint64_t offset, std::string& data);

    // A copy arriving from the PC: in "<base>/<transfer>.partial" until complete()
    struct Incoming {
        std::string folder;
        std::vector<std::string> local;  // per entry, from clipbundle::local_paths(); empty when left out
    };

    // Makes the copy's folder under base, with its folders and empty files. False if it can't.
    bool prepare(const std::string& base, const clipbundle::file_manifest& manifest, Incoming& in);

    // Writes a chunk of an entry's file at offset, and sets the file's time once it has all its bytes
    bool writeChunk(const Incoming& in, const clipbundle::file_manifest& manifest, size_t index, uint64_t offset, std::string_view data);

    // Moves the copy to "<base>/<transfer>" and lists its top-level paths, which go on the clipboard
    bool complete(const std::string& base, Incoming& in, const clipbundle::file_manifest& manifest, std::vector<std::string>& topLevel);

    // A copy received before, still whole in "<base>/<transfer>" (every file at its size and time),
    // so it isn't fetched again: lists its top-level paths, and marks it the newest for tidy()
    bool existing(const std::string& base, const clipbundle::file_manifest& manifest, std::vector<std::string>& topLevel);

    // Removes an unfinished copy
    void discard(const Incoming& in);

    // Deletes copies past the newest keep or older than maxAgeSeconds, and unfinished ones,
    // except the transfer named keepTransfer
    void tidy(const std::string& base, size_t keep, long maxAgeSeconds, const std::string& keepTransfer = std::string());

    // Free bytes on the volume holding path (or its nearest existing parent); 0 if unknown
    uint64_t freeBytes(const std::string& path);
}
