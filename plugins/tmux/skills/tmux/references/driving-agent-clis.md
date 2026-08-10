# Driving Agent CLIs — Reference

The recipes in `interaction-recipes.md` are tool-agnostic. The **only** per-CLI knobs are:

1. **`IDLE_REGEX`** — the substring/pattern that appears in the pane *only when the CLI is input-ready* (used by `detect-idle`).
2. **First-run / auth prompts** — the one-time gates a CLI shows before it will accept work (used by `handle-interruption`).
3. **Spawn flags** — how the CLI is started (sandbox, model, non-interactive guards).
4. **File-include syntax** — how to reference a file in a prompt for `send-via-tmpfile`.

This file is how you fill those four knobs in for a specific CLI.

---

## How to calibrate any CLI

You can calibrate an unknown CLI in three steps, entirely from the pane:

1. **Find the idle marker.** Spawn the CLI, let it settle, then:

   ```bash
   tmux capture-pane -t "$TARGET" -p | tail -5
   ```

   Pick a stable substring that's present at idle but *absent* mid-response — typically a status line (model + state), a shell-style prompt (`>`, `❯`), or a "ready" banner. Turn it into `IDLE_REGEX`. Match it against only the last few lines of the pane (not the whole buffer) and anchor it to something the CLI does **not** print mid-stream (a status-line suffix), or `detect-idle` will fire early on response content that echoes the marker.

2. **Discover first-run gates.** Run the very first invocation and watch for trust/login/permission prompts. Note the exact keystroke that dismisses each (a number, `y`, `Enter`). These go in your `handle-interruption` table.

3. **Confirm the submit behavior.** Verify the `send-inline` `sleep 0.3` is enough; if the CLI swallows the first `Enter`, raise the pause. Confirm whether it has a file-include shorthand (so `send-via-tmpfile` can use it) or needs a plain "read this path" instruction.

---

## Per-CLI calibration table

Values below are starting points — **always re-verify against your installed version** with step 1 above, since TUIs change their status lines between releases.

| CLI | `IDLE_REGEX` (starting point) | Idle marker location | First-run / auth gate | Spawn notes |
|---|---|---|---|---|
| **codex** | `gpt-5\.[0-9].*·` (model-agnostic across the 5.x slugs; the middot before the cwd path; anchor to the ` · /path` status line, not just the model name — the model name can appear in response text) | Bottom status line `gpt-5.6-sol xhigh · /path` | "Hooks need review" on first run → send `2` Enter ("Trust all and continue"). Auth: `codex login` if "Not authenticated". | Non-interactive bash must use the tmux TUI (not bare `codex`); sandbox via `-s read-only` / `-s workspace-write`; reasoning effort via `-c model_reasoning_effort=xhigh`. File-include: `@path`. |
| **gemini** | `gemini-[0-9.]+.*(pro\|flash)` (verify) | Bottom model/status line | Google account auth on first run ("Sign in") → can't self-recover; user authenticates in their terminal. | Confirm a non-interactive-safe launch mode; file-include syntax differs by version — verify before relying on `@`. |
| **aider** | `^>\s*$` or the `aider>` prompt at column 0 | Shell-style input prompt | API-key check on first run ("set OPENAI_API_KEY"/provider key) → user exports the key, then respawn. | Pass the model with `--model`; `--yes`/auto-confirm flags reduce approval prompts. No `@` include — give the path and say "add this file". |
| **generic REPL** | The REPL's prompt string, e.g. `>>> `, `In \[[0-9]+\]:`, `\$ ` | The last non-empty line (the prompt) | Usually none; some require an explicit "ready"/banner wait. | Launch the REPL as the window command; `send-inline` works directly; for multi-line input prefer `send-via-tmpfile` + a "read this file" instruction. |

**`detect-idle` for any of these** is unchanged — only `IDLE_REGEX` differs:

```bash
TARGET="<session>:<window>"
IDLE_REGEX='<from the table above, re-verified>'
# ...then run the two-phase detect-idle from interaction-recipes.md verbatim...
```

If a CLI has *no* stable idle marker (it leaves the cursor on a blank line), fall back to a pure stability check — "pane unchanged for N consecutive polls" — and accept a slightly higher false-positive risk, or have the CLI print a sentinel (e.g. ask it to end every reply with a fixed token) and match that.

---

## The codex plugin is the reference implementation

**The `codex` plugin in this marketplace is the canonical, production implementation of this skill.** It applies every recipe and lifecycle pattern here to a real CLI and is the best worked example to read when in doubt.

What codex contributes on top of this generic skill:

- **A lifecycle helper script** — `plugins/codex/scripts/codex-tmux.sh` — implementing spawn/find/reuse/kill, the idempotent **`pane`** (default: reused pane in the agent's current window, keep-shell) and **`bind`** (fallback: single window per agent session, `codex-<claude6>`) entry points, `remain-on-exit`, metadata recording, and orphan/dead detection. It is the concrete form of the pseudo-functions (`window_state`, `claude6`, etc.) shown in `sync-and-lifecycle.md` and `model-and-identity.md`.
- **codex-specific calibration** — the model-agnostic `gpt-5\.[0-9].*·` `IDLE_REGEX`, hooks-review handling, sandbox/approval flag mapping, and model/effort defaults.
- **A `codex exec` escape hatch** (confirm-gated) for genuine one-shots that don't need a tmux window.

When building support for a **new** CLI, mirror the codex plugin's structure: a thin lifecycle script (management only) plus a skill that defers all interaction theory to *this* tmux skill and adds only the four per-CLI knobs above. Don't re-teach `send-keys`/`capture-pane`/idle-detection — point at `interaction-recipes.md` and `sync-and-lifecycle.md`, exactly as the codex plugin does.

**Pointers:**
- `plugins/codex/scripts/codex-tmux.sh` — the reference lifecycle script.
- `plugins/codex/skills/codex/SKILL.md` — the reference skill: codex-specific one-liners + decision tables, deferring generic theory to this skill.
- `plugins/codex/skills/codex/references/tmux-mode.md` — codex's concrete, `cc-codex:`-targeted recipe notes.
