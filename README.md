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
- Xcode and the Swift toolchain
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

## Quick start

Build, launch, then assert the UI state you care about:

```sh
macness build --project MyApp.xcodeproj --scheme MyApp --configuration Debug
macness launch --app ./Build/Products/Debug/MyApp.app --fresh
macness verify --bundle-id com.example.MyApp \
  --expect-window "My App" \
  --expect-text "Ready" \
  --expect-role AXButton
```

Runs write artifacts below `.macness/runs/<timestamp>-<label>/` unless `--out` is supplied:

- `snapshot.json` — process, window, and accessibility-tree state
- `verify.json` — assertion results and exit status
- `screen.png` — optional desktop screen capture

## Verification model

Macness separates state capture from evaluation. `snapshot` collects available evidence; `verify` evaluates the expectations you provide. Always pass at least one `--expect-window`, `--expect-text`, or `--expect-role` flag to `verify`.

An assertion-free `verify` currently confirms only that the target process was resolved. Accessibility and screenshot errors are recorded in `snapshot.json`. Choose expectations that match the user-visible behavior being changed, and inspect the generated artifacts before calling a workflow complete.

Screen captures include the desktop rather than only the target window. Treat them as potentially sensitive build artifacts.

## Commands

```sh
macness doctor [--prompt] [--json]
macness build (--project PATH | --workspace PATH) [--scheme NAME] [--configuration NAME]
macness launch (--app PATH | --bundle-id ID) [--fresh] [--hide] [-- APP_ARGS...]
macness snapshot (--bundle-id ID | --pid PID) [--out DIR] [--label NAME]
macness verify (--bundle-id ID | --pid PID) --expect-text TEXT
macness monitor (--bundle-id ID | --pid PID) [--interval SECONDS] [--count N]
macness logs (--bundle-id ID | --pid PID) [--seconds N] [--out FILE]
```

Use `macness --help` for the complete option reference.

## Codex integration

Macness is a local CLI, not an MCP service. It integrates with Codex through a reusable local skill and optional project-level `AGENTS.md` guidance. See the [Codex integration guide](docs/codex-integration.md) for installation details, project instructions, and capability pathways.

## Development

```sh
swift test
```

Keep changes small, preserve structured artifacts, and avoid introducing unbounded subprocesses or captures. See [CONTRIBUTING.md](CONTRIBUTING.md).
