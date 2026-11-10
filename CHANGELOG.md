# Changelog

Changes to NabBar that you would notice. NabBar is built on
[ClaudeBar](https://github.com/tddworks/ClaudeBar); what ClaudeBar changed before NabBar branched
off is in [docs/CLAUDEBAR_CHANGELOG.md](docs/CLAUDEBAR_CHANGELOG.md).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1.0] - 2026-11-11

### Added
- Working and done dots. A blue dot sits on the Claude or Codex logo in the menu bar while that tool works on a task, and turns green when it finishes. Opening the menu clears the green dot. NabBar reads this from the tools' own session logs and changes nothing in them.
- A website: [m-nabeegh.github.io/NabBar](https://m-nabeegh.github.io/NabBar/).

### Fixed
- A Codex app-server that stopped answering no longer freezes every later refresh. It is stopped after 20 seconds and the next refresh starts clean, so the menu bar no longer keeps day-old numbers.
- The Codex dot now shows for a resumed conversation. Codex keeps writing it in the folder of the day it started, which NabBar used to skip.
- Watching for activity no longer holds NabBar near 9% CPU. Logs that have not changed are not read again, and it now stays under 1%.
- When the Claude CLI's Usage tab has no plan bars, NabBar says the CLI is logged out instead of showing nothing.

## [1.0.0] - 2026-10-08

First release.

- Codex, Claude and Command Code limits in the menu bar, coloured by how much is left, with each tool's 5-hour and weekly limits and reset times in the dropdown.
- Touch Portal plugin with a ready-made button face per tool and a refresh action.
- iPhone Home Screen widget through the Notify! app.
- macOS notifications when a limit drops into yellow, red or runs out.
