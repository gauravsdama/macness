# Release readiness

Status: **source/dev release ready**. The repository is licensed under Apache-2.0 and the technical checks pass locally. GitHub releases attach an explicitly unsigned Apple Silicon developer zip and checksum; Developer ID signing and notarization remain future production-binary work.

## Product and provenance

- Intended user: macOS developers who need repeatable build, launch, accessibility, screenshot, and log evidence from the command line.
- Employer-facing story: a focused Swift CLI that turns native macOS verification into structured, reviewable artifacts while keeping permissions and captures local.
- Repository: `gauravsdama/macness`, public, not a GitHub fork, with one author in the local commit history.
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
- GitHub Actions run `35034516465` passed the clean-tree gate and installed the packaged archive from a clean `macos-26` checkout. The `v0.1.0` developer-release workflow attached the unsigned zip and checksum as a prerelease.

## Tightening verification recorded 2026-09-15

- Graphify ran against an isolated copy outside the repository and indexed 200 nodes and 529 edges. Its hub report identified `MacnessRuntime`, `AccessibilityReader`, and `ProcessRunner`; every acted-on finding was confirmed in source before editing, and the temporary graph was removed.
- `./scripts/release_check.sh` passed after adding shell syntax checks, the expanded Swift suite, a release build, CLI smoke checks, personal-path checks, and tracked-artifact checks.
- The subprocess regression emitted 20,000 lines to both stdout and stderr concurrently, completed without a pipe deadlock, and retained exactly the configured 4 KiB per stream with explicit truncation flags. The timeout regression terminated a ten-second command in about 0.2 seconds.
- Parser coverage rejects negative or non-finite waits, invalid PIDs and depths, unbounded monitor counts, unsafe log windows and predicates, empty values, and unsupported build actions.
- A live Calculator check exercised readiness polling and passed process plus `AXApplication` verification. The snapshot visited 262 accessibility nodes and honestly reported `max-depth` truncation; a deliberately absent role produced an explicit “captured portion” failure rather than claiming a complete-tree miss.
- Live artifacts used mode `0700` for the run directory and `0600` for `snapshot.json`. Unit coverage also verifies collision-safe run names, private JSON, atomic command output, and removal of temporary output files.
- Two consecutive package builds produced identical SHA-256 `5267ac79c49344c849b2933a8142d659277c5bdcb843dea5a4ec8fa8922624c0`. The checksum verified, `unzip -t` passed, and the archive contained only the expected binary, installer, licensing, README, unsigned-build notice, and internal checksum.

## Version 0.1.1 candidate recorded 2026-10-14

- Twelve Swift tests passed, including bounded concurrent subprocess output, timeout termination, private atomic artifacts, parser bounds, and accessibility traversal metadata.
- A live Calculator run passed process launch and the `AXApplication` accessibility assertion. No repository evidence contains the temporary screenshot or snapshot.
- Two unsigned packages built from the same checkout were byte-for-byte identical. Clean checkouts can produce different Mach-O link UUIDs, so the checksum published with each release artifact is authoritative; cross-checkout bit-for-bit reproducibility is not claimed.
- `verify_release_archive.sh` checked the outer checksum, exact seven-file manifest, internal binary checksum, thin arm64 architecture, temporary-prefix installation, relocated execution, version `0.1.1`, and valid `doctor --json` output.
- Gitleaks scanned the full five-commit history without a finding. Swift Package Manager reports no external package dependencies. `LICENSE` and `NOTICE` remain in both the repository and archive.
- The release script now rejects an unavailable signing identity, requires notarization status `Accepted`, saves the notarization response beside the archive, and runs Gatekeeper assessment. A signed build requests hardened runtime with no entitlements.
- Documentation samples were checked locally with the conservative Binoculars profile and were labelled most likely human-generated. This is only a statistical writing signal, not proof of authorship.

## Release boundary

- The attached archive is an unsigned source/dev convenience build, not a production binary. This Mac has no Developer ID signing identity. GitHub release notes and the archive itself warn that Gatekeeper may block or warn and make no frictionless-install claim.
- Sign and notarize a future production binary when a Developer ID is available.
- Repeat the live verification against a representative owned app before a future production-binary release; the current Calculator smoke test proves the core launch/window/accessibility path.
- Screenshots and unified logs may contain private desktop or application data; `.macness/` is ignored and must not be committed.
- The tightening release is version `0.1.1`; `v0.1.0` remains the original unsigned source/developer prerelease.
- This Mac currently has no valid code-signing identities. Developer ID signing, Apple notarization acceptance, first-run online ticket lookup, and physical testing on a second Apple Silicon Mac remain owner-controlled release gates, not locally completed checks.

## Release checklist

- Run `./scripts/release_check.sh`.
- Run `otool -L .build/release/macness` and confirm only system libraries/frameworks are linked.
- For this source/dev release, confirm the GitHub prerelease attaches both the unsigned zip and its `.sha256` file.
- Install the archive into a temporary prefix and run `macness doctor --json` on another Apple Silicon Mac running macOS 13 or later; CI repeats the clean-checkout offline install on every push.
- For a future production binary, build with `./scripts/package_release.sh --sign-identity ... --notary-profile ...` and require an accepted notarization result.
- Transfer the zip and `.sha256` file to a separate Apple Silicon Mac and run `./scripts/verify_release_archive.sh` from a repository checkout, or manually verify the outer checksum, `SHA256SUMS`, install into a fresh prefix, run `macness doctor --json`, and assess the signed executable with `spctl` while online.
- Run `./scripts/release_check.sh --publish` from a clean release commit.
- Review the working tree and commit only the intended files. Do not include `.macness/` evidence.
