# Contributing

Thanks for helping. This page covers building, testing and getting a PR merged.

## Build & test

Needs macOS 15+, Xcode with Swift 6.2+, and [Tuist](https://tuist.io) (`brew install tuist`).

```bash
git clone https://github.com/M-Nabeegh/NabBar.git && cd NabBar
tuist install                  # resolve dependencies
tuist generate                 # generate and open NabBar.xcworkspace; ⌘R runs the app
tuist test                     # all tests (DomainTests, InfrastructureTests, AppTests, AcceptanceTests)
tuist test DomainTests         # one target
tuist build NabBar -C Release
```

- `tuist test` caches results and skips targets it thinks are unchanged. To force a real run: `xcodebuild test -workspace NabBar.xcworkspace -scheme NabBar-Workspace -destination 'platform=macOS,arch=arm64'`.
- Coverage: `tuist test --result-bundle-path TestResults.xcresult -- -enableCodeCoverage YES`.
- SwiftUI previews work in Xcode (`⌘⌥↩`); the project sets `ENABLE_DEBUG_DYLIB` for them.
- "No such module" errors from SourceKit in your editor are expected; modules resolve when Tuist builds.

## How code is organised

Every built-in provider is a JSON definition in `Modules/Providers/Resources/Providers/`, run by one generic `Provider` and `DataSource` (`Modules/`). Around them: `Sources/Domain` (`QuotaMonitor` as the single source of truth, sessions, Notify!), `Sources/Infrastructure` (storage, notifications, hooks) and `Sources/App` (SwiftUI views that read the domain directly, no ViewModels). The why and the data flow: [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md).

## Adding a provider

Start from captured output of the tool, write golden tests against it, then add the JSON definition (and a general engine rule when the definition can't say something) and register it. Read a similar provider's `docs/providers/<id>/design.md` first, and add `docs/providers/<id>/README.md` for the new one.

## Rules

- **Test first.** Chicago-school TDD with Swift Testing and `@Mockable`: assert on resulting state, not on calls. Bugs get a failing test before the fix.
- Follow the layering and naming in [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md).
- **One CHANGELOG line** under `## [Unreleased]` for anything a user would notice. Write the effect in the user's words, ≤300 characters, and end with an absolute issue or PR link.

## Docs

Each fact has one home. Check before pushing:

```bash
python3 scripts/gen-docs.py      # regenerate docs/README.md after changing a description
python3 scripts/check-docs.py --strict
```

## Releasing

Maintainers only. Set the version in `Sources/App/Info.plist`, move the `## [Unreleased]` lines in `CHANGELOG.md` under the new version, then run `scripts/make-dmg.sh`. It builds `build/release/NabBar.dmg`, the Touch Portal plugin and their checksums; attach all three to a GitHub release for the `vX.Y.Z` tag. Builds are signed ad hoc and not notarized.
