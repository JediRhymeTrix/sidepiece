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

Those measurements describe the predecessor on one Windows machine, **not a benchmark for the current release**. TLS caches, traffic and Windows versions affect memory. Working set is not private memory. A pdsvc/cmd/conhost wrapper adds its own overhead; the measured predecessor’s entire wrapped tree was 13.90 MiB private / 38.65 MiB working set. Native SCM hosting avoids those wrapper processes. See [measurement instructions](docs/development.md).

## Install in a few clicks
**Requires:** Windows x64, NVIDIA App installed and opened at least once, administrator access, and free loopback port 80. Releases are **experimental and unsigned**; verify the checksum before running. No signing or SmartScreen reputation is claimed.

1. Download **`Sidepiece-Setup-0.2.1-windows-x64.exe`** and `SHA256SUMS.txt` from [Releases](https://github.com/JediRhymeTrix/sidepiece/releases). Compare `Get-FileHash <downloaded-exe> -Algorithm SHA256` with its entry.
2. Run the installer and approve elevation. The configuration window shows NVIDIA GPU names, suggested metadata IDs and device state—including disabled GPUs.
3. Select your **external desktop GPU**, click **Allow selected GPU**, and review the editable ID. Optionally deny your internal laptop GPU. Nothing is selected automatically: a GPU name cannot establish enclosure topology, and the suggested `_1` suffix may need correction. [GPU selection details](docs/configuration.md#selecting-a-gpu).
4. Click **Install and verify**, confirm your selection, then reopen NVIDIA App and check driver discovery.

Setup handles service registration, permissions, endpoint redirection and a health check. The GUI closes afterward; **only the native service stays running**.

> Already using a bridge? Do not install alongside it. Stop and restore its endpoints **through its current manager** first. Setup refuses foreign installations, occupied port 80 and retained recovery data; it does not migrate or take over pdsvc.

### Prefer scripts or a portable host?
Download and extract the ZIP instead. In an elevated PowerShell window, run ` .\scripts\Setup.ps1 -Action ListGpus`, then ` .\scripts\Setup.ps1 -DeviceId 'ABCD_10DE_1234_5678_1'` with your exact metadata ID. The example is synthetic. [SCM and foreground/pdsvc instructions](docs/hosting.md).

## Configure, update or remove
- **Configure:** open **Configure GeForce Sidepiece** from Start. Edit allow/deny lists, toggle overrides, or use **Advanced JSON** for custom rules. Saves validate before replacing configuration and preserve running/stopped state.
- **Stop and restore / Start service:** use the configurator buttons. Disabling metadata overrides is not the same as stopping the bridge.
- **Update:** run the newer installer. Custom rules are preserved. Script-installed services must use `Setup.ps1 -Action Update` instead; installation layouts are not silently converted.
- **Uninstall:** use Windows **Installed Apps**. URL restoration must succeed before UI files are removed. Service binaries, configuration, route key and backups remain for recovery; review/archive them before reinstalling.
- **Scripted setup:** `Setup.ps1 -Action Status`, `-Action Stop`, `-Action Start`, `-Action Update` and `-Action Uninstall` remain available. Use the same installation/data roots used at installation. Installer-managed services use `C:\Program Files\GeForce Sidepiece\service` as `-InstallRoot`.

If the process crashes or is forcibly killed, the local URLs may remain redirected. Keep `route.key` and use the installed executable with `--data-dir 'C:\ProgramData\GeForceSidepiece' --restore` **only after the service has stopped**. See [hosting and recovery](docs/hosting.md) before deleting files.

## Configurable, not a hard-coded patch
`C:\ProgramData\GeForceSidepiece\config.json` controls explicit device and endpoint allow/deny lists, exact GET endpoint matches and conditional scalar overrides. Rules are reloaded per request; invalid rules disable rewriting while ordinary forwarding continues. Validate edits with the installed executable’s `--data-dir ... --validate` command. Blacklists win. The upstream host stays fixed to `gfwsl.geforce.com`.

The on-demand configurator uses built-in Windows PowerShell 5.1 and WinForms; it adds no resident UI or runtime to the native service. Start with [the example](config/config.example.json), [schema](config/schema.json), and [configuration guide](docs/configuration.md). Extra endpoint names and top-level scalar overrides require configuration, not recompilation. Request bodies and responses are not rewritten.

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
