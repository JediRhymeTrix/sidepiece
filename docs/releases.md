# Releases

`VERSION` is the single product version. A `vX.Y.Z` tag must match it exactly. Only tag a commit whose main-branch CI has passed. All 0.x releases remain experimental prereleases. A working user deployment is recorded as single-setup evidence, not hardware certification or validation of every installer path.

The release workflow rebuilds with MSVC static analysis, runs native and isolated lifecycle checks, runs GPU/UI smoke tests, packages an explicit allowlist into a Windows x64 ZIP, compiles the single-file setup EXE with pinned Inno Setup 6.4.3, exercises that EXE on a disposable runner and emits SHA-256 checksums for both downloads. Publishing uses GitHub-generated release notes categorized by `.github/release.yml`. No binary signing, silent updater or independent provenance attestation is claimed. Workflow identity, source commit and build logs are available in Actions; checksums detect corruption, not compromise of the publishing account.

The ZIP contains `sidepiece.exe`, setup/GPU/configuration helpers, example/schema, documentation, original artwork and MIT license. It never contains runtime files, real IDs, route keys, logs, backups, test executables or local manager scripts.

Before publishing, inspect package contents and tracked files for private data; verify CI, tag/version consistency, generated notes, checksum and downloaded assets. Test setup/update/uninstall on disposable Windows with synthetic settings; retain the limits in release notes if real NVIDIA hardware/UI testing is not complete.

## Publication gate
A publishable experimental candidate must pass both Windows CI jobs, include the expected helper paths (including `scripts/UiSession.ps1`) in the ZIP, and pass the compiled install/configure/update/uninstall and failure-recovery fixtures. `scripts/Test-Ui.ps1` checks an actual shown configuration window, cancellation, duplicate-session refusal, parent-loss cleanup and lock release without service/settings changes; the compiled fixture repeats this against installed payload helpers and checks shortcut presentation. Smoke mode exits with cancellation status 2, not success, after automatically closing the form. Hosted window checks do not establish foreground focus or UAC behavior on a real desktop.

`scripts/Test-Package.ps1` verifies the assets in `dist/`: checksums, excluded runtime/test files, required helpers, extracted binary version and extracted configurator lifecycle. CI and release builds both run it. Inspect downloaded artifacts again after publication using the same check against those downloaded assets. A green source-tree build alone does not validate packaged launch paths.

Use version-independent download instructions in documentation: `Sidepiece-Setup-<version>-windows-x64.exe`. Keep exact versions in `VERSION`, tags and generated assets, not in quick-start prose. Describe known limitations prominently; do not turn a user report into a claim of broad compatibility.

Stable promotion is a separate decision. Record a real desktop installer walkthrough (including elevation, cancellation and uninstall), supported Windows/NVIDIA App versions, and restart/reboot behavior before claiming those paths are verified. Code signing and an independent security review are recommended; neither is currently claimed. Automated fault injection is not a substitute for physical power-loss or full-disk testing.

## Build and publish
Run `scripts/Package.ps1` after a successful analyzed build, then `scripts/Build-Installer.ps1` with the pinned compiler. Release automation is tag-driven; pushing a candidate to main does not publish it. Only tag the reviewed, green-CI commit. GitHub releases are the intended binary distribution channel; fault-injected build fixtures must never be uploaded as release assets.
