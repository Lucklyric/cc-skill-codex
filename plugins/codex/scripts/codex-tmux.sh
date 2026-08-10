#!/usr/bin/env bash
# codex-tmux.sh — drive interactive codex sessions inside tmux.
# See plugins/codex/skills/codex/references/tmux-mode.md for usage docs.
#
# Permanent thin wrapper (spec 016, T1): the kind-agnostic lifecycle engine
# lives in agent-tmux.sh + profiles/codex.sh; this wrapper keeps the historic
# codex CLI surface stable — every verb, flag, exit code and CC_CODEX_* env
# var works unchanged. It maps CC_CODEX_* onto the engine's CC_AGENT_* names,
# delegates lifecycle verbs with --kind codex, and implements the codex-only
# `exec` verb (plus the removed send/capture migration stubs) itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults come from the codex profile (single source of truth for
# version-sensitive facts); used by exec and the send/capture stub text.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/profiles/codex.sh"
readonly SESSION_NAME="${CC_CODEX_SESSION_NAME:-cc-codex}"
readonly CODEX_BIN="${CC_CODEX_BIN:-$PROFILE_BIN_DEFAULT}"
readonly CODEX_MODEL="${CC_CODEX_MODEL:-$PROFILE_MODEL_DEFAULT}"
readonly CODEX_EFFORT="${CC_CODEX_EFFORT:-$PROFILE_EFFORT_DEFAULT}"

# Map legacy CC_CODEX_* env vars onto the engine's generic CC_AGENT_* names.
# Exported only when the CC_CODEX_ var is actually set, so the engine's
# "explicitly overridden?" checks (reuse warnings) keep their exact semantics.
# When it is NOT set, the generic name is UNSET: a stray CC_AGENT_* in the
# caller's environment must not change codex behavior vs v3.10.0, which only
# ever read CC_CODEX_*.
map_env() {
    local pair legacy generic
    for pair in SESSION_NAME BIN MODEL EFFORT KEEP_SHELL EXIT_SHELL REMAIN_ON_EXIT REF_PANE IDLE_REGEX BUSY_REGEX; do
        legacy="CC_CODEX_$pair"
        generic="CC_AGENT_$pair"
        if [[ -n "${!legacy+x}" ]]; then
            export "$generic"="${!legacy}"
        else
            unset "$generic"
        fi
    done
}

cmd_exec() {
    # Pass through all args to `codex exec`, but inject defaults if the caller
    # didn't specify them.
    local has_m=0 has_s=0 has_effort=0
    for a in "$@"; do
        case "$a" in
            -m|--model|-m=*|--model=*) has_m=1 ;;
            -s|--sandbox|-s=*|--sandbox=*) has_s=1 ;;
            model_reasoning_effort=*|*model_reasoning_effort=*) has_effort=1 ;;
        esac
    done

    local cmd=( "$CODEX_BIN" exec )
    (( has_m )) || cmd+=( -m "$CODEX_MODEL" )
    (( has_s )) || cmd+=( -s read-only )
    (( has_effort )) || cmd+=( -c "model_reasoning_effort=$CODEX_EFFORT" )
    cmd+=( "$@" )

    exec "${cmd[@]}"
}

