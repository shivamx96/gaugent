<h1 align="center">gaugent</h1>

<p align="center">
  <strong>How much of your coding-agent subscription is left, one glance away.</strong><br>
  A tiny native macOS menu-bar app for Claude Code and Codex allowances.
</p>

gaugent sits in the menu bar and shows the remaining share of each subscription window your
installed agent CLIs report: the 5-hour session, the weekly limit, per-model weekly limits,
spend limits, and reset credits. The dial's needle tracks the lowest remaining window, and
the panel breaks each tool down with reset countdowns.

## What it reads

| Tool | How | Needs |
| --- | --- | --- |
| **Codex** | `codex app-server` account and rate-limit RPCs | `codex` on PATH, signed in with ChatGPT |
| **Claude Code** | The `get_usage` control request in a print-mode session with no tools, no MCP servers, no persistence | `claude` on PATH, signed in with claude.ai |

Grok, Gemini, Muse, and other tools can be added by implementing the small `UsageProvider`
protocol in `GaugentCore`.

## Private by construction

- gaugent never sends a prompt, never starts a turn, and never reads a token. Each tool's own
  CLI answers from its own session.
- The cache in `~/Library/Caches/com.shivamx96.gaugent` holds quota numbers and hashed account
  identities only, with owner-only permissions.
- After a failed refresh the last good reading is kept only when the same account is still
  signed in, and it is shown dimmed. Stale readings never trigger the low-allowance warning.
- Readings are taken every five minutes, when the panel opens (if older than a minute), and on
  demand with ⌘R. The global shortcut ⌥⌘U opens the panel from anywhere.

## Requirements

- macOS 14 Sonoma or later
- Claude Code and/or Codex installed and signed in

## Build from source

```sh
git clone https://github.com/shivamx96/gaugent.git
cd gaugent
scripts/build-app.sh
open build/gaugent.app
```

For a development run without an app bundle:

```sh
swift run Gaugent
```

Run the tests with:

```sh
swift test
```

gaugent is prerelease software.
