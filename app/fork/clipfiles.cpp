#include "clipfiles.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <utility>

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/time.h>
#include <unistd.h>

namespace ClipFiles
{
namespace
{
    namespace fs = std::filesystem;

    const char* const k_PartialSuffix = ".partial";

    std::string baseName(std::string path)
    {
        while (path.size() > 1 && path.back() == '/') {
            path.pop_back();
        }
        size_t slash = path.rfind('/');
        return slash == std::string::npos ? path : path.substr(slash + 1);
    }

    // Finder's folder settings and the "._" files other volumes keep for it: of no use on the PC
    bool macOnly(const std::string& name)
    {
        return name == ".DS_Store" || name.compare(0, 2, "._") == 0;
    }

    class Walker
    {
    public:
        explicit Walker(Outgoing& out) : m_Out(out) {}

        bool addRoot(const std::string& path)
        {
            struct stat st;
            std::string name = baseName(path);
            if (name.empty() || name == "/" || stat(path.c_str(), &st) != 0) {
                m_Out.unreadable++;
                return true;
            }
            bool directory = S_ISDIR(st.st_mode);
            if (!directory && !S_ISREG(st.st_mode)) {
                m_Out.unreadable++;
                return true;
            }
            if (!clipbundle::well_formed_path(name)) {
                m_Out.unreadable++;
                return true;
            }
            if (!add(path, name, directory, static_cast<uint64_t>(st.st_size), st.st_mtime)) {
                return false;
            }
            return !directory || walk(path, name);
        }

    private:
        bool add(const std::string& path, const std::string& relative, bool directory, uint64_t size, int64_t mtime)
        {
            if (m_Out.manifest.entries.size() >= clipbundle::k_max_file_entries) {
                return false;
            }
            if (!directory && size > clipbundle::k_max_file_bytes - m_Bytes) {
                return false;
            }
            m_Bytes += directory ? 0 : size;

            clipbundle::file_entry entry;
            entry.path = relative;
            entry.size = directory ? 0 : size;
            entry.mtime = mtime;
            entry.directory = directory;
            m_Out.manifest.entries.push_back(std::move(entry));
            m_Out.paths.push_back(path);
            return true;
        }

        bool walk(const std::string& folder, const std::string& relative)
        {
            DIR* dir = opendir(folder.c_str());
            if (dir == nullptr) {
                m_Out.unreadable++;
                return true;
            }
            std::vector<std::string> names;
            while (struct dirent* item = readdir(dir)) {
                std::string name = item->d_name;
                if (name != "." && name != ".." && !macOnly(name)) {
                    names.push_back(std::move(name));
                }
            }
            closedir(dir);

            // In name order, so the same folder gives the same manifest
            std::sort(names.begin(), names.end());
            for (const std::string& name : names) {
                std::string path = folder + "/" + name;
                std::string child = relative + "/" + name;
                struct stat st;
                // Links are left out: they could lead out of the folder, or around in a loop
                if (lstat(path.c_str(), &st) != 0 || !(S_ISDIR(st.st_mode) || S_ISREG(st.st_mode)) ||
                        !clipbundle::well_formed_path(child)) {
                    m_Out.unreadable++;
                    continue;
                }
                bool directory = S_ISDIR(st.st_mode);
                if (!add(path, child, directory, static_cast<uint64_t>(st.st_size), st.st_mtime) ||
                        (directory && !walk(path, child))) {
                    return false;
                }
            }
            return true;
        }

        Outgoing& m_Out;
        uint64_t m_Bytes = 0;
    };

    std::string join(const std::string& folder, const std::string& relative)
    {
        return folder + "/" + relative;
    }

    void setTime(int fd, int64_t mtime)
    {
        if (mtime == 0) {
            return;
        }
        struct timespec times[2];
        times[0].tv_sec = mtime;
        times[0].tv_nsec = 0;
        times[1] = times[0];
        futimens(fd, times);
    }

    // The folder's own time, which tidy() orders copies by
    int64_t modified(const std::string& path)
    {
        struct stat st;
        return stat(path.c_str(), &st) == 0 ? static_cast<int64_t>(st.st_mtime) : 0;
    }

    std::vector<std::string> topLevelPaths(const std::string& folder, const clipbundle::file_manifest& manifest,
                                           const std::vector<std::string>& local)
    {
        std::vector<std::string> paths;
        for (size_t index : clipbundle::top_level(manifest)) {
            if (!local[index].empty()) {
                paths.push_back(join(folder, local[index]));
            }
        }
        return paths;
    }
}

bool share(const std::vector<std::string>& roots, Outgoing& out)
{
    out = Outgoing();
    Walker walker(out);
    for (const std::string& root : roots) {
        if (!walker.addRoot(root)) {
            out.manifest.entries.clear();
            out.paths.clear();
            return false;
        }
    }
    out.manifest.transfer = clipbundle::transfer_id(out.manifest.entries);
    return true;
}

ReadResult readChunk(const std::string& path, const clipbundle::file_entry& entry, uint64_t offset, std::string& data)
{
    data.clear();
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        return ReadResult::Failed;
    }

    // A file that changed since it was copied would arrive as a mix of the two
    struct stat st;
    if (fstat(fd, &st) != 0 || static_cast<uint64_t>(st.st_size) != entry.size || static_cast<int64_t>(st.st_mtime) != entry.mtime) {
        close(fd);
        return ReadResult::Changed;
    }
    if (offset > entry.size) {
        close(fd);
        return ReadResult::Failed;
    }

    size_t length = static_cast<size_t>(std::min<uint64_t>(entry.size - offset, clipbundle::k_file_chunk_bytes));
    data.resize(length);
    size_t done = 0;
    while (done < length) {
        ssize_t count = pread(fd, &data[done], length - done, static_cast<off_t>(offset + done));
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            close(fd);
            data.clear();
            return ReadResult::Failed;
        }
        done += static_cast<size_t>(count);
    }
    close(fd);
    return ReadResult::Ok;
}

