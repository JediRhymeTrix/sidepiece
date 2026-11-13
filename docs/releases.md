# Releases

`VERSION` is the single product version. A `vX.Y.Z` tag must match it exactly. Only tag a commit whose main-branch CI has passed. Initial `v0.1.0` is a prerelease; all 0.x releases remain prereleases until hardware/UI and installer coverage justify a stable release.

The release workflow rebuilds with MSVC static analysis, runs native and isolated lifecycle checks, packages an explicit allowlist of files into a Windows x64 ZIP and emits SHA-256 checksums. Publishing uses GitHub-generated release notes categorized by `.github/release.yml`. No binary signing, silent updater or independent provenance attestation is claimed. Workflow identity, source commit and build logs are available in Actions; checksums detect corruption, not compromise of the publishing account.

The ZIP contains `sidepiece.exe`, setup helper, example/schema, documentation, original artwork and MIT license. It never contains runtime files, real IDs, route keys, logs, backups, test executables or local manager scripts.

Before publishing, inspect package contents and tracked files for private data; verify CI, tag/version consistency, generated notes, checksum and downloaded assets. Test setup/update/uninstall on disposable Windows with synthetic settings; retain the limits in release notes if real NVIDIA hardware/UI testing is not complete.

Suggested local packaging: `scripts/Package.ps1` after a successful analyzed build. Release automation is tag-driven; it does not publish every main-branch commit. GitHub releases are the only intended binary distribution channel.
