# Configuration

## Selecting a GPU
Use **Configure GeForce Sidepiece** from Start, run `scripts/Setup.ps1 -Action ListGpus`, or view Device Manager → Display adapters → the external GPU → Properties → Details → Hardware Ids. Identify the physical desktop card yourself; the helper does not infer enclosure topology.

A synthetic PCI ID `PCI\VEN_10DE&DEV_ABCD&SUBSYS_12345678&REV_A1` maps to `ABCD_10DE_1234_5678_1`:
- device (`DEV`) first, vendor (`VEN`) second;
- first four and last four digits of `SUBSYS`, in that order;
- `_1` is the metadata instance suffix observed in the supported NVIDIA App format, **not** `REV_A1`. If the actual request uses another suffix, match that exact value instead.

Use uppercase IDs in configuration. Request IDs are compared case-insensitively. Verify the exact metadata ID locally if your GPU appears more than once or the PCI-derived ID does not match. Do not post raw NVIDIA logs to get help: they can contain credentials and tokenized URLs. Never assume every NVIDIA device in a laptop is external.

## Configure without hand-editing files
Open **Configure GeForce Sidepiece** from Start. Allow only the external desktop GPU, optionally deny internal GPUs, and select **Validate and save**. IDs remain editable because PCI inventory cannot establish enclosure topology or the metadata instance suffix. Disabled display devices are included in inventory.

The basic tab edits device lists and the override toggle without replacing custom rules. **Advanced JSON** exposes the full configuration. **Reload / discard edits** returns to the saved file. A stale save is refused: reload before applying changes made elsewhere. Saving preserves service state; **Stop and restore** restores official NVIDIA URLs, while disabling overrides leaves the bridge running.

## Configuration reference
The [example](../config/config.example.json) starts with an **empty device allowlist**, so it cannot rewrite until configured. Copy it to your private data directory as `config.json` for foreground mode; standalone setup creates it for you. Do not add a `$schema` property: the native parser rejects unknown fields. Editors can associate [schema.json](../config/schema.json) externally.

- `schemaVersion`: exactly integer `1`.
- `enabled`: boolean; defaults to false if absent.
- `whitelistDeviceIds`, `blacklistDeviceIds`: explicit IDs. Every request `dIDa` ID must be allowed; any denied ID vetoes all edits. Missing/empty/invalid `dIDa` means no rewrite.
- `whitelistEndpoints`, `blacklistEndpoints`: exact case-sensitive endpoint names. An endpoint needs both an allowlist entry and a matching rule. Deny wins.
- `rules`: at most 64 unique endpoint/method pairs.
- `endpoint`: 1–128 ASCII letters, digits or underscores appended to the fixed `/nvidia_web_services/controller.gfeclientcontent.NG.php/com.nvidia.services.GFEClientContent_NG.` prefix.
- `method`: only `GET`. There is no body editing.
- `overrides`: 1–16 unique top-level fields; `dIDa` cannot be overridden. Each entry has `field`, `from` and `to`. Values must be JSON scalars: strings, numbers, booleans or null.

The two bundled presets change string `iLp` from `"1"` to `"0"`. They intentionally do not coerce numeric `1`, booleans or arbitrary truthy values. If you independently confirm a numeric payload, use numeric values in your private rule instead.

## Additional endpoints and overrides
Add an exact endpoint name to `whitelistEndpoints`, then add a rule with that name and `method: "GET"`. An override such as `{"field":"mode","from":"old","to":"new"}` changes only a matching scalar. Add more **distinct** fields to the same override list if needed. Missing fields or nonmatching `from` values are skipped independently; the override list is not an all-or-nothing predicate group.

Comparison uses exact serialized JSON token text. `"old"` and `"\u006fld"` are not equivalent for override matching, even though their decoded strings agree. Object member names and device strings are decoded by the parser. Unchanged escaped-path bytes are retained; changed spans may use uppercase percent-encoding. Responses and query strings are not rewritten.

Unknown keys, duplicate keys, duplicate list items, conflicting rules and non-scalar override values are rejected. Maximum configuration size is 64 KiB, IDs/lists/routes have bounded lengths, and parser nesting is bounded. The schema cannot express all runtime constraints; `--validate` is authoritative. Legacy unversioned device/endpoint lists remain accepted for migration/testing. An explicit `rules` field requires `schemaVersion: 1`; new configurations should always use the versioned format.

## Editing safely
Prefer the configurator for validated, atomic saves with a previous-file backup. When editing manually, change only the private data directory’s `config.json`, not NVIDIA JSON files. Run the installed executable with `--data-dir 'C:\ProgramData\GeForceSidepiece' --validate` after changes. The running process loads rules per request. Invalid configuration disables rewriting while forwarding remains available; health availability alone does not prove rules are valid. `enabled: false` disables overrides, **not** the endpoint redirects or service. Stop the service to restore official URLs.
