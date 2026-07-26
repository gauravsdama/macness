---
name: macness
description: Build, launch, inspect, and verify native macOS apps using the locally installed macness CLI. Use for macOS app work that needs windows, accessibility-tree, screenshot, or unified-log evidence.
---

# Macness

Use this skill for native macOS app verification. `macness` is a local CLI, not
an MCP service: it has no external-account connector or remote data access.

## Preconditions

From the target app repository, run:

```sh
macness doctor --json
```

The terminal running the tool needs Accessibility permission for UI-tree
assertions and Screen Recording permission for screenshots. If either is not
available, run `macness doctor --prompt` and resolve it before relying on that
kind of evidence.

## Standard pathway

1. Build the app with `macness build --project ... --scheme ...` or workspace
   equivalent.
2. Launch with `macness launch --app ... --fresh`.
3. Verify with one or more expectations, for example:

   ```sh
   macness verify --bundle-id com.example.App \
     --expect-window "My App" \
     --expect-text "Ready" \
     --expect-role AXButton
   ```

4. Inspect `snapshot.json`, `verify.json`, and any screenshot in the emitted
   `.macness/runs/` directory.
5. Report success only when the requested expectations passed and the captured
   evidence is available.

## Available functionality

- `doctor`: toolchain and macOS permission checks
- `build`: `xcodebuild` for a project or workspace
- `launch`: start a `.app` or bundle identifier, optionally fresh/hidden
- `snapshot`: capture process metadata, visible windows, accessibility tree,
  and optional screenshot
- `verify`: assert visible window text, accessibility text, or roles
- `monitor`: take repeated snapshots during a workflow
- `logs`: collect a bounded unified-log export for a PID or bundle ID

## Constraints

- Always supply one or more `--expect-*` flags to `verify`. An assertion-free
  verify only confirms that a process exists in the current version.
- Screenshots capture the desktop, not only the target window; do not expose
  sensitive artifacts.
- Keep generated `.macness/` artifacts out of commits.
