---
name: tmux
description: This skill should be used when the agent needs to drive, observe, or manage ANOTHER interactive command-line program inside tmux — especially other agent CLIs such as codex, gemini, or aider. Triggers on spawning or reusing a tmux session/window/pane for a long-lived CLI, typing input with send-keys, reading output with capture-pane, detecting when the driven CLI is idle/done, binding one Claude session to its sub-process, serializing concurrent drivers (sync/locking), and lifecycle/cleanup of those windows. Do NOT trigger for plain one-shot shell commands that finish on their own, for tmux questions unrelated to driving an interactive program, or when the user is merely discussing tmux as a topic.
---

# Tmux: Driving Other Interactive CLIs as an Agent

Use this skill when you (Claude) must run **another interactive command-line program** —
typically another agent CLI like codex, gemini, or aider — keep it alive across your bash
calls, feed it input, watch its output, know when it has finished a turn, and iterate. tmux is
the substrate: the child keeps running between your calls, a human can attach to watch or
intervene, and you can both type into and read from the pane.

This is the **canonical, tool-agnostic catalog**. It teaches the mental model, the identity and
naming contract, the core interaction loop, one-driver discipline, and a decision table. Deep,
copy-pasteable recipes with full rationale live in the reference files; this page gives you the
short forms and tells you which reference to open. Other plugins (notably **codex**) link here
for the generic concepts and add only their tool-specific details.

## Mental model: session ⊃ window ⊃ pane

tmux nests three things, outermost to innermost:

- **Session** — a named, persistent container that survives detach. All driven CLIs for this
  marketplace live in one shared session, default name `cc-codex` (override with
  `CC_CODEX_SESSION_NAME`). A human attaches to the session, not to individual programs:
  `tmux attach -t cc-codex` (then `Ctrl-b w` to list windows).
- **Window** — one "tab" in the session, holding a driven CLI. A window has a name we control,
  so it can carry *identity* in that name (`cc-codex:<window>`).
- **Pane** — a rectangular split *inside* a window, running one process. A pane has no name, but
  it has an **immutable pane-id (`%NN`)** and per-pane user-options, so it can carry identity
  too. A pane is targeted by its pane-id, which is just as reliable as a window name.

### Two placements for a driven CLI

A single logical worker lives in **either** a dedicated window **or** a pane — pick the
placement, then bind identity to whichever you chose:

- **Dedicated window** (in the shared session) — best when the human isn't watching live, or
  when you fan out across many workers. Identity is the **window name** (`<tool>-<claude6>`);
  the human attaches to the session and tabs to it. Target = `<session>:<window>`.
- **Pane split into the agent's current window** — best when the agent itself runs inside tmux
  and a human wants to watch progress **live, beside Claude, with NO attach** (the driven CLI
  appears in the same window the human is already looking at). This is the **codex default**.
  Identity is **pane-bound**: a `@<tool>_<claude6>` user-option stamped on the pane, plus the
  pane-id as the target. Target = the pane-id (e.g. `%53`).

> **Rule of thumb:** one logical worker → one window **OR** one pane (never both). Choose
> *window* when the human will attach to watch / you run many workers; choose *pane in the
> current window* when the agent is inside tmux and a human wants a live side-by-side view with
> no attach. A pane is also still the right tool for showing two views of one worker at once
> (CLI + log tail). See `references/model-and-identity.md`.

> **Default placement & announcing.** Unless the human explicitly asks for a *new window* or a
> *new session*, spawn the driven CLI in the agent's **current session and window** (a pane
> beside the agent). Keep one worker per session: if its pane already exists in another window,
> **relocate it into the current window** (`tmux join-pane`) rather than duplicating it. And
> **announce before you spawn or move it** — e.g. *"I'll open `<tool>` as a pane in your current
> window (`<session>:<window>`)"* — so a split or relocation is never a surprise.

## Identity & naming contract

To bind *one* Claude session to *its* sub-processes — and to find/kill exactly those later —
every worker carries a stable per-session token: in its **window name** (window placement) or in
an **`@<tool>_<claude6>` pane user-option** (pane placement; see `references/model-and-identity.md`).

- **`claude6`** = first 6 chars of `$CLAUDE_CODE_SESSION_ID`.
  - Fallback when unset: first 6 chars of `sha256("$PPID:$PWD")`.

