<div align="center">
  <img src="assets/logo.svg" width="120" alt="Sidepiece external GPU heart logo">
  <h1>GeForce Sidepiece</h1>
  <p><strong>When NVIDIA App won’t commit to your eGPU.</strong><br><sub>NOT <strong>spy</strong>ware, I promise!</sub></p>
  <p>
    <a href="https://github.com/JediRhymeTrix/sidepiece/actions/workflows/ci.yml"><img src="https://github.com/JediRhymeTrix/sidepiece/actions/workflows/ci.yml/badge.svg" alt="Windows CI"></a>
    <a href="https://github.com/JediRhymeTrix/sidepiece/releases"><img src="https://img.shields.io/github/v/release/JediRhymeTrix/sidepiece?include_prereleases" alt="Release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
    <img src="https://img.shields.io/badge/platform-Windows%20x64-0078D4" alt="Windows x64">
    <img src="https://img.shields.io/badge/runtime-native%20C%2B%2B-a3e635" alt="Native C++">
  </p>
  <p>A tiny, reversible NVIDIA App metadata bridge for desktop eGPUs misidentified as laptop GPUs.</p>
</div>

## Is this your problem?
Your Thunderbolt, USB4 or OCuLink enclosure contains a **desktop NVIDIA GPU**, but NVIDIA App fails to discover a newer appropriate driver because its driver-discovery request labels that GPU as a laptop (`iLp: "1"`). Sidepiece conditionally changes that metadata to `"0"` for **only the explicitly allowlisted GPU IDs**, then forwards the request to NVIDIA over verified HTTPS.

This is a workaround for that specific classification issue—not a general NVIDIA App repair tool. It does not install drivers, enable/disable GPUs, spoof hardware, bypass compatibility checks, change certificates or set a system-wide proxy. An internal laptop GPU can remain denied, even when disabled in Device Manager. Mixed-device requests are not rewritten unless every device is allowlisted and none is denied.

**Unofficial and unaffiliated with NVIDIA.** GeForce and NVIDIA are their respective owners’ trademarks. The name and tagline are jokes, not claims about any person.

## Tiny on purpose
- Native C++ using Windows Winsock, WinHTTP and BCrypt; **no third-party runtime dependencies**.
- One process under native Windows Service Control Manager: no resident PowerShell, Python, Node, .NET host or service wrapper.
- Event-driven idle loop, streaming responses and at most eight concurrent clients.
- The tested predecessor was **about 256 KiB on disk**, **3.57 MiB private memory**, and **15.45 MiB working set** after live requests; idle CPU time did not increase during a 15-second sample.

Those measurements describe the predecessor on one Windows machine, **not a guaranteed v0.1.0 benchmark**. TLS caches, traffic and Windows versions affect memory. Working set is not private memory. A pdsvc/cmd/conhost wrapper adds its own overhead; the measured predecessor’s entire wrapped tree was 13.90 MiB private / 38.65 MiB working set. Native SCM hosting avoids those wrapper processes. See [measurement instructions](docs/development.md).

## Quick setup
Requires Windows x64, NVIDIA App, administrator access for setup, and free loopback port 80. Initial binaries are unsigned: verify the checksum and review the source; there is no claim of signing or SmartScreen reputation.

1. Download the Windows x64 ZIP and `SHA256SUMS.txt` from [Releases](https://github.com/JediRhymeTrix/sidepiece/releases). Compare `Get-FileHash <zip> -Algorithm SHA256` with the checksum, then extract the ZIP.
2. In PowerShell, run ` .\scripts\Setup.ps1 -Action ListGpus` and identify the **external desktop GPU**. [Convert its PCI hardware ID to the exact metadata ID](docs/configuration.md#selecting-a-gpu).
3. In an elevated PowerShell window in the extracted folder, run ` .\scripts\Setup.ps1 -DeviceId 'ABCD_10DE_1234_5678_1'`, replacing the synthetic example. No device is allowlisted automatically.
4. Reopen NVIDIA App and check driver discovery. If it still uses cached endpoints, close and reopen the app.

Do not install alongside an existing bridge. Stop and restore its endpoints **through its current manager** before switching hosts. Setup refuses an occupied port or a foreign endpoint; do not force it.

## Control and recovery
- Status: ` .\scripts\Setup.ps1 -Action Status`
- Stop and restore official URLs: `Stop-Service GeForceSidepiece` (elevated).
- Resume: `Start-Service GeForceSidepiece`.
- Update from a newly extracted release: ` .\scripts\Setup.ps1 -Action Update`. Custom rules are preserved.
- Uninstall: ` .\scripts\Setup.ps1 -Action Uninstall`. URLs are restored; configuration, backups and binaries are retained for recovery.

If the process crashes or is forcibly killed, the local URLs may remain redirected. Keep `route.key` and use the installed executable with `--data-dir 'C:\ProgramData\GeForceSidepiece' --restore` **only after the service has stopped**. See [hosting and recovery](docs/hosting.md) before deleting files.

## Configurable, not a hard-coded patch
`C:\ProgramData\GeForceSidepiece\config.json` controls explicit device and endpoint allow/deny lists, exact GET endpoint matches and conditional scalar overrides. Rules are reloaded per request; invalid rules disable rewriting while ordinary forwarding continues. Validate edits with the installed executable’s `--data-dir ... --validate` command. Blacklists win. The upstream host stays fixed to `gfwsl.geforce.com`.

Start with [the example](config/config.example.json), [schema](config/schema.json), and [configuration guide](docs/configuration.md). Extra endpoint names and top-level scalar overrides require configuration, not recompilation. Request bodies and responses are not rewritten.

## How it works
NVIDIA App → tokenized loopback listener → narrow metadata rules → NVIDIA HTTPS API.

Sidepiece edits only the owned URL string spans in NVIDIA App’s `NvConfig/LocalizedConfig.json` and `UpdateFramework/profile-catalog/component_profiles.json`. Other bytes are retained. It stages replacements, detects concurrent changes, keeps original backups, and refuses unknown destinations rather than taking them over. While running, directory notifications trigger reconciliation after NVIDIA rewrites its settings.

The local route key is a capability secret, not a security boundary against administrator access or processes able to read NVIDIA configuration. Never post it, raw endpoint URLs or unredacted NVIDIA logs.

## Documentation
- [Configuration and GPU selection](docs/configuration.md)
- [SCM, foreground/pdsvc, stop and crash recovery](docs/hosting.md)
- [Security model](SECURITY.md)
- [Build, tests and footprint measurements](docs/development.md)
- [Release process](docs/releases.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)

## Compatibility and verification limits
The predecessor’s live API comparisons confirmed byte-identical expected responses for desktop, laptop and unrelated requests. That does **not** establish that every NVIDIA App version refreshes its UI correctly. Real NVIDIA App GUI confirmation and broad hardware testing remain outstanding. Fixture tests are not hardware certification. NVIDIA can change these private settings or API formats; unknown layouts fail closed instead of being guessed.

If a driver is genuinely unavailable for your GPU/OS/channel, Sidepiece cannot make it compatible. If NVIDIA fixes the classification, stop and uninstall this workaround.
