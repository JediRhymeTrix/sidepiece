# Development

## Build
Install Visual Studio 2022 C++ Build Tools with the x64 toolchain and Windows SDK. Run ` .\scripts\Build.ps1 -Analyze` from PowerShell. `vswhere` discovers MSVC; no globally configured developer shell is required. Output is in `build/`. Builds use C++17, static CRT, size optimization, `/W4 /WX`, `/analyze`, ASLR and DEP. No package manager or third-party runtime is involved. This is a scripted repeatable build, not a claim of byte-for-byte reproducible binaries.

`Build.ps1` compiles the executable and three small native test programs. Tests have a 30-second timeout. `Test-Lifecycle.ps1` checks passive foreground health/stop on a random port in temporary data. `Test-Lifecycle.ps1 -Scm` is restricted to disposable GitHub Actions runners and additionally exercises native SCM hosting under LocalService. It never redirects real NVIDIA URLs. Transaction tests create synthetic JSON files and check exact-byte restoration and invalid-layout refusal.

The initial suite contains 82 parser/routing checks, 66 HTTP integration checks and 11 configurable-rule/transaction checks. Assertions cover header handling, chunked/binary bodies, compression passthrough, CORS, redirect/auth policy, access boundaries, device vetoes and scalar overrides. Fixture coverage does not replace real GPU, driver-channel or NVIDIA App GUI testing. Windows service permissions and setup lifecycle require separate runner validation.

Format C++ with the checked-in `.clang-format`. PowerShell scripts target Windows PowerShell 5.1 and PowerShell 7. Keep native arguments explicitly quoted where paths contain spaces; check actual native exit codes rather than relying on `$ErrorActionPreference` alone.

## Source map
- `src/platform.hpp`: Win32 RAII, text/file helpers and fixed redacted diagnostics.
- `src/json.hpp`: bounded strict JSON parser with original byte spans.
- `src/rules.hpp`: schema validation and narrow metadata overrides.
- `src/endpoints.hpp`: owned URL-span edits and transactional replacement.
- `src/proxy.hpp`: Winsock framing/access control and WinHTTP streaming.
- `src/runtime.hpp`: data initialization, endpoint watches, listener and drain.
- `src/main.cpp`: CLI and native SCM host.

The modules intentionally share one small translation unit; no plugin framework or dynamic runtime is necessary. Rules are data, not executable extensions. Upstream changes must not introduce arbitrary destination configuration.

## Measure footprint honestly
Measure the actual process after a representative request and TLS initialization, not merely before the first connection. PowerShell `Get-Process -Id <pid> | Select-Object Id,PrivateMemorySize64,WorkingSet64,TotalProcessorTime` gives separate private/working-set/CPU metrics. Divide byte values by 1 MiB. Measure executable size separately with `Get-Item`.

Sample total CPU time again after an idle interval and report its delta. Record Windows version, build flags, traffic/concurrency and sample duration. For pdsvc or another wrapper, enumerate and sum its entire process tree separately; do not attribute cmd/conhost overhead to the native helper or hide it from total costs. Never trim working sets to manufacture a benchmark. A synthetic passive run does not characterize loaded TLS traffic.

## Test safety
Never run a second live instance on a developer machine already using this bridge. Fixture tests use a random loopback port, passive hosting and synthetic paths. Do not point fixture roots at real NVIDIA folders. SCM tests must run on disposable hosted runners, not a personal workstation. Never copy live route keys, requests, backup files or runtime logs into fixtures or artifacts.
