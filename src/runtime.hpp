#pragma once
static bool launchClient(SOCKET s) {
    uintptr_t thread =
        _beginthreadex(nullptr, 256 * 1024, clientThread, (void *)(uintptr_t)s, 0, nullptr);
    if (!thread)
        return false;
    CloseHandle((HANDLE)thread);
    return true;
}
static BOOL WINAPI consoleStop(DWORD code) {
    if (code == CTRL_C_EVENT || code == CTRL_BREAK_EVENT || code == CTRL_CLOSE_EVENT ||
        code == CTRL_SHUTDOWN_EVENT) {
        try {
            Lock lock(&maintenance);
            if (!passive)
                updateEndpoints(false);
            paused = true;
            SetEvent(stopEvent);
            return TRUE;
        } catch (...) {
            return FALSE;
        }
    }
    return FALSE;
}
static void tokenFile(bool prepare) {
    wstring path = dir + L"\\route.key";
    if (prepare) {
        Handle f(CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                             FILE_ATTRIBUTE_NORMAL, nullptr));
        if (f.h != INVALID_HANDLE_VALUE) {
            unsigned char random[32]{};
            require(BCryptGenRandom(nullptr, random, sizeof(random),
                                    BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0,
                    "random generation failed");
            string s;
            for (size_t i = 0; i < sizeof(random); ++i) {
                unsigned char c = random[i];
                s += "0123456789abcdef"[c >> 4];
                s += "0123456789abcdef"[c & 15];
            }
            writeAll(f.h, s);
        } else
            require(GetLastError() == ERROR_FILE_EXISTS, "cannot prepare key");
    }
    token = readFile(path, 64);
    require(token.size() == 64, "invalid route key");
    for (size_t i = 0; i < token.size(); ++i)
        require(hex(token[i]) >= 0, "invalid route key");
    localBase = "http://127.0.0.1" +
                (configuredPort == 80 ? string() : ":" + std::to_string(configuredPort)) + "/" +
                token + "/";
}
static bool localCommand(bool stop, bool print) {
    Internet session(WinHttpOpen(nullptr, WINHTTP_ACCESS_TYPE_NO_PROXY, nullptr, nullptr, 0));
    require(session.h != nullptr, "local client failed");
    WinHttpSetTimeouts(session.h, 3000, 3000, 5000, 10000);
    Internet conn(WinHttpConnect(session.h, L"127.0.0.1", configuredPort, 0));
    Internet req(
        WinHttpOpenRequest(conn.h, stop ? L"POST" : L"GET",
                           wide("/" + token + (stop ? "/control/stop" : "/health")).c_str(),
                           nullptr, nullptr, nullptr, 0));
    if (!req.h)
        return false;
    DWORD disable =
        WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_AUTHENTICATION | WINHTTP_DISABLE_COOKIES;
    WinHttpSetOption(req.h, WINHTTP_OPTION_DISABLE_FEATURE, &disable, sizeof(disable));
    if (!WinHttpSendRequest(req.h, nullptr, 0, nullptr, 0, 0, 0) ||
        !WinHttpReceiveResponse(req.h, nullptr))
        return false;
    DWORD code = 0, n = sizeof(code);
    require(WinHttpQueryHeaders(req.h, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                nullptr, &code, &n, nullptr) &&
                code == 200,
            "helper refused operation");
    if (print) {
        char b[4096];
        DWORD count = 0;
        require(WinHttpReadData(req.h, b, sizeof(b), &count) != 0, "health read failed");
        fwrite(b, 1, count, stdout);
        std::fputc('\n', stdout);
    }
    return true;
}

