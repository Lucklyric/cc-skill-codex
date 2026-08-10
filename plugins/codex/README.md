# Codex CLI Integration Plugin

OpenAI Codex (GPT-5.6 series) integration for Claude Code, providing high-reasoning capabilities for complex coding tasks.

## Overview

This plugin enables Claude Code users to invoke OpenAI's Codex CLI with the GPT-5.6 series (`gpt-5.6-sol` / `gpt-5.6-terra` / `gpt-5.6-luna`) for advanced reasoning, complex implementations, and architectural design. It provides task-aware model + reasoning-effort selection, session continuation, and safe defaults for seamless integration.

> **Requires codex CLI ≥ 0.144.0** for the GPT-5.6 series. On older CLIs, set `CC_CODEX_MODEL=gpt-5.5` to fall back to the prior model.

## Default mode: codex pane beside Claude

By default, codex runs as a **pane split into your current tmux window** — right next to Claude, no separate attach. When codex exits, the pane **stays**: it drops into your interactive shell (keep-shell default) so you can keep using it manually — e.g. `codex resume --last` to continue the conversation by hand — and the next resolve relaunches codex in the same pane; type `exit` to close it (`CC_CODEX_KEEP_SHELL=0` restores the old auto-close). When Claude is not running inside tmux, it falls back to one dedicated reused window (`codex-<claude6>`) in the `cc-codex` session:

```bash
tmux attach -t cc-codex   # only needed for the fallback window
```

A `codex exec` escape hatch remains for one-shot calls. The helper script handles lifecycle (pane / bind / spawn / list / kill); the codex skill drives interaction via raw tmux commands (`send-keys` / `capture-pane`). See `skills/codex/references/tmux-mode.md` for the full workflow and recipes.

### Helper script subcommands

The helper script at `$CLAUDE_PLUGIN_ROOT/scripts/codex-tmux.sh` exposes lifecycle-only subcommands:

