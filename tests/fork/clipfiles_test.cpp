// Tests for app/fork/clipfiles.*: a Finder copy walked into a manifest and read in chunks, a copy from
// the PC written into the cache, and old copies cleared. Uses a temporary folder.
//   clang++ -std=c++17 -DCLIPBUNDLE_WITH_ZLIB -Iapp/fork tests/fork/clipfiles_test.cpp app/fork/clipfiles.cpp app/fork/clipbundle.cpp -lz

#include "clipfiles.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

#include <sys/stat.h>
#include <unistd.h>

namespace fs = std::filesystem;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static void writeFile(const fs::path& path, const std::string& data)
{
    std::ofstream out(path, std::ios::binary);
    out << data;
}

static std::string readFile(const fs::path& path)
{
    std::ifstream in(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

static long long mtimeOf(const fs::path& path)
{
    struct stat st;
    return stat(path.c_str(), &st) == 0 ? static_cast<long long>(st.st_mtime) : -1;
}

static int indexOf(const clipbundle::file_manifest& m, const std::string& path)
{
    for (size_t i = 0; i < m.entries.size(); i++) {
        if (m.entries[i].path == path) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

static std::string bigData()
{
    std::string data(clipbundle::k_file_chunk_bytes + 1234, '\0');
    for (size_t i = 0; i < data.size(); i++) {
        data[i] = static_cast<char>((i * 31 + 7) & 0xFF);
    }
    return data;
}

int main()
{
    char pattern[] = "/tmp/clipfiles-test-XXXXXX";
    const char* made = mkdtemp(pattern);
    if (made == nullptr) {
        std::printf("FAIL: no temporary folder\n");
        return 1;
    }
    fs::path root(made);
    fs::path source = root / "source";
    fs::create_directories(source / "Photos" / "Raw");
    fs::create_directories(source / "Empty");
    writeFile(source / "Photos" / "b.jpg", "bee");
    writeFile(source / "Photos" / "a.jpg", "ay");
    writeFile(source / "Photos" / "Raw" / "big.dng", bigData());
    writeFile(source / "Photos" / ".DS_Store", "finder");
    writeFile(source / "Photos" / "._a.jpg", "appledouble");
    writeFile(source / "notes.txt", "");
    fs::create_symlink("/etc", source / "Photos" / "outside");

    // ---- A Finder copy: two files and two folders
    ClipFiles::Outgoing out;
    CHECK(ClipFiles::share({(source / "Photos").string(), (source / "notes.txt").string(), (source / "Empty").string(),
                            (source / "missing").string()}, out));
    CHECK(out.unreadable == 2);  // the link inside, and the missing root
    CHECK(clipbundle::valid_transfer_id(out.manifest.transfer));
    CHECK(out.manifest.entries.size() == out.paths.size());
    std::vector<std::string> expected = {"Photos", "Photos/Raw", "Photos/Raw/big.dng", "Photos/a.jpg", "Photos/b.jpg", "notes.txt", "Empty"};
    CHECK(out.manifest.entries.size() == expected.size());
    for (size_t i = 0; i < expected.size() && i < out.manifest.entries.size(); i++) {
        CHECK(out.manifest.entries[i].path == expected[i]);
    }
    int big = indexOf(out.manifest, "Photos/Raw/big.dng");
    CHECK(big >= 0 && out.manifest.entries[big].size == bigData().size());
    CHECK(out.manifest.entries[0].directory && !out.manifest.entries[2].directory);

    // The same copy read again has the same id
    ClipFiles::Outgoing again;
    CHECK(ClipFiles::share({(source / "Photos").string(), (source / "notes.txt").string(), (source / "Empty").string()}, again));
    CHECK(again.manifest.transfer == out.manifest.transfer);

    // ---- Chunks
    std::string sent;
    if (big >= 0) {
        const clipbundle::file_entry& entry = out.manifest.entries[big];
        std::string chunk;
        CHECK(ClipFiles::readChunk(out.paths[big], entry, 0, chunk) == ClipFiles::ReadResult::Ok);
        CHECK(chunk.size() == clipbundle::k_file_chunk_bytes);
        sent = chunk;
        CHECK(ClipFiles::readChunk(out.paths[big], entry, chunk.size(), chunk) == ClipFiles::ReadResult::Ok);
        CHECK(chunk.size() == 1234);
        sent += chunk;
        CHECK(sent == bigData());
        CHECK(ClipFiles::readChunk(out.paths[big], entry, entry.size + 1, chunk) == ClipFiles::ReadResult::Failed);
    }
    int a = indexOf(out.manifest, "Photos/a.jpg");
    writeFile(source / "Photos" / "a.jpg", "changed");
    std::string ignored;
    CHECK(a >= 0 && ClipFiles::readChunk(out.paths[a], out.manifest.entries[a], 0, ignored) == ClipFiles::ReadResult::Changed);

    // ---- The copy arriving from the PC
    fs::path base = root / "cache";
    ClipFiles::Incoming in;
    CHECK(ClipFiles::prepare(base.string(), out.manifest, in));
    CHECK(fs::is_directory(fs::path(in.folder) / "Photos" / "Raw"));
    CHECK(fs::is_directory(fs::path(in.folder) / "Empty"));
    CHECK(fs::exists(fs::path(in.folder) / "notes.txt"));
    if (big >= 0) {
        CHECK(ClipFiles::writeChunk(in, out.manifest, big, 0, std::string_view(sent).substr(0, clipbundle::k_file_chunk_bytes)));
        CHECK(!ClipFiles::writeChunk(in, out.manifest, big, clipbundle::k_file_chunk_bytes, sent.substr(clipbundle::k_file_chunk_bytes) + "!"));
        CHECK(ClipFiles::writeChunk(in, out.manifest, big, clipbundle::k_file_chunk_bytes, std::string_view(sent).substr(clipbundle::k_file_chunk_bytes)));
    }
    CHECK(!ClipFiles::writeChunk(in, out.manifest, 0, 0, "x"));  // a folder
    CHECK(!ClipFiles::writeChunk(in, out.manifest, 99, 0, "x"));
    for (const char* name : {"Photos/a.jpg", "Photos/b.jpg"}) {
        int i = indexOf(out.manifest, name);
        CHECK(i >= 0 && ClipFiles::writeChunk(in, out.manifest, i, 0, std::string(out.manifest.entries[i].size, 'z')));
    }

    std::vector<std::string> top;
    CHECK(ClipFiles::complete(base.string(), in, out.manifest, top));
    CHECK(top.size() == 3);
    fs::path landed = base / out.manifest.transfer;
    CHECK(in.folder == landed.string());
    CHECK(!fs::exists(base / (out.manifest.transfer + ".partial")));
    CHECK(readFile(landed / "Photos" / "Raw" / "big.dng") == bigData());
    if (big >= 0) {
        CHECK(mtimeOf(landed / "Photos" / "Raw" / "big.dng") == out.manifest.entries[big].mtime);
    }

    // ---- The same copy again: what's in the cache is used, unless it changed there
    std::vector<std::string> reused;
    CHECK(ClipFiles::existing(base.string(), out.manifest, reused));
    CHECK(reused == top);
    clipbundle::file_manifest other = out.manifest;
    other.transfer = std::string(32, 'f');
    CHECK(!ClipFiles::existing(base.string(), other, reused));
    CHECK(reused.empty());
    writeFile(landed / "Photos" / "b.jpg", "longer");
    CHECK(!ClipFiles::existing(base.string(), out.manifest, reused));

    // ---- Tidying: unfinished copies go, and old ones past the newest few
    fs::create_directories(base / (std::string(32, 'a') + ".partial"));
    fs::create_directories(base / std::string(32, 'b'));
    fs::create_directories(base / std::string(32, 'c'));
    fs::create_directories(base / "not-a-copy");
    ClipFiles::tidy(base.string(), 2, 24 * 3600, out.manifest.transfer);
    CHECK(!fs::exists(base / (std::string(32, 'a') + ".partial")));
    CHECK(fs::exists(landed));  // the one kept by name
    CHECK(fs::exists(base / "not-a-copy"));
    CHECK(fs::exists(base / std::string(32, 'b')) && fs::exists(base / std::string(32, 'c')));
    ClipFiles::tidy(base.string(), 1, 24 * 3600, out.manifest.transfer);
    CHECK(int(fs::exists(base / std::string(32, 'b'))) + int(fs::exists(base / std::string(32, 'c'))) == 1);
    ClipFiles::tidy(base.string(), 3, -1);  // everything is older than that
    CHECK(!fs::exists(landed));

    CHECK(ClipFiles::freeBytes((base / "missing" / "deeper").string()) > 0);

    std::error_code ec;
    fs::remove_all(root, ec);

    if (s_Failures == 0) {
        std::printf("clipfiles: all tests passed\n");
        return 0;
    }
    std::printf("clipfiles: %d failure(s)\n", s_Failures);
    return 1;
}
