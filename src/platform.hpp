#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <windows.h>
#include <winhttp.h>
#include <bcrypt.h>
#include <process.h>
#include <algorithm>
#include <atomic>
#include <charconv>
#include <cstdio>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "bcrypt.lib")
using std::string;
using std::wstring;
static const string official = "https://gfwsl.geforce.com/";
static const string driverPrefix = "/nvidia_web_services/controller.gfeclientcontent.NG.php/"
                                   "com.nvidia.services.GFEClientContent_NG.";
static const string endpoints[] = {"getDispDrvrByDevid", "getDispDrvrDtlsByDevid"};
static void require(bool ok, const char *msg) {
    if (!ok)
        throw std::runtime_error(msg);
}
static wstring wide(const string &s, UINT cp = CP_UTF8) {
    if (s.empty())
        return {};
    int n = MultiByteToWideChar(cp, cp == CP_UTF8 ? MB_ERR_INVALID_CHARS : 0, s.data(),
                                (int)s.size(), nullptr, 0);
    require(n > 0, "invalid text");
    wstring w(n, 0);
    MultiByteToWideChar(cp, cp == CP_UTF8 ? MB_ERR_INVALID_CHARS : 0, s.data(), (int)s.size(),
                        w.data(), n);
    return w;
}
static string narrow(const wstring &s, UINT cp = CP_UTF8) {
    if (s.empty())
        return {};
    int n = WideCharToMultiByte(cp, 0, s.data(), (int)s.size(), nullptr, 0, nullptr, nullptr);
    require(n > 0, "invalid text");
    string r(n, 0);
    WideCharToMultiByte(cp, 0, s.data(), (int)s.size(), r.data(), n, nullptr, nullptr);
    return r;
}
struct Handle {
    HANDLE h = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE v = INVALID_HANDLE_VALUE) : h(v) {}
    ~Handle() {
        if (h != INVALID_HANDLE_VALUE && h)
            CloseHandle(h);
    }
    Handle(const Handle &) = delete;
};
struct Internet {
    HINTERNET h = nullptr;
    explicit Internet(HINTERNET v = nullptr) : h(v) {}
    ~Internet() {
        if (h)
            WinHttpCloseHandle(h);
    }
    Internet(const Internet &) = delete;
};
struct Socket {
    SOCKET s = INVALID_SOCKET;
    explicit Socket(SOCKET v = INVALID_SOCKET) : s(v) {}
    ~Socket() {
        if (s != INVALID_SOCKET)
            closesocket(s);
    }
    Socket(const Socket &) = delete;
};
static string readFile(const wstring &path, size_t max = 4 << 20) {
    Handle f(CreateFileW(path.c_str(), GENERIC_READ,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    require(f.h != INVALID_HANDLE_VALUE, "file unavailable");
    LARGE_INTEGER sz{};
    require(GetFileSizeEx(f.h, &sz) && sz.QuadPart >= 0 && (unsigned long long)sz.QuadPart <= max,
            "file oversized");
    string b((size_t)sz.QuadPart, 0);
    DWORD n = 0;
    require(b.empty() || (ReadFile(f.h, b.data(), (DWORD)b.size(), &n, nullptr) && n == b.size()),
            "file read failed");
    return b;
}
static void writeAll(HANDLE h, const string &b) {
    DWORD n = 0;
    require(b.empty() || (WriteFile(h, b.data(), (DWORD)b.size(), &n, nullptr) && n == b.size()),
            "file write failed");
}
// Only fixed diagnostics belong here: never log request URLs, payloads or the route key.
static wstring logPath;
static SRWLOCK logLock = SRWLOCK_INIT;
static void diagnostic(const char *message) {
    std::fprintf(stderr, "%s\n", message);
    std::fflush(stderr);
    if (logPath.empty())
        return;
    AcquireSRWLockExclusive(&logLock);
    {
        WIN32_FILE_ATTRIBUTE_DATA info{};
        if (GetFileAttributesExW(logPath.c_str(), GetFileExInfoStandard, &info) &&
            (info.nFileSizeHigh || info.nFileSizeLow >= 1024 * 1024))
            MoveFileExW(logPath.c_str(), (logPath + L".previous").c_str(),
                        MOVEFILE_REPLACE_EXISTING);
        Handle f(CreateFileW(logPath.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_DELETE,
                             nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
        if (f.h != INVALID_HANDLE_VALUE) {
            SYSTEMTIME t{};
            GetSystemTime(&t);
            char prefix[64]{};
            std::snprintf(prefix, sizeof(prefix), "%04u-%02u-%02uT%02u:%02u:%02uZ ", t.wYear,
                          t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
            string line = string(prefix) + message + "\r\n";
            DWORD n = 0;
            WriteFile(f.h, line.data(), (DWORD)line.size(), &n, nullptr);
        }
    }
    ReleaseSRWLockExclusive(&logLock);
}
static int hex(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
static string upper(string s) {
    for (char &c : s)
        if (c >= 'a' && c <= 'z')
            c -= 32;
    return s;
}
static string lower(string s) {
    for (char &c : s)
        if (c >= 'A' && c <= 'Z')
            c += 32;
    return s;
}
static string trim(string s) {
    auto a = s.find_first_not_of(" \t");
    if (a == string::npos)
        return {};
    return s.substr(a, s.find_last_not_of(" \t") - a + 1);
}
static bool starts(const string &s, const string &p) {
    return s.size() >= p.size() && s.compare(0, p.size(), p) == 0;
}
static string unescape(const string &s) {
    string o;
    o.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%') {
            require(i + 2 < s.size() && hex(s[i + 1]) >= 0 && hex(s[i + 2]) >= 0,
                    "invalid URL encoding");
            o += (char)(hex(s[i + 1]) * 16 + hex(s[i + 2]));
            i += 2;
        } else
            o += s[i];
    }
    return o;
}