```bash
# Derive claude6. With CLAUDE_CODE_SESSION_ID set, stable for the whole Claude
# session; the sha256("$PPID:$PWD") fallback is best-effort — stable for the
# duration of the parent shell.
claude6() {
  local id="${CLAUDE_CODE_SESSION_ID:-}"
  if [[ -z "$id" ]]; then
    id=$(printf '%s' "$PPID:$PWD" | shasum -a 256 | cut -c1-6)
  fi
  printf '%s' "${id:0:6}"
}
```

Two window-naming patterns apply to **any** driven tool `<tool>` (codex, gemini, aider, …):

| Pattern | When | Example |
|---|---|---|
| **Bound** (default): `<tool>-<claude6>` | The default. Exactly **one** per Claude session, topic-agnostic, **reused for every task**. | `codex-0d61e6` |
| **Extra**: `<tool>-<topic>-<claude6>-<rand2>` | ONLY when the user explicitly asks for a separate / parallel task. `topic` = 2–15 chars `[a-z0-9-]`; `rand2` = 2 random `[a-z0-9]`. | `codex-auth-0d61e6-x7` |

**Default to the bound window.** Most conversations want a single reused worker, not a new
window per task — extra windows pile up and are hard to attach to and clean up. Only branch to
the extra-window pattern when the user explicitly says "separate", "parallel", "in another
window", "at the same time", "fresh window", etc.

The matcher for "my windows" must recognize **both** the exact bound name `^<tool>-<claude6>$`
and the extra glob `<tool>-*-<claude6>-*`. Full rules, topic-slug derivation, and the
bind/reuse/respawn workflow: `references/model-and-identity.md`.

## When to use a window vs a pane

A pane's *index* is volatile (it renumbers as panes open/close), but its **pane-id (`%NN`) is
immutable for the life of the pane and targets verbatim in every `send-keys` / `capture-pane`
recipe — exactly as reliable as a window name**. Idle-detection and interaction are *identical*
for a pane and a window; only the target string differs (`%NN` vs `<session>:<window>`). The one
fair caveat: enumerating/killing "my" panes across a whole session is a touch more involved than
for windows (use `list-panes -a` server-wide, filtered by the `@`-marker — see references).

| You want… | Use |
|---|---|
| Another logical worker, human will attach to watch / many workers | A **window** (extra-window naming); identity = window name. |
| Agent runs inside tmux; human wants the driven CLI visible beside them, no attach | A **pane** split into the agent's current window; identity is pane-bound (`@`-marker + pane-id), target = the pane-id. |
| Two views of the *same* worker visible at once (CLI + log tail) | A **pane** split inside that worker's window. |
| To watch a windowed worker without disturbing the driver | Attach to the session and select its window. |

## Core interaction loop

There is **no notification** when an interactive CLI finishes a turn — you must poll. The loop
is always the same four steps; calibrate only the idle signal per tool.

1. **Baseline** — capture the pane *before* sending, to anchor both the activity wait and the
   delta extraction.
2. **Send** — type the prompt, pause briefly, then send `Enter` as a separate key event.
3. **Wait for activity** — poll until the pane *differs* from baseline (the turn started).
4. **Wait for idle** — poll until the pane *stops changing* AND shows the tool's idle/status
   line, requiring 2 consecutive stable reads (debounce). Then extract the delta.

Short forms (substitute `$W` = `cc-codex:<window>`; set `IDLE_REGEX` per tool — see
`references/driving-agent-clis.md`):

