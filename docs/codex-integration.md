# Codex integration

`macness` is a local command-line harness, not an MCP connector. Its supported
Codex integration is a reusable local skill plus optional project-level
guidance. This keeps macOS permissions and screenshots local to the developer
machine.

## One-time setup

```sh
git clone <your-macness-repository> macness
cd macness
./scripts/setup.sh --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

The script builds a release binary and copies the bundled skill to
`$CODEX_HOME/skills/macness` (or `$HOME/.codex/skills/macness`). Start a new
Codex task after installation so it can discover the local skill.

Run `./scripts/setup.sh --check` for a non-installing prerequisite and
permission check. Add `--no-codex-skill` when only the CLI is wanted.

## Project guidance

Add this to the target macOS repository's `AGENTS.md` when Macness is the
standard verification workflow:

```md
## macOS verification

Use the `macness` skill for native macOS app changes. Run `macness doctor`
before UI verification. Build, launch, and then use `macness verify` with at
least one `--expect-window`, `--expect-text`, or `--expect-role` assertion.
Inspect `snapshot.json` and `verify.json` before reporting success. Treat
desktop screenshots as potentially sensitive artifacts.
```

## Functional pathways

| Need | Command |
| --- | --- |
| Prerequisites and permissions | `macness doctor --json` |
| Build | `macness build --project App.xcodeproj --scheme App` |
| Launch a fresh app | `macness launch --app path/to/App.app --fresh` |
| UI state evidence | `macness snapshot --bundle-id com.example.App` |
| Assert UI behavior | `macness verify --bundle-id ... --expect-text Ready` |
| Observe a flow | `macness monitor --bundle-id ... --count 5` |
| Diagnose runtime errors | `macness logs --bundle-id ... --seconds 120` |

## Current verification boundary

Use explicit expectations. In the current version, an assertion-free `verify`
passes after it resolves a running process, while screenshot and accessibility
capture errors are recorded in `snapshot.json` rather than failing every kind
of check.
