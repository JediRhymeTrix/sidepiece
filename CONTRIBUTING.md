# Contributing

Keep changes small, dependency-free and reversible. Explain the NVIDIA App symptom and the request field you intend to change. Do not generalize endpoint or destination matching to make a single fixture pass.

Run `scripts/Build.ps1 -Analyze` and `scripts/Test-Lifecycle.ps1` on Windows. Add a synthetic regression check for parser, rules, endpoint ownership or HTTP changes. Never exercise live redirects if another bridge is active. Service/setup tests belong on disposable Windows runners.

Do not commit runtime config, route keys, NVIDIA logs or real request payloads. Replace hardware IDs with synthetic IDs in tests. Issue reports should include redacted versions, hosting mode, expected/actual behavior and minimal synthetic reproduction—not a full log archive. Report security issues using [SECURITY.md](SECURITY.md).

By contributing you agree your contributions are licensed under the project’s MIT license. Use descriptive commits and document behavior/security changes. Avoid claims of NVIDIA affiliation, guaranteed driver availability or universal hardware compatibility.