bool prepare(const std::string& base, const clipbundle::file_manifest& manifest, Incoming& in)
{
    in = Incoming();
    in.folder = join(base, manifest.transfer + k_PartialSuffix);
    in.local = clipbundle::local_paths(manifest);

    std::error_code ec;
    fs::remove_all(in.folder, ec);
    fs::create_directories(in.folder, ec);
    if (ec) {
        return false;
    }

    // Folders and empty files now, as no chunk comes for them
    bool any = false;
    for (size_t i = 0; i < manifest.entries.size(); i++) {
        if (in.local[i].empty()) {
            continue;
        }
        const clipbundle::file_entry& entry = manifest.entries[i];
        std::string path = join(in.folder, in.local[i]);
        if (entry.directory) {
            fs::create_directories(path, ec);
            any = any || !ec;
            continue;
        }
        fs::create_directories(fs::path(path).parent_path(), ec);
        int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            in.local[i].clear();
            continue;
        }
        if (entry.size == 0) {
            setTime(fd, entry.mtime);
        }
        close(fd);
        any = true;
    }
    if (!any) {
        discard(in);
        return false;
    }
    return true;
}

bool writeChunk(const Incoming& in, const clipbundle::file_manifest& manifest, size_t index, uint64_t offset, std::string_view data)
{
    if (index >= manifest.entries.size() || in.local[index].empty() || manifest.entries[index].directory) {
        return false;
    }
    const clipbundle::file_entry& entry = manifest.entries[index];
    if (offset > entry.size || data.size() > entry.size - offset) {
        return false;
    }

    int fd = open(join(in.folder, in.local[index]).c_str(), O_WRONLY);
    if (fd < 0) {
        return false;
    }
    size_t done = 0;
    while (done < data.size()) {
        ssize_t count = pwrite(fd, data.data() + done, data.size() - done, static_cast<off_t>(offset + done));
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            close(fd);
            return false;
        }
        done += static_cast<size_t>(count);
    }
    if (offset + data.size() == entry.size) {
        setTime(fd, entry.mtime);
    }
    return close(fd) == 0;
}

bool complete(const std::string& base, Incoming& in, const clipbundle::file_manifest& manifest, std::vector<std::string>& topLevel)
{
    std::string final = join(base, manifest.transfer);
    std::error_code ec;
    fs::remove_all(final, ec);
    fs::rename(in.folder, final, ec);
    if (ec) {
        return false;
    }
    in.folder = final;
    topLevel = topLevelPaths(final, manifest, in.local);
    return !topLevel.empty();
}

bool existing(const std::string& base, const clipbundle::file_manifest& manifest, std::vector<std::string>& topLevel)
{
    topLevel.clear();
    std::string folder = join(base, manifest.transfer);
    std::vector<std::string> local = clipbundle::local_paths(manifest);
    for (size_t i = 0; i < manifest.entries.size(); i++) {
        if (local[i].empty()) {
            continue;
        }
        const clipbundle::file_entry& entry = manifest.entries[i];
        struct stat st;
        if (stat(join(folder, local[i]).c_str(), &st) != 0 || S_ISDIR(st.st_mode) != entry.directory) {
            return false;
        }
        if (!entry.directory && (static_cast<uint64_t>(st.st_size) != entry.size ||
                                 (entry.mtime != 0 && static_cast<int64_t>(st.st_mtime) != entry.mtime))) {
            return false;
        }
    }

    topLevel = topLevelPaths(folder, manifest, local);
    if (topLevel.empty()) {
        return false;
    }
    utimes(folder.c_str(), nullptr);
    return true;
}

void discard(const Incoming& in)
{
    if (!in.folder.empty()) {
        std::error_code ec;
        fs::remove_all(in.folder, ec);
    }
}

void tidy(const std::string& base, size_t keep, long maxAgeSeconds, const std::string& keepTransfer)
{
    std::error_code ec;
    std::vector<std::pair<int64_t, std::string>> copies;
    for (const auto& item : fs::directory_iterator(base, ec)) {
        std::string name = item.path().filename().string();
        std::string transfer = name;
        bool partial = name.size() > strlen(k_PartialSuffix) &&
                       name.compare(name.size() - strlen(k_PartialSuffix), std::string::npos, k_PartialSuffix) == 0;
        if (partial) {
            transfer = name.substr(0, name.size() - strlen(k_PartialSuffix));
        }
        if (!clipbundle::valid_transfer_id(transfer) || transfer == keepTransfer) {
            continue;
        }
        if (partial) {
            // Left from a copy that stopped
            std::error_code removed;
            fs::remove_all(item.path(), removed);
            continue;
        }
        copies.emplace_back(modified(item.path().string()), item.path().string());
    }

    std::sort(copies.begin(), copies.end(), [](const auto& a, const auto& b) {
        return a.first > b.first;
    });
    int64_t now = static_cast<int64_t>(time(nullptr));
    for (size_t i = 0; i < copies.size(); i++) {
        if (i >= keep || now - copies[i].first > maxAgeSeconds) {
            std::error_code removed;
            fs::remove_all(copies[i].second, removed);
        }
    }
}

uint64_t freeBytes(const std::string& path)
{
    fs::path at(path);
    while (!at.empty()) {
        struct statvfs info;
        if (statvfs(at.c_str(), &info) == 0) {
            return static_cast<uint64_t>(info.f_bavail) * static_cast<uint64_t>(info.f_frsize);
        }
        if (at == at.parent_path()) {
            break;
        }
        at = at.parent_path();
    }
    return 0;
}
}
