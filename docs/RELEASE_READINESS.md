# Release readiness

Status: **source/dev release ready**. The repository is licensed under Apache-2.0 and the technical checks pass locally. GitHub releases attach an explicitly unsigned Apple Silicon developer zip and checksum; Developer ID signing and notarization remain future production-binary work.

## Product and provenance

- Intended user: macOS developers who need repeatable build, launch, accessibility, screenshot, and log evidence from the command line.
- Employer-facing story: a focused Swift CLI that turns native macOS verification into structured, reviewable artifacts while keeping permissions and captures local.
- Repository: `gauravsdama/macness`, private, not a GitHub fork, with one author in the local commit history.
- Source: first-party Swift code. Swift Package Manager reports no third-party package dependencies and no vendored source is tracked.
- Interface: CLI only. There is no product UI or user-facing string inventory to maintain.

## Evidence recorded 2026-09-15

- `swift test`: 5 tests passed, including the packaged binary version contract.
- `swift build -c release`: passed on Apple Swift 6.3.2, arm64 macOS 26.6.2.
- `./scripts/setup.sh --check`: Swift, Xcode 26.5, screen capture, Accessibility, and Screen Recording checks all passed in the current user context.
- A temporary-prefix install produced a runnable standalone binary; `otool -L` showed only Apple system frameworks and Swift runtime libraries.
- A live no-screenshot check launched Calculator and passed running-process, `Calculator` window, and `AXApplication` role assertions. Evidence is under the ignored `.macness/release-audit/` directory.
- `./scripts/release_check.sh`: runs diff hygiene, tests, a release build, CLI smoke test, personal-path check, and tracked-artifact check.
- `./scripts/package_release.sh --output /tmp/macness-package-final`: produced a deterministic `macness-0.1.0-macos-arm64.zip`; two consecutive builds had SHA-256 `b2bcf1d5b7bad86e60661c90dd3285f55259f6679f7df763d3184e74b53d3bc8`.
- The packaged installer verified `SHA256SUMS`, installed into a fresh temporary prefix, reported version `0.1.0`, and ran `doctor --json` successfully. `file` confirmed a thin arm64 Mach-O.

## Release boundary

- The attached archive is an unsigned source/dev convenience build, not a production binary. This Mac has no Developer ID signing identity. GitHub release notes and the archive itself warn that Gatekeeper may block or warn and make no frictionless-install claim.
- Sign and notarize a future production binary when a Developer ID is available.
- Repeat the live verification against a representative owned app before a future production-binary release; the current Calculator smoke test proves the core launch/window/accessibility path.
- Screenshots and unified logs may contain private desktop or application data; `.macness/` is ignored and must not be committed.

## Release checklist

- Run `./scripts/release_check.sh`.
- Run `otool -L .build/release/macness` and confirm only system libraries/frameworks are linked.
- For this source/dev release, confirm the GitHub prerelease attaches both the unsigned zip and its `.sha256` file.
- Install the archive into a temporary prefix and run `macness doctor --json` on another Apple Silicon Mac running macOS 13 or later; CI repeats the clean-checkout offline install on every push.
- For a future production binary, build with `./scripts/package_release.sh --sign-identity ... --notary-profile ...` and require an accepted notarization result.
- Run `./scripts/release_check.sh --publish` from a clean release commit.
- Review the working tree and commit only the intended files. Do not include `.macness/` evidence.
