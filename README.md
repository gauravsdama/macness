# Macness

Macness is a local CLI for inspecting and verifying native macOS applications. It builds and launches an app, records visible windows and accessibility state, captures optional screen evidence, and evaluates simple assertions against the running process.

It is for developers and coding agents working on macOS apps who need proof of UI state after a change, rather than a successful build alone.

## What it covers

- Xcode toolchain and macOS permission checks
- Xcode project and workspace builds
- Launching an app by path or bundle identifier
- Visible-window snapshots for a target process
- Accessibility-tree snapshots and text/role assertions
- Optional screen captures and bounded unified-log exports
- Repeated snapshots for observing a workflow

## Requirements

- macOS 13 or later
- Xcode and the Swift toolchain; source builds require Swift 6.3 or later
- Accessibility permission for UI-tree inspection
- Screen Recording permission for screenshots

## Install

### Standalone installation

From a clone or release checkout:

```sh
cd macness
./scripts/setup.sh --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
macness doctor --json
```

The setup script builds a release binary, installs it under the selected prefix, and installs the bundled Codex skill by default. Run `./scripts/setup.sh --check` to validate the local toolchain and permissions without a global install.

### Development build

```sh
swift build
swift test
.build/debug/macness doctor
```

### Apple Silicon source/dev release package

Create a self-contained offline zip for Apple Silicon Macs:

```sh
./scripts/package_release.sh
```

The GitHub source/dev release attaches this deterministic archive and its SHA-256 checksum. The archive contains the `arm64` executable, Apache-2.0 notices, an unsigned-build notice, checksum, and an offline installer. On another Apple Silicon Mac:

```sh
shasum -a 256 -c macness-0.1.1-macos-arm64.zip.sha256
unzip macness-0.1.1-macos-arm64.zip
cd macness-0.1.1-macos-arm64
./install.sh
export PATH="$HOME/.local/bin:$PATH"
macness doctor --json
```

No compiler or repository checkout is needed on the destination Mac. Building apps still requires Xcode; launch, snapshot, verify, and capture operations use macOS frameworks and permissions.

The attached developer binary is not signed with an Apple Developer ID and is not notarized. Gatekeeper may block or warn about it because its publisher cannot be verified. Review the source and checksum before deciding whether to run it; this release does not promise a frictionless Gatekeeper installation.

Signing and notarization require an Apple Developer Program account, a Developer ID Application certificate in the login keychain, and a stored `notarytool` profile. No entitlements are required. The packaging script signs the only executable with the hardened runtime, verifies the signature, submits the exact zip, requires an `Accepted` response, and runs Gatekeeper assessment before reporting success:

```sh
xcrun notarytool store-credentials macness-notary \
  --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD"
./scripts/package_release.sh \
  --sign-identity "Developer ID Application: NAME (TEAM_ID)" \
  --notary-profile macness-notary
```

The accepted response is saved beside the archive as `.notarization.json`. A standalone executable inside a zip cannot carry a stapled ticket, so the destination Mac must be online for Gatekeeper's notarization lookup on first launch. Do not describe a Developer ID-only archive as notarized unless that record says `Accepted`.

Before transferring any archive to another Mac, verify its manifest, checksum, architecture, offline installation, and relocated launch:

```sh
./scripts/verify_release_archive.sh dist/macness-0.1.1-macos-arm64.zip
```

## Quick start

Build, launch, then assert the UI state you care about:

```sh
macness build --project MyApp.xcodeproj --scheme MyApp --configuration Debug
macness launch --app ./Build/Products/Debug/MyApp.app --fresh --wait 10
macness verify --bundle-id com.example.MyApp \
  --expect-window "My App" \
  --expect-text "Ready" \
  --expect-role AXButton
```

Runs write artifacts below a collision-safe `.macness/runs/<timestamp>-<label>-<nonce>/` directory unless `--out` is supplied. Run directories are created with owner-only permissions, and JSON, screenshots, and log files are restricted to the owner:

- `snapshot.json` — process, window, and accessibility-tree state
- `verify.json` — assertion results and exit status
- `screen.png` — optional desktop screen capture

Accessibility capture is bounded to 5,000 nodes, 250 children per node, the requested depth, and a 15-second traversal budget. `snapshot.json` records `accessibilityMetadata.truncated` and the exact limits that stopped traversal. Treat a failed text or role expectation as inconclusive when capture was truncated outside the relevant part of the tree.

## Verification model

Macness separates state capture from evaluation. `snapshot` collects available evidence; `verify` evaluates the expectations you provide. Always pass at least one `--expect-window`, `--expect-text`, or `--expect-role` flag to `verify`.

An assertion-free `verify` currently confirms only that the target process was resolved. Accessibility and screenshot errors are recorded in `snapshot.json`. Choose expectations that match the user-visible behavior being changed, and inspect the generated artifacts before calling a workflow complete.

Screen captures include the desktop rather than only the target window. Unified logs can also contain application data. Treat both as sensitive even though Macness writes them with private filesystem permissions.

## Commands

```sh
macness doctor [--prompt] [--json]
macness build (--project PATH | --workspace PATH) [--scheme NAME] [--configuration NAME]
macness launch (--app PATH | --bundle-id ID) [--fresh] [--hide] [--wait SECONDS] [-- APP_ARGS...]
macness snapshot (--bundle-id ID | --pid PID) [--out DIR] [--label NAME]
macness verify (--bundle-id ID | --pid PID) --expect-text TEXT
macness monitor (--bundle-id ID | --pid PID) [--interval SECONDS] [--count N]
macness logs (--bundle-id ID | --pid PID) [--seconds N] [--out FILE]
```

Use `macness --help` for the complete option reference.

`--wait` is a readiness timeout rather than a fixed delay: Macness returns when the process reports that it finished launching, or fails when the timeout expires. Numeric options reject negative, non-finite, and unsafe values. Monitoring requires a finite count; log collection is limited to 24 hours and 50 MiB per invocation.

## Codex integration

Macness is a local CLI, not an MCP service. It integrates with Codex through a reusable local skill and optional project-level `AGENTS.md` guidance. See the [Codex integration guide](docs/codex-integration.md) for installation details, project instructions, and capability pathways.

## Development

```sh
./scripts/release_check.sh
```

Keep changes small, preserve structured artifacts, and avoid introducing unbounded subprocesses or captures. See [CONTRIBUTING.md](CONTRIBUTING.md).

Macness is licensed under Apache-2.0. The [release-readiness record](docs/RELEASE_READINESS.md) lists verified source and binary distribution checks.

## License

Copyright 2026 Gaurav Dama. Licensed under the [Apache License 2.0](LICENSE).
