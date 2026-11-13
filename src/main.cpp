#include "core.hpp"
static bool scmMode = false;
static SERVICE_STATUS_HANDLE serviceHandle = nullptr;
static SERVICE_STATUS serviceStatus{};
static wstring dataOverride, nvidiaOverride;
static unsigned short listenPort = 80;
static bool fixtureMode = false;
static HANDLE runtimeReady = nullptr;
static void reportService(DWORD state, DWORD error = NO_ERROR) {
    if (!serviceHandle)
        return;
    serviceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    serviceStatus.dwCurrentState = state;
    serviceStatus.dwWin32ExitCode = error;
    serviceStatus.dwControlsAccepted =
        state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN : 0;
    serviceStatus.dwWaitHint =
        state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING ? 30000 : 0;
    serviceStatus.dwCheckPoint = serviceStatus.dwWaitHint ? serviceStatus.dwCheckPoint + 1 : 0;
    SetServiceStatus(serviceHandle, &serviceStatus);
}
static void runtimeStarted() {
    reportService(SERVICE_RUNNING);
    if (runtimeReady)
        SetEvent(runtimeReady);
}
static void requestStop() {
    Lock lock(&maintenance);
    if (!passive)
        updateEndpoints(false);
    paused = true;
    SetEvent(stopEvent);
}
static DWORD WINAPI serviceControl(DWORD code, DWORD, void *, void *) {
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
        reportService(SERVICE_STOP_PENDING);
        try {
            requestStop();
            return NO_ERROR;
        } catch (...) {
            reportService(SERVICE_RUNNING);
            return ERROR_WRITE_FAULT;
        }
    }
    if (code == SERVICE_CONTROL_INTERROGATE) {
        SetServiceStatus(serviceHandle, &serviceStatus);
        return NO_ERROR;
    }
    return ERROR_CALL_NOT_IMPLEMENTED;
}
#include "runtime.hpp"
static std::vector<wstring> runtimeArgs;
static void WINAPI serviceMain(DWORD, wchar_t **) {
    serviceHandle = RegisterServiceCtrlHandlerExW(L"GeForceSidepiece", serviceControl, nullptr);
    if (!serviceHandle)
        return;
    reportService(SERVICE_START_PENDING);
    std::vector<wchar_t *> argv;
    for (auto &a : runtimeArgs)
        argv.push_back(a.data());
    int result = runBridge((int)argv.size(), argv.data());
    reportService(SERVICE_STOPPED, result ? ERROR_SERVICE_SPECIFIC_ERROR : NO_ERROR);
}
int wmain(int argc, wchar_t **argv) {
    try {
        runtimeArgs.push_back(argv[0]);
        for (int i = 1; i < argc; ++i) {
            wstring arg = argv[i];
            if (arg == L"--version") {
                std::puts("GeForce Sidepiece " SIDEPIECE_VERSION);
                return 0;
            }
            if (arg == L"--help") {
                std::puts(
                    "sidepiece [--service] [--data-dir PATH] "
                    "[--prepare|--validate|--probe|--stop|--restore|--passive]\nFixture tests "
                    "only: --fixture-root PATH --port PORT (requires --passive for serving)");
                return 0;
            }
            if (arg == L"--service") {
                scmMode = true;
                continue;
            }
            if (arg == L"--data-dir" || arg == L"--fixture-root" || arg == L"--port") {
                require(i + 1 < argc, "option requires value");
                wstring value = argv[++i];
                if (arg == L"--data-dir")
                    dataOverride = value;
                if (arg == L"--fixture-root") {
                    nvidiaOverride = value;
                    fixtureMode = true;
                }
                if (arg == L"--port") {
                    unsigned long v = std::stoul(value);
                    require(v > 0 && v <= 65535, "invalid port");
                    listenPort = (unsigned short)v;
                }
                continue;
            }
            runtimeArgs.push_back(arg);
        }
        configuredPort = listenPort;
        require(listenPort == 80 || fixtureMode, "nonstandard ports are fixture-only");
        if (fixtureMode) {
            bool allowed = runtimeArgs.size() == 2 &&
                           (runtimeArgs[1] == L"--passive" || runtimeArgs[1] == L"--prepare" ||
                            runtimeArgs[1] == L"--validate" || runtimeArgs[1] == L"--restore" ||
                            runtimeArgs[1] == L"--stop" || runtimeArgs[1] == L"--probe");
            require(allowed, "fixture root requires an explicit test or control mode");
        }
        if (scmMode) {
            SERVICE_TABLE_ENTRYW table[] = {
                {const_cast<wchar_t *>(L"GeForceSidepiece"), serviceMain}, {nullptr, nullptr}};
            require(StartServiceCtrlDispatcherW(table) != 0,
                    "SCM dispatcher failed; use foreground mode outside Services");
            return 0;
        }
        std::vector<wchar_t *> args;
        for (auto &a : runtimeArgs)
            args.push_back(a.data());
        return runBridge((int)args.size(), args.data());
    } catch (const std::exception &e) {
        std::fprintf(stderr, "%s\n", e.what());
        return 1;
    }
}