```bash
# 1) Baseline BEFORE sending (anchor for activity-wait AND delta).
BASELINE=$(tmux capture-pane -t "$W" -p -S -200)

# 2a) Short, single-line prompt (≤ ~500 chars).
tmux send-keys -t "$W" -l -- "<prompt>"
sleep 0.3                       # let the TUI register the typing burst
tmux send-keys -t "$W" Enter    # Enter as its own event, or it may not submit

# 2b) Long / multi-line / code-block prompt: write the body to a tmp file with the
#     Write tool (NOT a heredoc — avoids delimiter collisions), then reference it:
#     tmux send-keys -t "$W" -l -- "Read @$PROMPT_FILE and follow its instructions."
#     sleep 0.3 && tmux send-keys -t "$W" Enter

# 3) Activity-wait: pane must first differ from BASELINE.
DL=$(( $(date +%s) + 30 ))
while (( $(date +%s) < DL )); do
  [[ "$(tmux capture-pane -t "$W" -p -S -200)" != "$BASELINE" ]] && break
  sleep 0.5
done

# 4) Idle-wait: stable AND idle line, debounced over 2 reads. Match IDLE_REGEX
#    against only the BOTTOM of the pane (the status line) so a response that
#    echoes the marker mid-buffer can't trigger a false "idle".
PREV=""; STABLE=0; DL=$(( $(date +%s) + 600 ))
while (( $(date +%s) < DL )); do
  BUF=$(tmux capture-pane -t "$W" -p -S -200)
  if [[ "$BUF" == "$PREV" ]] && grep -qE "$IDLE_REGEX" <<<"$(printf '%s\n' "$BUF" | tail -3)"; then
    STABLE=$((STABLE+1)); (( STABLE >= 2 )) && break
  else STABLE=0; fi
  PREV="$BUF"; sleep 0.5
done

# 5) Extract the delta (everything emitted since BASELINE). Preferred: line-count
#    tail — robust on redraw-heavy TUIs.
BEFORE_LINES=$(printf '%s\n' "$BASELINE" | wc -l)
AFTER=$(tmux capture-pane -t "$W" -p -S -200)
AFTER_LINES=$(printf '%s\n' "$AFTER" | wc -l)
(( AFTER_LINES > BEFORE_LINES )) && printf '%s\n' "$AFTER" | tail -n "$(( AFTER_LINES - BEFORE_LINES ))"
# Alternative (noisy on redraw-heavy TUIs — spinners/status redraws):
#   diff <(printf '%s\n' "$BASELINE") <(printf '%s\n' "$AFTER") | grep '^>' | sed 's/^> //'

# More scrollback for long responses (>200 lines):
tmux capture-pane -t "$W" -p -S -1000

# Cancel an in-flight turn (most agent TUIs bind Esc to cancel):
tmux send-keys -t "$W" Escape
```

**Readiness-or-dead check (right after spawn).** A freshly spawned target — window **or** pane —
is not guaranteed to be alive: a bad flag, missing auth, or a crash can make the CLI exit at
launch. Before driving, confirm it is up, and if it died, surface *why* instead of waiting out
the full idle timeout against a dead target:

```bash
# Pane placement: poll #{pane_dead}; window placement: use process state (window_state).
if [[ "$(tmux display -p -t "$TARGET" '#{pane_dead}')" == 1 ]]; then
  echo "Driven CLI exited at launch. Last output:"
  tmux capture-pane -t "$TARGET" -p -S -50      # show the failure reason
  # do NOT send a prompt — respawn/fix first.
fi
```

Only once the target is confirmed live (pane not dead / process running) do you run the loop's
readiness wait for the idle prompt. See `references/sync-and-lifecycle.md`.

**Why two phases:** the idle/status line is usually present *both* before sending and after the
turn completes, so a stability-only loop exits immediately on the pre-send pane (false "done").
The activity-wait phase fixes this by requiring the pane to first change. Full recipes —
send-inline, send-via-tmpfile, detect-idle, extract-delta, incremental-capture, copy-mode,
cancel, handle-interruption — with rationale: `references/interaction-recipes.md`.

## One-driver discipline

Each driven window has **exactly one driver at a time** — you. Two concurrent writers
interleave keystrokes and corrupt both the prompt and your idle detection.

- Complete the full loop (send → wait-idle → extract) for a window before issuing the next
  send to it. Do not pipeline sends.
- Serialize lifecycle operations (spawn/find/kill) with a per-session `flock` so two turns
  don't race to create or remove the same window.
- A human attaching to *watch* is fine; a human *typing* while you drive is not — surface that
  the window is being driven if you detect unexpected input.

Locking, race-free spawn/find, and the lock-free macOS fallback: `references/sync-and-lifecycle.md`.

## Lifecycle & cleanup

- **Stay in your lane (agent-session isolation).** Each agent owns only the workers it created,
  identified by its own `@<tool>-<claude6>` marker. Reuse, relocate, spawn, and scoped cleanup
  must touch ONLY your own markered panes/windows — **never** move, kill, or reuse a pane/window
  belonging to another agent (a different `claude6`) or one you did not create. A *global* reap
  of every agent's dead workers is a separate, explicit command — use it only when the user
  asks to clean up everything, never as part of normal work.
- **Bind, don't accumulate.** Ensure the single bound window exists (create if absent, reuse if
  alive, respawn if dead), then drive it. Spawn extra windows only on explicit request.
- Set `remain-on-exit failed` so a *crashed* CLI (non-zero exit) leaves its scrollback for
  diagnosis, while a *clean* exit auto-closes the pane (no dead-pane corpse in a live window).
  Use `on` only for a window the human isn't actively viewing.
