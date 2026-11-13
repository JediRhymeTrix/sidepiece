# Security

## Supported scope
The initial 0.1.x prerelease targets Windows x64 and NVIDIA App metadata requests. Treat unsigned prerelease binaries as experimental. This is not a hardened multi-tenant proxy.

## Boundaries
- Listen exclusively on IPv4 loopback, not LAN interfaces. Require a locally generated 256-bit route key and expected Host header. Permit only NVIDIA App’s `https://nvfile` browser origin (or requests without Origin); browser requests cannot stop the process.
- Forward only NVIDIA web-services paths to fixed HTTPS host `gfwsl.geforce.com`; verify TLS normally. Automatic redirects, cookies and Windows authentication are disabled. No CONNECT tunneling or arbitrary upstream configuration.
- Rules require explicit device and endpoint allowlists. Any denied device vetoes the entire rewrite. No body or response overrides; no executable plugins.
- SCM installation uses LocalService with a service SID, not LocalSystem. The service SID receives read/execute on the binary directory, Modify on its data directory and the two NVIDIA configuration directories needed for atomic replacement. These directory grants also cover other files in those directories; they are not per-file sandboxing.
- Program Files binaries and ProgramData configuration are protected by setup. Custom paths must be trusted local directories. Do not install on network shares or under untrusted writable parents. Setup is for trusted administrators, not hostile directory trees.
- Local administrators, the service identity, and processes that can read NVIDIA settings can obtain the route capability. The route is not a defense against a compromised local account. Do not expose or port-forward it.

## Data
No telemetry or external analytics are included. Forwarded NVIDIA requests still go to NVIDIA. Diagnostics use fixed messages without request URLs, headers or payloads. `sidepiece.log` rotates at approximately 1 MiB into one previous file. Backups and NVIDIA logs can contain sensitive data even when service diagnostics do not.

Never publish `route.key`, runtime configuration, backups, raw NVIDIA URLs, credentials or complete NVIDIA logs. Issue templates request redacted information only.

## Failure modes
Graceful stop restores owned endpoint strings before stopping. A crash, power loss, forced termination or failed restore can leave redirected URLs behind. Keep the route key; stop the host and use `--restore` with the same data directory. Unknown destinations are refused, not overwritten. Do not replace complete NVIDIA JSON files with old backups; that may lose newer settings.

## Reporting
Report vulnerabilities privately using [GitHub private vulnerability reporting](https://github.com/JediRhymeTrix/sidepiece/security/advisories/new) when enabled. If unavailable, open a minimal issue requesting a private reporting channel without exploit details or secrets. Do not attach live route keys or unredacted logs.