static int runBridge(int argc, wchar_t **argv) {
    try {
        require(argc <= 2, "one mode at a time");
        wstring mode = argc == 2 ? argv[1] : L"";
        require(mode.empty() || mode == L"--passive" || mode == L"--validate" ||
                    mode == L"--prepare" || mode == L"--restore" || mode == L"--stop" ||
                    mode == L"--probe",
                "unknown option");
        std::vector<wchar_t> exeBuffer(32768);
        wchar_t *exe = exeBuffer.data();
        require(GetModuleFileNameW(nullptr, exe, 32768) > 0, "executable path failed");
        dir = exe;
        dir = dir.substr(0, dir.find_last_of(L"\\"));
        if (!dataOverride.empty())
            dir = dataOverride;
        if (mode.empty() || mode == L"--passive")
            logPath = dir + L"\\sidepiece.log";
        tokenFile(mode == L"--prepare");
        if (mode == L"--prepare" || mode == L"--validate") {
            parseRules(readFile(dir + L"\\config.json", 65536));
            return 0;
        }
        if (mode == L"--probe" || mode == L"--stop") {
            require(localCommand(mode == L"--stop", mode == L"--probe"), "helper not reachable");
            return 0;
        }
        std::vector<wchar_t> pdBuffer(32768);
        wchar_t *pd = pdBuffer.data();
        DWORD pl = GetEnvironmentVariableW(L"ProgramData", pd, 32768);
        require(pl > 0 && pl < 32768, "ProgramData unavailable");
        wstring root = wstring(pd) + L"\\NVIDIA Corporation\\NVIDIA App\\";
        if (!nvidiaOverride.empty())
            root = nvidiaOverride + L"\\";
        files[0] = root + L"NvConfig\\LocalizedConfig.json";
        files[1] = root + L"UpdateFramework\\profile-catalog\\component_profiles.json";
        if (mode == L"--restore") {
            require(!localCommand(false, false), "helper running; use --stop");
            updateEndpoints(false);
            return 0;
        }
        passive = mode == L"--passive";
        WSADATA wd{};
        require(WSAStartup(MAKEWORD(2, 2), &wd) == 0, "Winsock startup failed");
        Socket listener(socket(AF_INET, SOCK_STREAM, IPPROTO_TCP));
        require(listener.s != INVALID_SOCKET, "socket failed");
        BOOL exclusive = TRUE;
        require(setsockopt(listener.s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (char *)&exclusive,
                           sizeof(exclusive)) == 0,
                "exclusive bind failed");
        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = htons(configuredPort);
        require(bind(listener.s, (sockaddr *)&addr, sizeof(addr)) == 0 &&
                    listen(listener.s, 8) == 0,
                "cannot bind loopback port 80; NVIDIA untouched");
        Handle stop(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
            drained(CreateEventW(nullptr, TRUE, TRUE, nullptr));
        stopEvent = stop.h;
        drainedEvent = drained.h;
        require(stop.h && drained.h, "events unavailable");
        WSAEVENT acceptEvent = WSACreateEvent();
        require(acceptEvent != WSA_INVALID_EVENT &&
                    WSAEventSelect(listener.s, acceptEvent, FD_ACCEPT | FD_CLOSE) == 0,
                "listener event failed");
        _Analysis_assume_(acceptEvent != nullptr);
        Internet session(WinHttpOpen(nullptr, WINHTTP_ACCESS_TYPE_NO_PROXY, nullptr, nullptr, 0));
        require(session.h != nullptr, "WinHTTP startup failed");
        require(WinHttpSetTimeouts(session.h, 10000, 10000, 30000, 30000) != 0,
                "upstream timeout failed");
        DWORD max = 8;
        WinHttpSetOption(session.h, WINHTTP_OPTION_MAX_CONNS_PER_SERVER, &max, sizeof(max));
        WinHttpSetOption(session.h, WINHTTP_OPTION_MAX_CONNS_PER_1_0_SERVER, &max, sizeof(max));
        Internet conn(WinHttpConnect(session.h, L"gfwsl.geforce.com", 443, 0));
        require(conn.h != nullptr, "WinHTTP connection failed");
        upstream = conn.h;
        HANDLE watches[2] = {INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE};
        std::vector<HANDLE> events = {stop.h, acceptEvent};
        if (!passive) {
            for (int i = 0; i < 2; ++i) {
                wstring parent = files[i].substr(0, files[i].find_last_of(L"\\"));
                watches[i] = FindFirstChangeNotificationW(parent.c_str(), FALSE,
                                                          FILE_NOTIFY_CHANGE_FILE_NAME |
                                                              FILE_NOTIFY_CHANGE_LAST_WRITE);
                require(watches[i] != INVALID_HANDLE_VALUE, "cannot watch NVIDIA settings");
                events.push_back(watches[i]);
            }
            try {
                updateEndpoints(true);
            } catch (...) {
                try {
                    updateEndpoints(false);
                } catch (...) {
                }
                throw;
            }
        }
        logPath = dir + L"\\sidepiece.log";
        if (!scmMode)
            SetConsoleCtrlHandler(consoleStop, TRUE);
        runtimeStarted();
        diagnostic("ready: native WinHTTP; loopback only; configured metadata overrides");
        bool abnormal = false;
        for (;;) {
            DWORD which =
                WaitForMultipleObjects((DWORD)events.size(), events.data(), FALSE, INFINITE);
            if (which == WAIT_OBJECT_0)
                break;
            if (which == WAIT_OBJECT_0 + 1) {
                WSANETWORKEVENTS ne{};
                if (WSAEnumNetworkEvents(listener.s, acceptEvent, &ne) != 0 ||
                    (ne.lNetworkEvents & FD_CLOSE)) {
                    abnormal = true;
                    break;
                }
                for (;;) {
                    SOCKET s = accept(listener.s, nullptr, nullptr);
                    if (s == INVALID_SOCKET)
                        break;
                    u_long blocking = 0;
                    WSAEventSelect(s, nullptr, 0);
                    ioctlsocket(s, FIONBIO, &blocking);
                    DWORD timeout = 10000;
                    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
                    timeout = 60000;
                    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));
                    if (active.load() >= 8) {
                        closesocket(s);
                        continue;
                    }
                    ResetEvent(drained.h);
                    ++active;
                    if (!launchClient(s)) {
                        closesocket(s);
                        if (active.fetch_sub(1) == 1)
                            SetEvent(drained.h);
                    }
                }
            } else if (which >= WAIT_OBJECT_0 + 2 && which < WAIT_OBJECT_0 + events.size()) {
                FindNextChangeNotification(events[which]);
                Lock lock(&maintenance);
                if (!paused)
                    try {
                        updateEndpoints(true);
                    } catch (...) {
                        diagnostic("configuration maintenance deferred; other settings preserved");
                    }
            } else {
                abnormal = true;
                break;
            }
        }
        if (!scmMode)
            SetConsoleCtrlHandler(consoleStop, FALSE);
        if (abnormal) {
            Lock lock(&maintenance);
            if (!passive)
                updateEndpoints(false);
            paused = true;
        }
        for (HANDLE h : watches)
            if (h != INVALID_HANDLE_VALUE)
                FindCloseChangeNotification(h);
        WSACloseEvent(acceptEvent);
        shutdown(listener.s, SD_BOTH);
        // Keep shared handles alive until workers finish; terminate the process if the drain
        // ceiling expires.
        DWORD drainedResult = WAIT_TIMEOUT;
        for (unsigned i = 0; i < 14; ++i) {
            drainedResult = WaitForSingleObject(drained.h, 5000);
            if (drainedResult != WAIT_TIMEOUT)
                break;
            if (scmMode)
                reportService(SERVICE_STOP_PENDING);
        }
        if (drainedResult != WAIT_OBJECT_0) {
            diagnostic("worker drain timed out; endpoints restored; terminating process");
            ExitProcess(ERROR_TIMEOUT);
        }
        diagnostic("stopped; official endpoints restored (passive mode leaves settings untouched)");
        return abnormal ? 1 : 0;
    } catch (const std::exception &e) {
        diagnostic(e.what());
        return 1;
    }
}