# ---------- Usage ----------
usage() {
    cat <<'EOF'
Usage: codex-tmux.sh <subcommand> [args...]

Subcommands:
  pane [--topic SLUG] [--cwd DIR] [--full-auto|--read-only] [--horizontal|--vertical] [--size PCT]
      DEFAULT when Claude runs inside tmux. Spawn / locate / reuse a single
      codex instance as a PANE split into the CURRENT Claude window (right
      next to Claude, so progress is visible with no separate attach).
      Idempotent per Claude session (reuse is server-wide, surviving window
      moves): reuses the live codex pane if present, relaunches codex inside
      the kept shell pane if codex exited (keep-shell default), respawns it
      if dead, else splits a new one. Prints the pane id (e.g. %53) on
      stdout line 1.
      --topic SLUG (2-15 chars, [a-z0-9-]; default: main) addresses an EXTRA
      topic-named pane in the same window; each topic gets its own pane with
      the same per-topic reuse/relocate/respawn semantics.
      Exits 3 (use `bind`) when not inside tmux; exits 4 if codex dies on
      launch (after one retry; codex output on stderr). Default split:
      horizontal, 45% (--size 10-90); auto-switches to vertical if a
      horizontal split would leave codex <80 cols.

  panes [--all]
      Read-only detection: list codex PANES server-wide, one TSV line per
      pane: "<pane_id>\t<topic>\t<state>\t<session:window_index>\t<cwd>"
      (state = alive|shell|dead; shell = codex exited, pane kept at an
      interactive shell). Filtered to the current Claude session's claude6
      by default; --all lists every agent's codex panes. Exits 0 if at least
      one line was printed, 1 otherwise. Never creates the cc-codex session.

  bind [--cwd DIR] [--full-auto|--read-only]
      Dedicated-window mode / fallback when NOT inside tmux. Bind this Claude
      session to its single reused codex window (codex-<claude6>) in the
      cc-codex session and print it. Idempotent: creates codex if absent,
      reuses if alive, relaunches codex in the kept shell if codex exited,
      respawns if dead. Prints the window name on stdout line 1 plus an
      attach hint on line 2.

  new <topic> [--cwd DIR] [--full-auto|--read-only]
      Create a new codex window in the cc-codex tmux session. Use ONLY when a
      SEPARATE WINDOW is explicitly requested; the default is `pane` (extra
      panes via `pane --topic`), with `bind` as the outside-tmux fallback.
      Prints the full window name on stdout plus an attach hint.

  prompt [--target T|--topic SLUG] [--file PATH] [--wait] [--timeout SECS] [--] <text...>
      Type a prompt into the codex pane: literal send-keys, short pause, then
      Enter as its own key event. Long or multi-line text is handed over via
      a tmp file automatically ("Read @file ..."). Records the baseline that
      `wait` and `read --delta` anchor to. --wait chains straight into `wait`.
      Default target: this session's main-topic pane (override with --target
      %pane-id/window or --topic SLUG).

  wait [--target T|--topic SLUG] [--timeout SECS] [--activity-timeout SECS]
      Block until codex's turn settles: after a `prompt`, first requires pane
      activity (exit 8 = stalled if none), then a stable pane showing the
      idle status line (gpt-5.x · path) at the bottom. Standalone `wait`
      answers "is it idle now?". Prints "idle", exit 0; 5 = timeout,
      6 = no target, 9 = codex exited (kept shell).

  read [--target T|--topic SLUG] [--delta] [--lines N]
      Print the pane. --delta = only what codex emitted since the last
      `prompt` (line-count tail; works on kept-shell panes too);
      default = the last N (200) lines of scrollback.

  cancel [--target T|--topic SLUG]
      Send Escape to cancel the in-flight turn; re-run `wait` afterwards.

  send | capture
      Removed in v3.1.0 — see references/tmux-mode.md for the skill recipes
      that replace them.

  ls [--mine]
      List codex windows. --mine filters to the current Claude session id.

  find <topic> [--cwd DIR] [--include-dead] [--any-session]
      Look up matching codex windows in the current Claude session's
      claude6 namespace. Prints "<window>\t<state>\t<cwd>" lines for
      matches; exits 0 if anything matched, 1 otherwise. Use BEFORE
      `new` to decide whether to reuse an existing window.

  attach <window>
      Print the shell command the user can run to attach to a window.

  rename <old-window> <new-topic>
      Rename a window's topic portion; preserves the suffix.

  kill <window> | kill <%pane-id> | kill --mine | kill --orphaned
      Kill a specific window, a codex PANE by its pane id (e.g. %53, pane
      mode), all of the current Claude session's codex windows AND panes
      (--mine, matched by claude6), or every dead codex window/pane on the
      server (--orphaned). --mine and --orphaned are pane-aware.

  exec [codex-exec flags...] <prompt>
      Run codex exec one-shot outside tmux (escape hatch).

Environment:
  CC_CODEX_SESSION_NAME  (default: cc-codex)
  CC_CODEX_BIN           (default: codex)
  CC_CODEX_MODEL         (default: gpt-5.6-sol; e.g. gpt-5.6-terra, gpt-5.6-luna,
                          or gpt-5.5 on a codex CLI < 0.144.0)
  CC_CODEX_EFFORT        (default: xhigh; ladder low<medium<high<xhigh<max<ultra —
                          max/ultra are 5.6-series; ultra is sol/terra only)
  CC_CODEX_KEEP_SHELL    (default: 1 — when codex exits, the pane drops into an
                          interactive shell and stays for manual use; `exit`
                          closes it. 0 = legacy: codex exit closes the pane per
                          CC_CODEX_REMAIN_ON_EXIT)
  CC_CODEX_EXIT_SHELL    (default: $SHELL; the shell keep-shell drops into)
  CC_CODEX_REMAIN_ON_EXIT (default: failed; governs the pane's ROOT process —
                          the kept shell under keep-shell, codex itself with
                          CC_CODEX_KEEP_SHELL=0)
  CC_CODEX_IDLE_REGEX     (default: the profile's model-agnostic status-line
                          regex; used by `wait`/`prompt --wait`)
  Model/effort/sandbox bind when codex STARTS; overrides on a live reuse warn
  on stderr instead of applying (they DO apply when the kept shell relaunches
  codex, since that is a fresh start).
EOF
}

# ---------- Dispatch ----------
main() {
    if [[ $# -eq 0 ]]; then
        usage >&2
        exit 2
    fi

    local subcmd="$1"
    shift || true

    case "$subcmd" in
        -h|--help|help)
            usage
            ;;
        pane|panes|bind|new|prompt|wait|read|cancel|ls|find|attach|rename|kill|_internal)
            map_env
            exec "$SCRIPT_DIR/agent-tmux.sh" --kind codex "$subcmd" "$@"
            ;;
        send|capture)
            cat <<EOF >&2
codex-tmux: '$subcmd' was removed in v3.1.0.

Interaction is now driven by the codex skill directly. See:
  plugins/codex/skills/codex/references/tmux-mode.md  (recipes)

Quick replacements:
  send    → tmux send-keys -t $SESSION_NAME:<window> -l -- "<prompt>"
            sleep 0.3
            tmux send-keys -t $SESSION_NAME:<window> Enter
            (then capture-pane and read the delta yourself)
  capture → tmux capture-pane -t $SESSION_NAME:<window> -p
EOF
            exit 64
            ;;
        exec) cmd_exec "$@" ;;
        *)
            echo "codex-tmux: unknown subcommand '$subcmd'" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
