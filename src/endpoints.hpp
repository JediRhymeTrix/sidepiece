#pragma once
struct Edit {
    size_t a, b;
    string v;
};
static string editEndpoints(const string &data, bool localized, const string &from,
                            const string &to) {
    Json j(data);
    std::vector<int> targets;
    if (localized) {
        int k = 0;
        for (const char *key : {"localizedConfig", "gfwsl", "server"})
            k = j.member(k, key);
        targets.push_back(k);
    } else {
        require(j.n[0].type == '[', "invalid components");
        std::set<string> found;
        for (int c : j.n[0].arr) {
            string name = j.text(j.member(c, "componentName"));
            if (name != "grd" && name != "crd")
                continue;
            require(found.insert(name).second, "duplicate component");
            int a = j.member(c, "updateCheckerProfiles");
            require(j.n[a].type == '[' && !j.n[a].arr.empty(), "missing profiles");
            for (int p : j.n[a].arr)
                targets.push_back(j.member(p, "otaBaseUrl"));
        }
        require(found.size() == 2, "missing driver component");
    }
    std::vector<Edit> edits;
    for (int k : targets) {
        string old = j.text(k);
        if (old == to)
            continue;
        require(old == from, "unknown NVIDIA endpoint; refusing change");
        edits.push_back({j.n[k].a, j.n[k].b, "\"" + to + "\""});
    }
    std::sort(edits.begin(), edits.end(), [](const Edit &a, const Edit &b) { return a.a > b.a; });
    string result = data;
    for (const Edit &e : edits)
        result.replace(e.a, e.b - e.a, e.v);
    return result;
}
static void atomicReplace(const wstring &path, const string &before, const string &after) {
    wstring tmp = path + L".bridge-" + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    try {
        {
            Handle f(CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                 FILE_ATTRIBUTE_NORMAL, nullptr));
            require(f.h != INVALID_HANDLE_VALUE, "cannot stage configuration");
            writeAll(f.h, after);
            require(FlushFileBuffers(f.h) != 0, "cannot flush configuration");
        }
        require(readFile(path) == before, "configuration changed concurrently");
        require(ReplaceFileW(path.c_str(), tmp.c_str(), nullptr, 0, nullptr, nullptr) != 0,
                "cannot replace configuration");
    } catch (...) {
        DeleteFileW(tmp.c_str());
        throw;
    }
}
static unsigned short configuredPort = 80;
static wstring dir;
static wstring files[2];
static string token, localBase;
static SRWLOCK maintenance = SRWLOCK_INIT;
static bool paused = false, passive = false;
struct Lock {
    SRWLOCK *l;
    explicit Lock(SRWLOCK *v) : l(v) { AcquireSRWLockExclusive(l); }
    ~Lock() { ReleaseSRWLockExclusive(l); }
};
static void updateEndpoints(bool enable) {
    string before[2], after[2];
    for (int i = 0; i < 2; ++i) {
        before[i] = readFile(files[i]);
        after[i] = editEndpoints(before[i], i == 0, enable ? official : localBase,
                                 enable ? localBase : official);
    }
    int done = -1;
    try {
        for (int i = 0; i < 2; ++i) {
            if (before[i] == after[i])
                continue;
            if (enable) {
                wstring bd = dir + L"\\backups";
                require(CreateDirectoryW(bd.c_str(), nullptr) ||
                            GetLastError() == ERROR_ALREADY_EXISTS,
                        "cannot create backup directory");
                wstring bp = bd + L"\\" +
                             (i == 0 ? L"LocalizedConfig.json.native-original"
                                     : L"component_profiles.json.native-original");
                Handle f(CreateFileW(bp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                     FILE_ATTRIBUTE_NORMAL, nullptr));
                if (f.h != INVALID_HANDLE_VALUE)
                    writeAll(f.h, before[i]);
                else
                    require(GetLastError() == ERROR_FILE_EXISTS, "cannot create backup");
            }
            atomicReplace(files[i], before[i], after[i]);
            done = i;
        }
    } catch (...) {
        for (int i = done; i >= 0; --i)
            if (before[i] != after[i])
                try {
                    atomicReplace(files[i], after[i], before[i]);
                } catch (...) {
                    std::fputs("configuration rollback incomplete; run --restore\n", stderr);
                }
        throw;
    }
}
