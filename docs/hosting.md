# Hosting and recovery

## Standalone Windows service
Setup registers `GeForceSidepiece` for automatic startup under LocalService plus its own service SID. Runtime needs no pdsvc dependency, resident script or wrapper. Default executable: `C:\Program Files\GeForce Sidepiece\sidepiece.exe`; private data: `C:\ProgramData\GeForceSidepiece`.

Run setup/control commands elevated. `Setup.ps1` supports `Install` (default), `Update`, `Uninstall`, `Status`, `ListGpus`, `-WhatIf`, `-BinaryPath`, `-InstallRoot` and `-DataRoot`. Use the same custom roots for subsequent operations. Choose trusted local, unused directories; quotes, reparse points and traversal paths are rejected. Reinstall does not overwrite retained files: after uninstall, review/archive them manually or select fresh roots.

Update requires an owned service/manifest, stops safely, preserves custom configuration and keeps `sidepiece.previous.exe` for rollback. Service-start health failures trigger rollback. Setup never force-kills a host that cannot restore its URLs. Do not invoke setup with its own installed binary as the update source.

Stop through `Stop-Service GeForceSidepiece`. Restore occurs before shutdown is signaled; restoration failure is reported and the host remains running. Workers drain for at most 70 seconds while SCM checkpoints advance. Do not force termination simply because Services briefly displays Stop Pending.

## Foreground / pdsvc
The **same executable** runs in the foreground when `--service` is absent. Put it in a protected directory and create a private writable data directory, copy `config/config.example.json` there as `config.json`, and select the eGPU allowlist. Grant the chosen account access to the two NVIDIA configuration directories as needed; do not broadly relax ACLs or run a whole process manager elevated.

Run `sidepiece.exe --data-dir <private-directory> --prepare`, then `--validate`, then `sidepiece.exe --data-dir <private-directory>` to serve. A manager such as pdsvc should launch that foreground command without `--service`, and stop using `sidepiece.exe --data-dir <private-directory> --stop`. Wait for exit before restarting. Ctrl+C also attempts restoration. Configure your manager’s stop timeout above the 70-second drain ceiling. The public project ships no private pdsvc scripts or dashboard integration.

Use exactly one host. Migration requires stopping/restoring through the old manager, confirming port 80 is free and official URLs are restored, then starting the new host. Never run SCM and pdsvc copies simultaneously, or share a data directory between different host installations.

## CLI reference
- `--help`, `--version`: diagnostics without loading runtime files.
- `--data-dir PATH`: config/key/log/backup directory; otherwise executable directory.
- `--prepare`: create a local random route key if absent, then validate rules.
- `--validate`: validate rules and existing route key without changing NVIDIA settings.
- `--probe`: authenticated local health/counters.
- `--stop`: authenticated non-browser graceful stop with restoration.
- `--restore`: restore this installation’s URL spans while stopped.
- `--passive`: serve without editing NVIDIA settings; intended for diagnostics/tests.
- `--service`: SCM host only; do not run directly in a console.
- `--fixture-root`, `--port`: test-only controls; serving requires passive mode. Not a supported production customization.

Modes are mutually exclusive. Production listens on IPv4 loopback port 80, matching the current NVIDIA configuration scheme.

## Crash recovery and troubleshooting
1. Stop the host via its manager if it is alive. Check that the expected process has exited.
2. Keep the **same** data directory and `route.key`; it identifies owned redirects. Never regenerate it to recover an existing installation.
3. Run the installed executable with `--data-dir <same-directory> --restore` elevated if necessary. It replaces only its own tokenized URLs with the official NVIDIA URL. It refuses foreign/unknown endpoints.
4. Restart NVIDIA App. Only then archive retained files or migrate hosts.

Backups are originals for inspection, not instructions to overwrite current files wholesale. NVIDIA may have made unrelated settings changes since installation. If layouts change or restoration refuses an unfamiliar URL, stop and inspect locally; do not blindly replace JSON or delete route keys.

Port conflict: stop the existing owner rather than killing arbitrary processes. Access denied: inspect the service SID grants; do not switch to LocalSystem as a workaround. Rules not applying: validate config, confirm exact GPU metadata ID, endpoint and scalar type. UI stale: reopen NVIDIA App; API success is not proof the UI consumed the response.

Logs: `sidepiece.log` and one `.previous` file in the data directory, roughly 1 MiB each. Logs omit URLs, headers and payloads. An abrupt process kill may leave no final diagnostic. No automatic crash-restart policy is installed in 0.1.x: investigate and restore rather than hiding persistent configuration failures.