- **Keep-shell alternative:** wrap the driven CLI so its exit `exec`s an interactive shell
  (`<cli> …; exec "$SHELL" -l`) — the pane then survives the CLI exiting, stays manually
  usable, and the driver can relaunch the CLI in place later. The cost: liveness can no
  longer be read from `#{pane_dead}` — detect the CLI by walking the pane's process tree
  instead. The codex plugin implements this as its default; see its `codex-tmux.sh` for the
  reference implementation (states `alive` / `shell` / `dead`).
- Detect state without parsing the pane: a window is `alive`/`dead`/`unknown` from tmux plus
  process inspection.
- **Never kill silently** — killing destroys scrollback irreversibly. Tell the user which
  windows you'll remove and confirm, unless they explicitly said "kill all".

Spawn/find/kill, orphan/dead detection, and `remain-on-exit` details:
`references/sync-and-lifecycle.md`.

## Decision table

| Situation | Action |
|---|---|
| First interaction with a tool this conversation | Ensure the **bound** window `<tool>-<claude6>` exists, then drive it. |
| Follow-up / "continue" / "now also…" | Reuse the same bound window; run the loop again. |
| User explicitly asks for a separate / parallel task | Spawn an **extra** window `<tool>-<topic>-<claude6>-<rand2>`. |
| Agent runs inside tmux, human wants the driven CLI visible beside them, no attach | Split a **pane** into the agent's **current window**; pane-bound identity (`@<tool>_<claude6>` user-option), target = the **pane-id**. |
| Need two views of one worker at once (CLI + log) | Split a **pane** inside that window. |
| Prompt ≤ ~500 chars, single line | `short-inline-prompt` recipe. |
| Prompt multi-line / code blocks / > ~1KB | `tmp-file-prompt` recipe (Write tool → tmp file). |
| "Is it done?" | `detect-idle` (two-phase: activity-wait → stability). |
| Reading the latest response | `extract-delta`. |
| Response > ~200 lines / > history-limit | `incremental-capture` / `copy-mode-navigation`. |
| User says "stop / cancel / never mind" mid-turn | `cancel-in-flight` (send `Escape`), then re-detect idle. |
| CLI shows an unexpected non-response prompt | `handle-interruption`. |
| Wrapping up | Offer cleanup; confirm before any kill. |

## Applies to codex / gemini / aider

The loop above is identical across agent CLIs; only the **idle signal** and a few keys differ:

- **codex** — idle/status line matches `gpt-5\.[0-9].*·` (model-agnostic across the 5.x slugs;
  the middot before the cwd path in `gpt-5.6-sol xhigh · /path`); `Esc` cancels. Anchor to the
  ` · /path` status line, not just the model name, because the model name can appear in response
  text. The codex plugin is the **reference implementation**: it adds `pane` (default) / `bind`
  (fallback) lifecycle commands, sandbox/approval flags, and hooks-review handling on top of
  this skill.
- **gemini** — calibrate `IDLE_REGEX` to the gemini prompt/status line; otherwise the same loop.
- **aider** — calibrate to its `>` prompt; same send/capture/idle pattern.
- **any REPL** — pick a regex that matches the input-ready prompt and reuse the loop.

To calibrate a new tool, run `tmux capture-pane -t "$W" -p | tail -5` while it sits idle and
build `IDLE_REGEX` from what appears near the bottom. Match it against only the last few lines
of the pane (as the loop above does) and anchor it to something the CLI does NOT print
mid-stream (a status-line suffix), so a response that echoes the marker can't trigger an early
idle. Per-CLI calibration tables and the pointer to the codex reference implementation:
`references/driving-agent-clis.md`.

## Reference index

- `references/model-and-identity.md` — session/window/pane model; `claude6` identity; naming;
  binding and reuse; topic-slug derivation; the matcher contract.
- `references/interaction-recipes.md` — send-inline, send-via-tmpfile, detect-idle (two-phase),
  extract-delta, incremental-capture, copy-mode, cancel, handle-interruption.
- `references/sync-and-lifecycle.md` — one-driver discipline, `flock` serialization,
  spawn/find/kill/cleanup, orphan/dead detection, `remain-on-exit`.
- `references/driving-agent-clis.md` — per-CLI calibration (codex/gemini/aider/generic REPL);
  points to the codex plugin as the reference implementation.