| Subcommand | Purpose |
|---|---|
| `pane [--topic <slug>] [--cwd DIR] [--full-auto\|--read-only] [--horizontal\|--vertical] [--size PCT]` | **DEFAULT** (inside tmux): get/create THE codex pane in the current window. Idempotent — reuse if alive, relocate if drifted, respawn if dead. Prints a pane id (e.g. `%53`). Exit 3 = not inside tmux (use `bind`); exit 4 = codex died at launch. |
| `panes [--all]` | Read-only: list this agent's codex panes as TSV (pane_id, topic, state, location, cwd). Never creates anything. |
| `bind [--cwd DIR] [--full-auto\|--read-only]` | **FALLBACK** (outside tmux): get/create the single bound window `codex-<claude6>`. Idempotent. |
| `new <topic> [--cwd DIR] [--full-auto\|--read-only]` | Spawn an extra SEPARATE window (explicit user request only). Returns the window name immediately. |
| `ls [--mine]` | List codex windows with state (`alive` / `dead` / `unknown`). `--mine` filters to the current Claude session. |
| `find <topic> [--cwd DIR] [--include-dead] [--any-session]` | Look up extra windows by topic in this session's `claude6` namespace. Exit 0 + one match per line, or exit 1 if none. |
| `attach <window>` | Print the tmux attach command (Claude Code's bash is non-interactive). |
| `rename <old> <new-topic>` | Replace the topic portion; preserves the `<claude6>-<rand2>` suffix. |
| `kill <window\|%pane-id>` / `kill --mine` / `kill --orphaned` | Remove one codex pane/window; ALL of this session's codex; or every agent's dead codex (global escape hatch — explicit request only). |
| `exec [flags...] <prompt>` | One-shot escape hatch using `codex exec` (no tmux). |

Model and reasoning effort for every spawn and `exec` come from `CC_CODEX_MODEL` / `CC_CODEX_EFFORT` (defaults `gpt-5.6-sol` / `xhigh`); they bind when a codex process starts, so overrides on a reuse call warn instead of applying.

In v3.1.0 the `send` and `capture` subcommands were removed; they now print a migration error (exit 64) pointing at the recipe catalog. Drive interaction via `tmux send-keys` / `tmux capture-pane` per the recipes in `skills/codex/references/tmux-mode.md`.

## Features

- **GPT-5.6 series**: `gpt-5.6-sol` (frontier, default), `gpt-5.6-terra` (balanced), `gpt-5.6-luna` (fast/affordable) — pick per task
- **Extended effort ladder**: low · medium · high · xhigh · **max** · **ultra** (5.6 adds `max`/`ultra`; default `xhigh`)
- **Task-aware selection**: choose model + effort by task, or override via `CC_CODEX_MODEL` / `CC_CODEX_EFFORT`
- **Code Review**: delegate `codex review` over uncommitted changes, a base branch, or a commit
- **Session Continuation**: Resume previous conversations with `codex exec resume --last`
- **Safe Sandbox Defaults**: Read-only for general tasks, workspace-write for code editing
- **Web Search Integration**: Built-in web search for research and documentation lookup
- **Non-Interactive Execution**: Optimized for Claude Code's non-terminal bash environment
- **Deterministic skill loading**: a `UserPromptSubmit` hook nudges Claude to invoke the codex skill whenever a prompt mentions codex (see "Skill-load nudge hook")
- **Keep-shell panes**: when codex exits, its pane drops into your shell instead of closing — manually usable, relaunchable in place (`CC_CODEX_KEEP_SHELL=0` to disable)

## Prerequisites

1. **Codex CLI** (v0.144.0 or later, required for the GPT-5.6 series) — install via either of the two officially recommended methods from [`openai/codex`](https://github.com/openai/codex):

   ```bash
   # npm (cross-platform)
   npm install -g @openai/codex

   # OR Homebrew (macOS)
   brew install --cask codex

   # Verify
   codex --version  # Should show v0.144.0+
   ```

   To upgrade later, re-run the matching command:
   ```bash
   npm install -g @openai/codex@latest      # npm install
   brew upgrade --cask codex                # Homebrew install
   ```

   Alternative: download a prebuilt binary from the [latest GitHub release](https://github.com/openai/codex/releases/latest), extract, rename to `codex`, and place on `$PATH`.

2. **Authentication**
   ```bash
   codex login
   ```
   ChatGPT-account auth runs the base GPT-5.6 slugs (`gpt-5.6-sol`/`gpt-5.6-terra`/`gpt-5.6-luna`) and `gpt-5.5`. The `-fast` service-tier variants (e.g. `gpt-5.6-sol-fast`) require an OpenAI API key (`codex logout && codex login --api-key <key>`).

3. **API Access**
   - OpenAI API key (or ChatGPT plan with GPT-5.6 access)
   - Codex CLI API access enabled

## Installation

This plugin is part of the cc-dev-tools marketplace. To install:

1. Add the marketplace:
   ```bash
   /marketplace add https://github.com/Lucklyric/cc-dev-tools
   ```

2. Install the plugin:
   ```bash
   /plugin install codex@cc-dev-tools
   ```

3. Restart Claude Code

## Usage

### Basic Invocation

The skill is automatically invoked when you mention "Codex" or request complex coding assistance:

```
User: "Use Codex to design a binary search tree in Rust"
```

### Skill-load nudge hook

Skill triggering from the description alone is probabilistic — in sessions with many plugins, Claude can miss the codex skill and drive the `codex` CLI from memory instead. To make loading reliable, the plugin ships a `UserPromptSubmit` hook (`hooks/hooks.json` + `hooks/skill-nudge.sh`): on every prompt that contains the word "codex" (word-boundary, case-insensitive), it injects a reminder telling Claude to invoke the codex skill before running any codex command. Prompts that don't mention codex pass through untouched, and the hook adds no LLM calls (pure bash + jq, python3 fallback). Hooks load at session start — restart Claude Code after installing or updating the plugin.

### Model Selection

Pick a GPT-5.6 model + effort by task (default `gpt-5.6-sol` + `xhigh`):

**Code Editing Tasks (network enabled)**:
```bash
codex exec -m gpt-5.6-sol -s workspace-write \
  -c model_reasoning_effort=xhigh \
  -c sandbox_workspace_write.network_access=true \
  "Implement thread-safe queue in Python"
```

**Hardest Reasoning (max/ultra effort)**:
```bash
codex exec -m gpt-5.6-sol -s read-only \
  -c model_reasoning_effort=max \
  "Design a distributed cache system"    # or effort=ultra for the very hardest
```

**Everyday / cost-aware work (terra or luna)**:
```bash
codex exec -m gpt-5.6-terra -c model_reasoning_effort=high "Review this module"
codex exec -m gpt-5.6-luna  -c model_reasoning_effort=medium "Quick: explain quicksort"
```

### Session Management

```bash
# Start a new session (automatic on first request)
codex exec -m gpt-5.6-sol "Implement authentication system"

# Resume most recent session
codex exec resume --last

# Continue with new prompt in same session
codex exec resume --last "Now implement the login flow"
```

### Code Review

```bash
codex review --uncommitted                       # staged + unstaged + untracked
codex review --base main                          # this branch vs a base branch
codex review --commit <SHA> --title "summary"     # a specific commit
codex review --uncommitted "Focus on concurrency safety."
```

### Advanced Options

**With Web Search** (built-in on supported models, no flag needed in `codex exec`):
```bash
codex exec -m gpt-5.6-sol \
  -c model_reasoning_effort=xhigh \
  "Research React 19 Server Components"
```

**Workspace-Write with Network Access** (run installers, fetch deps, hit APIs):
```bash
codex exec -m gpt-5.6-sol -s workspace-write \
  -c model_reasoning_effort=xhigh \
  -c sandbox_workspace_write.network_access=true \
  "Install dependencies and run the test suite"
```

**Clean output capture** (write only the final message / structured JSON):
```bash
codex exec -m gpt-5.6-sol -o /tmp/answer.txt "Summarize @report.md in 3 bullets."
codex exec -m gpt-5.6-sol --output-schema schema.json "Return the result as JSON."
```

**Different Sandbox Modes**:
```bash
# Read-only (for reasoning tasks)
codex exec -m gpt-5.6-sol -s read-only "Review code"

# Workspace-write (for code editing)
codex exec -m gpt-5.6-sol -s workspace-write "Refactor module"

# Full access (advanced users only)
codex exec -m gpt-5.6-sol -s danger-full-access "Complex task"
```

## Configuration

### Default Settings

| Parameter | Default Value | CLI Flag / Env | Notes |
|-----------|---------------|----------|-------|
| Model | `gpt-5.6-sol` | `-m gpt-5.6-sol` / `CC_CODEX_MODEL` | Frontier GPT-5.6 agentic model (requires CLI ≥ 0.144.0) |
| Sandbox (default) | `read-only` | `-s read-only` | Safe default for reasoning / review |
| Sandbox (coding) | `workspace-write` | `-s workspace-write` | Required for file edits |
| Network access | `enabled` (with `workspace-write`) | `-c sandbox_workspace_write.network_access=true` | Required for `npm`/`pip`/`cargo`/HTTP calls |
| Reasoning Effort | `xhigh` | `-c model_reasoning_effort=xhigh` / `CC_CODEX_EFFORT` | Strong default; escalate to `max`/`ultra` for the hardest tasks |
| Web Search | built-in | (no flag in `codex exec`) | Native `web_search` tool on supported models |

The tmux spawns (`pane`/`bind`/`new`) and `exec` all pin `-m $CC_CODEX_MODEL -c model_reasoning_effort=$CC_CODEX_EFFORT`. Set `CC_CODEX_MODEL=gpt-5.5` on a codex CLI older than 0.144.0.

### Reasoning Effort Levels

Ladder: **low < medium < high < xhigh < max < ultra**

- **ultra**: Maximum reasoning with automatic task delegation (`gpt-5.6-sol`/`gpt-5.6-terra` only)
- **max**: Maximum reasoning depth for the hardest problems (5.6 series)
- **xhigh**: Extra-high reasoning (plugin default)
- **high**: Greater reasoning depth for complex problems
- **medium**: Balances speed and reasoning depth
- **low**: Fast responses with lighter reasoning

## Model Comparison

| Model | Use Case | Effort ceiling |
|-------|----------|----------------|
| GPT-5.6-Sol (default) | Frontier: hard reasoning, architecture, deep debugging | ultra |
| GPT-5.6-Terra | Balanced everyday coding/review (cost-aware) | ultra |
| GPT-5.6-Luna | Fast & affordable: quick edits, high volume | max |
| GPT-5.5 | Prior frontier model; use on CLIs older than 0.144.0 | xhigh |

`-fast` service-tier variants (e.g. `gpt-5.6-sol-fast`) exist for 1.5× speed but require API-key auth.

### Fallback Chain
- **Model**: `gpt-5.6-sol` → `gpt-5.6-terra` / `gpt-5.6-luna` → `gpt-5.5` (older CLI)
- **Reasoning effort**: `xhigh` → `high` → `medium`

## Troubleshooting

### CLI Not Installed
```bash
# Check if Codex CLI is installed
codex --version

# If not found, follow OpenAI's installation guide
```

### General Diagnosis / Updates
```bash
codex doctor    # diagnose installation, config, auth, and runtime health
codex update    # update the CLI in place
```

### Authentication Required
```bash
# Authenticate with OpenAI
codex login
```

### "stdout is not a terminal" Error

**Problem**: Using `codex` instead of `codex exec` in non-interactive environment

**Solution**: Always use `codex exec` in Claude Code:
```bash
# WRONG
codex -m gpt-5.6-sol "prompt"

# CORRECT
codex exec -m gpt-5.6-sol "prompt"
```

### Session Not Found
```bash
# Check if there are previous sessions
codex exec resume --list

# Start a new session
codex exec -m gpt-5.6-sol "New task"
```

### API Rate Limits

If you encounter rate limits, check your OpenAI API usage dashboard. The plugin uses high-reasoning models which may have different rate limits.

## Documentation

- **SKILL.md**: Complete skill definition and usage guide
- **references/tmux-mode.md**: Canonical tmux-mode recipe catalog (v3.1.0 default workflow)
- **references/codex-help.md**: Full CLI reference
- **references/cli-features.md**: CLI flag table, interactive-vs-exec differences
- **references/codex-config.md**: Configuration options
- **references/file-context.md**: Passing files, directories, and the `@` syntax
- **references/command-patterns.md**: Legacy `exec`-mode templates (kept for escape-hatch reference)
- **references/session-workflows.md**: Legacy `exec`-mode session-continuation patterns
- **references/advanced-patterns.md**: Legacy `exec`-mode advanced flag combinations
- **references/examples.md**: Legacy `exec`-mode examples by use case
- **references/troubleshooting.md**: Error catalog and fixes

## Version Compatibility

- **Minimum**: Codex CLI v0.144.0 (required for the GPT-5.6 series; older CLIs can run `CC_CODEX_MODEL=gpt-5.5`)
- **Recommended**: Latest stable version
- **Models**: GPT-5.6-Sol (default), GPT-5.6-Terra, GPT-5.6-Luna; GPT-5.5 fallback

## When to Use Codex vs Gemini vs Claude

**Use Codex when:**
- You need GPT-5.6-Sol's frontier reasoning capabilities (xhigh, up to max/ultra)
- Complex coding tasks requiring high-reasoning model
- Architecture and system design with maximum reasoning
- Code reviews requiring deep analysis

**Use Gemini when:**
- You need Google's latest AI models
- Research with web search is important
- Free tier OAuth access (Codex requires API key)
- Creative or general reasoning tasks

**Use Claude (native) when:**
- Simple queries within Claude Code's capabilities
- No external AI needed
- Quick responses preferred

## Rate Limits & Costs

**Note**: Codex CLI uses OpenAI's API, which may have associated costs:
- GPT-5.6 series usage is billed per token
- Higher reasoning effort (xhigh/max/ultra) may consume more tokens
- Check OpenAI's pricing for current rates

## Contributing

This plugin follows the cc-dev-tools marketplace structure:
- Plugin root: `plugins/codex/`
- Metadata: `.claude-plugin/plugin.json`
- Skill definition: `skills/codex/SKILL.md`
- References: `skills/codex/references/`
- Hooks: `hooks/hooks.json` + `hooks/skill-nudge.sh`

## License

Apache-2.0

## Author

0xasun

## Repository

https://github.com/Lucklyric/cc-dev-tools

## Version

3.11.0
