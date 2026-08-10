# Tmux Agent-CLI Orchestration Plugin

The canonical, reusable guide for one agent (Claude) to **drive and observe other
interactive CLIs inside tmux** — especially agent CLIs like codex, gemini, and aider.

## Overview

When Claude needs to run another long-lived, interactive command-line program — feed it
input, watch its output, know when it has finished a turn, and iterate — tmux is the right
substrate: the child process keeps running across Claude's bash calls, a human can attach to
watch or intervene, and Claude can both type into and read from the pane.

This plugin ships a single skill that teaches the generic, tool-agnostic recipes for doing
this reliably: the session/window/pane model, an identity-and-naming scheme that binds one
agent to its sub-processes, the send → wait-for-activity → wait-for-idle → extract-delta
interaction loop, one-driver discipline and locking, and lifecycle/cleanup. It is the
**reference other plugins link to** — the codex plugin defers its generic tmux know-how here
and keeps only codex-specific details.

## Features

- **Agent-CLI orchestration model**: session ⊃ window ⊃ pane, and when to use a window vs a pane.
- **Identity & naming**: a stable `claude6` token derived from the Claude session, used to bind
  one Claude session to exactly one reused worker window (and to spawn extra windows only on
  explicit request).
- **Interaction recipes**: send-inline, send-via-tmpfile, two-phase idle detection, delta
  extraction, incremental capture, copy-mode navigation, cancel, and interruption handling.
- **Sync & lifecycle**: one-driver discipline, `flock` serialization, spawn/find/kill/cleanup,
  orphan/dead detection, and `remain-on-exit` semantics.
- **Per-CLI calibration**: how to adapt the generic loop to codex, gemini, aider, or any REPL.

## Prerequisites

1. **tmux** (3.0 or later recommended)
   ```bash
   # macOS
   brew install tmux
   # Debian / Ubuntu
   sudo apt-get install tmux
   ```

2. **The CLI you intend to drive** (e.g. codex, gemini, aider) installed and authenticated.

3. A POSIX shell with `flock` available for serialized lifecycle operations (Linux ships it;
   on macOS install via `brew install flock` or use the skill's lock-free fallback).

## Installation

This plugin is part of the cc-dev-tools marketplace. To install:

1. Add the marketplace:
   ```bash
   /marketplace add https://github.com/Lucklyric/cc-dev-tools
   ```

2. Install the plugin:
   ```bash
   /plugin install tmux@cc-dev-tools
   ```

3. Restart Claude Code

## Usage

The skill is automatically invoked when Claude needs to drive, observe, or manage another
interactive CLI inside tmux:

```
User: "Drive codex in a tmux window and watch it until it's done"
User: "Spawn a gemini session I can attach to, then send it this prompt"
User: "Send-keys this to the aider window and capture what it prints back"
```

## Naming & Identity Model

Each Claude session derives a short, stable token:

- **`claude6`** = first 6 chars of `$CLAUDE_CODE_SESSION_ID` (fallback: first 6 chars of the
  sha256 of `"$PPID:$PWD"`).

Worker CLIs run inside a shared tmux session (default name `cc-codex`, override with
`CC_CODEX_SESSION_NAME`). Within it, two window-naming patterns apply to **any** driven tool:

- **Bound window (default, one per Claude session, topic-agnostic, reused for every task):**
  `<tool>-<claude6>` — e.g. `codex-0d61e6`.
- **Extra windows (ONLY when the user explicitly asks for a separate/parallel task):**
  `<tool>-<topic>-<claude6>-<rand2>` — e.g. `codex-auth-0d61e6-x7` (topic = 2–15 chars `[a-z0-9-]`).

This is the contract the skill teaches; concrete bind/find/kill commands and the codex
specialization live in the skill and its references.

## Skills

### Tmux (Agent-CLI Orchestration)

The primary and only skill: the canonical generic catalog for driving other interactive CLIs
in tmux.

- **Skill Path**: `skills/tmux/SKILL.md`
- **Triggers**: "drive codex/gemini/aider in tmux", "spawn/reuse a tmux window/pane",
  "send-keys", "capture-pane", "detect idle/done", "orchestrate an agent CLI"

## Documentation

- **skills/tmux/SKILL.md**: the canonical generic catalog (mental model, identity/naming,
  interaction loop, decision table).
- **skills/tmux/references/model-and-identity.md**: session/window/pane model; `claude6`
  identity; naming; binding and reuse.
- **skills/tmux/references/interaction-recipes.md**: send-inline, send-via-tmpfile, two-phase
  idle detection, extract-delta, incremental-capture, copy-mode, cancel, handle-interruption.
- **skills/tmux/references/sync-and-lifecycle.md**: one-driver discipline, `flock`
  serialization, spawn/find/kill/cleanup, orphan/dead detection, `remain-on-exit`.
- **skills/tmux/references/driving-agent-clis.md**: per-CLI calibration (codex/gemini/aider/
  generic REPL); points to the codex plugin as the reference implementation.

## Relationship to Other Plugins

This skill is the **canonical reference**. The **codex** plugin drives codex through tmux and
links here for the generic concepts (send/capture/idle-detection/naming/locking), keeping only
codex-specific commands, regexes, and flags in its own docs. New plugins that drive an
interactive CLI should do the same: link to this skill instead of re-teaching the recipes.

## Contributing

This plugin follows the cc-dev-tools marketplace structure:
- Plugin root: `plugins/tmux/`
- Metadata: `.claude-plugin/plugin.json`
- Skill: `skills/tmux/SKILL.md`
- References: `skills/tmux/references/`

## License

Apache-2.0

## Version

0.1.2

## Author

0xasun

## Repository

https://github.com/Lucklyric/cc-dev-tools
