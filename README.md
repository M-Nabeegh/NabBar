# <img src="docs/nabbar-icon.png" width="40" height="40" valign="middle" alt=""> NabBar

**Codex, Claude and Command Code limits in your Mac's menu bar — and on your Touch Portal deck.**

NabBar is a focused build of [ClaudeBar](https://github.com/tddworks/ClaudeBar) by TDDWorks. It tracks
just the three tools I use, in the order I use them, with a muted look, and runs side by side with
an installed ClaudeBar without touching its settings.

| | NabBar | ClaudeBar |
|---|---|---|
| Providers | Codex → Claude → Command Code | 20 built-in, plus extensions |
| Settings | `~/.nabbar` | `~/.claudebar` |
| Bundle id | `com.nabeegh.nabbar` | `com.tddworks.claudebar` |
| Updates | rebuild from source (no auto-update) | Sparkle |
| Look | Muted Slate theme | Light / Dark / CLI / … |
| Touch Portal | plugin included | — |

## Build and install

Needs macOS 15+, Xcode and [Tuist](https://tuist.dev) (`brew install tuist`).

```bash
scripts/build-local.sh --install
```

This builds a Release app, names it NabBar, ad-hoc signs it, verifies the signature and installs
`/Applications/NabBar.app`. It never touches `/Applications/ClaudeBar.app`, `~/.claudebar`, your
CLI logins or the Keychain. Without `--install` it only builds into `build/local/`.

The build leaves out the AWS SDK (a multi-gigabyte download only Bedrock needs), via
`TUIST_CLAUDEBAR_WITHOUT_AWS=1`.

## First run

- **Claude** reads `claude /usage`. The CLI must be logged in and past its first-run setup:
  run `claude auth login`, then `claude` once and pick a theme. A CLI that was never logged in
  now shows *Authentication required* instead of hanging on "Fetching usage data…".
- **Codex** uses the Codex CLI. If it's only installed inside the ChatGPT app, the installer
  points NabBar at that copy. Click **Refresh** once so NabBar may run it in the background.
- **Command Code** works as soon as you're logged in to it.

NabBar refreshes all three every 5 minutes and shows their percentages in the menu bar.

## Touch Portal

`scripts/build-local.sh` also writes `build/local/NabBar.tpp`. Import it in Touch Portal →
Settings → Plug-ins. It publishes, for each of `codex`, `claude` and `commandcode`:

| State | Example |
|---|---|
| `com.nabeegh.nabbar.touchportal.state.<id>.left` | `80%` |
| `….<id>.used` | `20%` |
| `….<id>.reset` | `Resets in 2h 39m` |
| `….<id>.status` | `healthy` |
| `….<id>.summary` | `Claude` / `80% left` |

The plugin only reads `~/.nabbar/status.json` and talks to Touch Portal on `127.0.0.1`. No network,
no credentials.

## Tests

```bash
TUIST_CLAUDEBAR_WITHOUT_AWS=1 tuist install && TUIST_CLAUDEBAR_WITHOUT_AWS=1 tuist generate --no-open
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ProvidersTests -only-testing:DomainTests -only-testing:DataSourcesTests \
  -only-testing:InfrastructureTests -only-testing:AppTests
```

## Credits

Built on [ClaudeBar](https://github.com/tddworks/ClaudeBar) © 2025 TDDWorks and contributors,
MIT licensed. Its original README is in [docs/CLAUDEBAR_README.md](docs/CLAUDEBAR_README.md).
NabBar changes © 2026 M. Nabeegh, also MIT — see [LICENSE](LICENSE).
