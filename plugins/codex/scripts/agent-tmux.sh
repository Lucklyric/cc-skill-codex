#!/usr/bin/env bash
# agent-tmux.sh — drive an interactive agent CLI (codex, claude, ...) inside
# tmux: spawn/reuse/relocate panes and windows, keep-shell lifecycle, identity
# markers, and state detection. Kind-agnostic: everything CLI-specific comes
# from a profile sourced from profiles/<kind>.sh (see profiles/codex.sh for
# the contract). Callers normally go through a kind wrapper (codex-tmux.sh),
# which maps legacy env vars and adds kind-only verbs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set after profile load (init_globals): KIND, LABEL (=<kind>-tmux, message
# prefix), WIN_PREFIX (window/title prefix), OPT_PREFIX (pane/window option prefix,
# cc_<kind>), SESSION_NAME, AGENT_BIN/MODEL/EFFORT, REMAIN_ON_EXIT,
# KEEP_SHELL, EXIT_SHELL, AGENT_TITLE, RESUME_CMD, LOGIN_HINT.
KIND=""

init_globals() {
    LABEL="${KIND}-tmux"
    WIN_PREFIX="$KIND"
    OPT_PREFIX="cc_${KIND}"
    AGENT_TITLE="${PROFILE_TITLE:-$KIND}"
    # Single quotes are stripped: RESUME_CMD is interpolated into the
    # single-quoted printf format of the keep-shell hint (compose_launch_cmd),
    # where a literal ' would break the whole launch command's quoting.
    RESUME_CMD="${PROFILE_RESUME_CMD//\'/}"
    LOGIN_HINT="${PROFILE_LOGIN_HINT:-}"
    # Fresh-start safety defaults (sandbox mode / approval policy) come from
    # the profile; the generic --full-auto/--read-only flags map onto them.
    SANDBOX_DEFAULT="${PROFILE_SANDBOX_DEFAULT:-read-only}"
    APPROVAL_DEFAULT="${PROFILE_APPROVAL_DEFAULT:-on-request}"
    # Env-var prefix shown in user-facing messages (the kind wrapper's legacy
    # names, e.g. CC_CODEX — the vars users actually set).
    ENV_PREFIX="${PROFILE_ENV_PREFIX:-CC_AGENT}"
    # Input-ready detection for the driving verbs (`wait`, `prompt --wait`):
    # a regex matched against the BOTTOM of the pane (last 3 lines). Empty →
    # stability-only detection (more consecutive unchanged polls required).
    IDLE_REGEX="${CC_AGENT_IDLE_REGEX:-${PROFILE_IDLE_REGEX:-}}"
    # Busy detection (the inverse): while this regex matches the last 15 pane
    # lines the turn is still running, whatever else looks stable. For TUIs
    # whose idle footer is user-configurable (Claude Code statuslines), a
    # universal busy marker ("esc to interrupt") beats any idle marker.
    BUSY_REGEX="${CC_AGENT_BUSY_REGEX:-${PROFILE_BUSY_REGEX:-}}"
    readonly SESSION_NAME="${CC_AGENT_SESSION_NAME:-cc-$KIND}"
    readonly AGENT_BIN="${CC_AGENT_BIN:-${PROFILE_BIN_DEFAULT:-$KIND}}"
    # How the pane/window behaves when its ROOT process exits. With keep-shell
    # (default, below) the root process is the wrapper/kept shell, so this only
    # matters when that shell exits (user types `exit`) or is killed:
    #   failed (default) — keep the pane ONLY on a non-zero (crash) exit so you
    #                      can read the error; a clean exit auto-closes the pane.
    #   on               — always keep the dead pane (preserves the final screen).
    #   off              — always close the pane when the root process exits.
    readonly REMAIN_ON_EXIT="${CC_AGENT_REMAIN_ON_EXIT:-failed}"
    # Keep-shell behavior: what happens to the pane/window when the AGENT exits.
    #   1 (default) — the agent CLI is wrapped so that when it exits (cleanly or
    #                 crashed), the pane drops into an interactive shell: the
    #                 pane stays where it is, scrollback intact, usable MANUALLY
    #                 (e.g. the profile's resume command continues the
    #                 conversation by hand). Typing `exit` in that shell closes
    #                 the pane. The next `pane`/`bind` call relaunches the agent
    #                 inside the kept shell instead of splitting a new pane.
    #   0           — legacy: the agent is the pane's root process, so its exit
    #                 closes the pane per CC_AGENT_REMAIN_ON_EXIT above.
    readonly KEEP_SHELL="${CC_AGENT_KEEP_SHELL:-1}"
    # Shell to drop into when the agent exits under keep-shell.
    readonly EXIT_SHELL="${CC_AGENT_EXIT_SHELL:-${SHELL:-/bin/sh}}"
    # Model and reasoning effort for every spawned agent; defaults come from the
    # profile. Explicit CC_AGENT_MODEL/CC_AGENT_EFFORT (set by the kind wrapper
    # from its legacy vars) bind when the agent STARTS; on a live reuse they
    # warn instead of applying (they DO apply on a keep-shell relaunch).
    readonly AGENT_MODEL="${CC_AGENT_MODEL:-${PROFILE_MODEL_DEFAULT:-}}"
    readonly AGENT_EFFORT="${CC_AGENT_EFFORT:-${PROFILE_EFFORT_DEFAULT:-}}"
}

# ---------- Pure helpers (no tmux, no agent CLI) ----------

compute_claude6() {
    # The per-agent isolation token: the first 6 chars of $CLAUDE_CODE_SESSION_ID.
    # This is the ONLY isolation boundary — two agents whose session ids share a
    # 6-char prefix would resolve to the same worker (reuse/kill each other's).
    # Session ids are random UUIDs, so a real collision is ~1 in 16M; if you run
    # synthetic/fixed session ids (e.g. tests), keep their 6-char prefixes unique.
    if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
        printf '%s' "${CLAUDE_CODE_SESSION_ID:0:6}"
        return
    fi
    # Fallback: deterministic for the duration of a parent shell session.
    printf '%s' "$PPID:$PWD" | shasum -a 256 | cut -c1-6
}

validate_topic() {
    local topic="$1"
    if [[ ! "$topic" =~ ^[a-z0-9-]{2,15}$ ]]; then
        echo "$LABEL: invalid topic '$topic' (must be 2-15 chars, [a-z0-9-])" >&2
        return 1
    fi
}

rand_suffix() {
    # Two random chars from [a-z0-9].
    local chars='abcdefghijklmnopqrstuvwxyz0123456789'
    printf '%s%s' \
        "${chars:RANDOM%36:1}" \
        "${chars:RANDOM%36:1}"
}

compose_window_name() {
    local topic="$1"
    validate_topic "$topic" || return 1
    printf '%s-%s-%s-%s' "$WIN_PREFIX" "$topic" "$(compute_claude6)" "$(rand_suffix)"
}

# ---------- tmux primitives ----------

ensure_tmux_or_die() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "$LABEL: 'tmux' is not installed. Install with: brew install tmux" >&2
        exit 127
    fi
}

ensure_session() {
    ensure_tmux_or_die
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        # Create detached, with a placeholder first window we'll never use.
        tmux new-session -d -s "$SESSION_NAME" -n "_placeholder" -x 200 -y 50
        # Optionally: set the placeholder to do nothing useful.
        tmux send-keys -t "$SESSION_NAME:_placeholder" "echo '$SESSION_NAME placeholder — do not use'" Enter
    fi
}

window_exists() {
    local window="$1"
    ensure_tmux_or_die
    tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null \
        | grep -Fxq "$window"
}

window_pane_pid() {
    # Print the pid of the first pane in the named window.
    local window="$1"
    tmux list-panes -t "$SESSION_NAME:$window" -F '#{pane_pid}' 2>/dev/null | head -n1
}

# True (0) if an agent process is running at, or up to two levels below, the
# given pid. Matched by comparing the agent binary's basename against the
# first TWO argv words of each process, so both a binary ("codex -m …") and
# an interpreter-run script ("bash /path/mock-codex.sh -m …", tests) match.
# $2 (optional) is the binary the pane/window was LAUNCHED with (recorded as
# @<opt>_bin at spawn) so detection stays correct even when the current
# call runs with a different bin override; defaults to $AGENT_BIN.
# Level 0 covers legacy direct-exec panes; level 1 covers the keep-shell
# wrapper (wrapper-shell → agent) AND an agent relaunched manually from the
# kept shell; level 2 covers one nested shell more.
agent_running_under() {
    local root="$1" want="${2:-$AGENT_BIN}"
    [[ -z "$root" ]] && return 1
    [[ -z "$want" || "$want" == "-" ]] && want="$AGENT_BIN"
    want="${want##*/}"
    local pids p kids=""
    kids="$(pgrep -P "$root" 2>/dev/null | tr '\n' ' ')" || true
    pids="$root $kids"
    for p in $kids; do
        pids+=" $(pgrep -P "$p" 2>/dev/null | tr '\n' ' ' || true)"
    done
    # Basename via parameter expansion, NOT basename(1): ps argv words can
    # start with '-' ("-zsh", "-c"), which basename(1) parses as options and
    # noisily rejects on stderr.
    local args tok1 tok2 rest
    for p in $pids; do
        args="$(ps -o args= -p "$p" 2>/dev/null || true)"
        [[ -z "$args" ]] && continue
        tok1="${args%% *}"
        rest="${args#"$tok1"}"; rest="${rest# }"
        tok2="${rest%% *}"
        if [[ "${tok1##*/}" == "$want" ]]; then return 0; fi
        if [[ -n "$tok2" && "${tok2##*/}" == "$want" ]]; then return 0; fi
    done
    return 1
}

# Compose the tmux shell-command string that launches the agent (argv passed
# as args, shell-quoted here). Under keep-shell (default), the agent is
# wrapped so that when it exits — cleanly or crashed — the pane prints a hint
# and drops into an interactive shell instead of closing. CC_AGENT_KEEP_SHELL=0
# restores the legacy direct launch.
compose_launch_cmd() {
    local launch
    launch="$(printf '%q ' "$@")"
    launch="${launch% }"
    if [[ "$KEEP_SHELL" == "0" ]]; then
        printf '%s' "$launch"
        return
    fi
    local sh_q
    sh_q="$(printf '%q' "$EXIT_SHELL")"
    printf '%s' "$launch; printf '\\n[$KIND exited (status %s) -- pane kept for manual use: $RESUME_CMD continues the conversation; exit closes the pane]\\n' \"\$?\"; exec $sh_q -l"
}

# Build the agent launch argv for a fresh start. Delegates flag composition to
# the profile's agent_compose_cmd (sets the AGENT_CMD array from AGENT_BIN,
# AGENT_MODEL, AGENT_EFFORT plus the sandbox/approval arguments).
build_agent_cmd() {
    local sandbox="$1" approval="$2"
    AGENT_CMD=()
    agent_compose_cmd "$sandbox" "$approval"
}

# Relaunch the agent inside an existing keep-shell target (pane id or
# session:window) by typing the launch command into its interactive shell —
# same pane, geometry and scrollback preserved. A relaunch is a fresh agent
# START, so the CURRENT sandbox/model/effort apply (unlike a live reuse,
# where overrides only warn). Waits for the agent process to appear; returns
# 1 if it did not start (caller falls back to kill + fresh spawn).
relaunch_agent_in() {
    local target="$1" cwd="$2" sandbox="$3" approval="$4"
    build_agent_cmd "$sandbox" "$approval"
    local launch
    launch="$(printf '%q ' "${AGENT_CMD[@]}")"
    launch="${launch% }"
    tmux send-keys -t "$target" -l -- "cd $(printf '%q' "$cwd") && $launch" 2>/dev/null || return 1
    sleep 0.2
    tmux send-keys -t "$target" Enter 2>/dev/null || return 1
    local pid i
    for (( i = 0; i < 16; i++ )); do
        sleep 0.3
        pid="$(tmux display-message -p -t "$target" '#{pane_pid}' 2>/dev/null || true)"
        if [[ -n "$pid" ]] && agent_running_under "$pid"; then
            return 0
        fi
    done
    return 1
}

# ---------- Subcommands ----------

cmd_new() {
    local topic=""
    local cwd="$PWD"
    local sandbox="$SANDBOX_DEFAULT"
    local approval="$APPROVAL_DEFAULT"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cwd) cwd="$2"; shift 2 ;;
            --full-auto) sandbox="workspace-write"; shift ;;
            --read-only) sandbox="read-only"; shift ;;
            -*) echo "$LABEL new: unknown flag '$1'" >&2; return 2 ;;
            *) topic="$1"; shift ;;
        esac
    done

    if [[ -z "$topic" ]]; then
        echo "$LABEL new: topic required (e.g., '$LABEL.sh new auth')" >&2
        return 2
    fi
    validate_topic "$topic" || return 2

    ensure_session

    # Compose unique window name (retry once on extremely unlikely collision).
    local window
    window="$(compose_window_name "$topic")"
    if window_exists "$window"; then
        window="$(compose_window_name "$topic")"
        if window_exists "$window"; then
            echo "$LABEL new: name collision for topic '$topic' (retry failed)" >&2
            return 17
        fi
    fi

    build_agent_cmd "$sandbox" "$approval"

    # Spawn the window detached (keep-shell wrapper unless CC_AGENT_KEEP_SHELL=0).
    tmux new-window -t "$SESSION_NAME" -n "$window" -d -c "$cwd" \
        "$(compose_launch_cmd "${AGENT_CMD[@]}")"

    # remain-on-exit ($REMAIN_ON_EXIT, default 'failed'): keep the window on a
    # crash (non-zero exit) so the error is readable; a clean exit auto-closes it.
    # Must be set ASAP after new-window. All post-spawn options are guarded: if
    # the agent exits instantly the window may already be gone, and an unguarded
    # failure would abort under `set -e`.
    tmux set-option -w -t "$SESSION_NAME:$window" remain-on-exit "$REMAIN_ON_EXIT" 2>/dev/null || true

    # Record metadata as per-window user options.
    tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_cwd" "$cwd" 2>/dev/null || true
    tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_created" "$(date '+%Y-%m-%dT%H:%M:%S%z')" 2>/dev/null || true
    tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_topic" "$topic" 2>/dev/null || true
    tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_model" "$AGENT_MODEL" 2>/dev/null || true
    tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_effort" "$AGENT_EFFORT" 2>/dev/null || true
    tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_bin" "$AGENT_BIN" 2>/dev/null || true

    # Output: window name on stdout line 1, attach hint on line 2.
    echo "$window"
    echo "Attach with: tmux attach -t $SESSION_NAME \; select-window -t $window"
}

cmd_bind() {
    # Idempotently bind the current Claude session to a single reused agent
    # window named "<kind>-<claude6>" (topic-agnostic). Create the agent in it
    # if absent, reuse it if alive, respawn it if dead. This is the default
    # entry point; `new` is reserved for explicit extra/parallel windows.
    local cwd="$PWD"
    local sandbox="$SANDBOX_DEFAULT"
    local approval="$APPROVAL_DEFAULT"
    local want_sandbox=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cwd) cwd="$2"; shift 2 ;;
            --full-auto) sandbox="workspace-write"; want_sandbox="workspace-write"; shift ;;
            --read-only) sandbox="read-only"; want_sandbox="read-only"; shift ;;
            -*) echo "$LABEL bind: unknown flag '$1'" >&2; return 2 ;;
            *) echo "$LABEL bind: unexpected arg '$1'" >&2; return 2 ;;
        esac
    done

    ensure_session

    local window
    window="$WIN_PREFIX-$(compute_claude6)"
    if window_exists "$window"; then
        local state
        state="$(window_state "$window")"
        if [[ "$state" == "alive" ]]; then
            # Reuse the live window. Warn (don't fail) on a sandbox mismatch so
            # the skill can decide whether to kill + re-bind.
            local existing
            existing="$(tmux show-option -wqv -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_sandbox" 2>/dev/null)"
            if [[ -n "$want_sandbox" && -n "$existing" && "$want_sandbox" != "$existing" ]]; then
                echo "$LABEL bind: bound window '$window' is '$existing'; requested '$want_sandbox'. Kill and re-bind to switch ($LABEL.sh kill $window && $LABEL.sh bind --$want_sandbox)." >&2
            fi
            # Same for an explicit model/effort override: it cannot apply to an
            # already-running agent, so warn instead of silently ignoring.
            local existing_model existing_effort
            existing_model="$(tmux show-option -wqv -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_model" 2>/dev/null)"
            existing_effort="$(tmux show-option -wqv -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_effort" 2>/dev/null)"
            if { [[ -n "${CC_AGENT_MODEL+x}" && -n "$existing_model" && "$AGENT_MODEL" != "$existing_model" ]]; } \
                || { [[ -n "${CC_AGENT_EFFORT+x}" && -n "$existing_effort" && "$AGENT_EFFORT" != "$existing_effort" ]]; }; then
                echo "$LABEL bind: reusing window '$window' (model '${existing_model:-?}', effort '${existing_effort:-?}'); ${ENV_PREFIX}_MODEL/${ENV_PREFIX}_EFFORT do NOT apply to a reused window. Kill and re-bind to switch ($LABEL.sh kill $window && $LABEL.sh bind)." >&2
            fi
            echo "$window"
            echo "Attach with: tmux attach -t $SESSION_NAME \; select-window -t $window"
            return 0
        elif [[ "$state" == "shell" ]]; then
            # Keep-shell window: the agent exited but the window sits at an
            # interactive shell. Relaunch the agent inside it (fresh start, so
            # the requested sandbox/model/effort apply); fall through to a full
            # respawn only if the relaunch fails.
            if relaunch_agent_in "$SESSION_NAME:$window" "$cwd" "$sandbox" "$approval"; then
                tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_cwd" "$cwd" 2>/dev/null || true
                tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_sandbox" "$sandbox" 2>/dev/null || true
                tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_model" "$AGENT_MODEL" 2>/dev/null || true
                tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_effort" "$AGENT_EFFORT" 2>/dev/null || true
                tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_bin" "$AGENT_BIN" 2>/dev/null || true
                echo "$window"
                echo "Attach with: tmux attach -t $SESSION_NAME \; select-window -t $window"
                return 0
            fi
            tmux kill-window -t "$SESSION_NAME:$window" 2>/dev/null || true
        else
            # Dead/orphaned: clear it out and respawn below.
            tmux kill-window -t "$SESSION_NAME:$window" 2>/dev/null || true
        fi
    fi

    build_agent_cmd "$sandbox" "$approval"

    # Spawn the bound window detached, then verify the agent survived launch;
    # retry once on immediate exit (transient home-dir / MCP init hiccups
    # happen), mirroring cmd_pane. Report exit 4 instead of returning a dead
    # window the caller would then drive blindly.
    local attempt=0
    while (( attempt < 2 )); do
        attempt=$(( attempt + 1 ))
        tmux new-window -t "$SESSION_NAME" -n "$window" -d -c "$cwd" \
            "$(compose_launch_cmd "${AGENT_CMD[@]}")"

        # remain-on-exit ($REMAIN_ON_EXIT, default 'failed'): keep the window on
        # a crash so the error is readable; a clean exit auto-closes it. Set ASAP
        # after new-window.
        # All post-spawn options are guarded: if the agent exits instantly the
        # window may already be gone, and an unguarded failure would abort
        # under `set -e`.
        tmux set-option -w -t "$SESSION_NAME:$window" remain-on-exit "$REMAIN_ON_EXIT" 2>/dev/null || true
        tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_cwd" "$cwd" 2>/dev/null || true
        tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_created" "$(date '+%Y-%m-%dT%H:%M:%S%z')" 2>/dev/null || true
        tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_sandbox" "$sandbox" 2>/dev/null || true
        tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_model" "$AGENT_MODEL" 2>/dev/null || true
        tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_effort" "$AGENT_EFFORT" 2>/dev/null || true
        tmux set-option -w -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_bin" "$AGENT_BIN" 2>/dev/null || true

        sleep 0.4
        if [[ "$(window_state "$window")" == "alive" ]]; then
            # Output: window name on stdout line 1, attach hint on line 2.
            echo "$window"
            echo "Attach with: tmux attach -t $SESSION_NAME \; select-window -t $window"
            return 0
        fi
        echo "$LABEL bind: $KIND exited immediately in $window (attempt $attempt):" >&2
        tmux capture-pane -t "$SESSION_NAME:$window" -p -S -20 2>/dev/null | sed 's/^/  | /' >&2 || true
        tmux kill-window -t "$SESSION_NAME:$window" 2>/dev/null || true
        sleep 0.5
    done
    echo "$LABEL bind: $KIND exited immediately twice; aborting. Check '$LOGIN_HINT', then re-run." >&2
    return 4
}

# ---------- Pane mode (the agent as a pane in the current Claude window) ----------

# Reference pane = the pane Claude Code itself runs in. Overridable for tests.
current_ref_pane() {
    printf '%s' "${CC_AGENT_REF_PANE:-${TMUX_PANE:-}}"
}

# Resolve the window target ("session:window_index") that contains a pane.
pane_window_target() {
    local pane="$1"
    tmux display-message -p -t "$pane" '#{session_name}:#{window_index}' 2>/dev/null
}

# State of an agent pane:
#   alive — pane exists and an agent process is running in it
#   shell — pane exists, the agent exited, an interactive shell holds the pane
#           (keep-shell default; the pane is manually usable / relaunchable)
#   dead  — the pane's root process exited (kept around by remain-on-exit)
#   gone  — the pane no longer exists
# NOTE: `display-message -t <stale-id>` silently falls back to the active pane
# (returning a bogus state), so we must exact-match the pane id in the live
# pane list instead of trusting display-message.
pane_agent_state() {
    local pane="$1" row
    row="$(tmux list-panes -a -F '#{pane_id} #{pane_dead} #{pane_pid}' 2>/dev/null \
        | awk -v p="$pane" '$1==p { print $2 " " $3; f=1 }
                            END   { if (!f) print "gone" }')"
    if [[ "$row" == "gone" ]]; then echo "gone"; return; fi
    local dead="${row%% *}" pid="${row##* }"
    if [[ "$dead" == "1" ]]; then echo "dead"; return; fi
    local bin
    bin="$(tmux show-option -p -qv -t "$pane" "@${OPT_PREFIX}_bin" 2>/dev/null || true)"
    if agent_running_under "$pid" "$bin"; then echo "alive"; else echo "shell"; fi
}

# Find THIS Claude session's agent pane for a topic anywhere on the server
# (matched by the @<opt>_claude6 + @<opt>_topic markers). Server-wide
# (`list-panes -a`) so reuse survives Claude moving the pane to another window.
# The claude6 marker is unique per Claude session and is NOT inherited by
# splits, so there is no false-match risk. Legacy panes without a topic option
# are treated as topic "main".
# NOTE on parsing: IFS=$'\t' treats tab as IFS whitespace, so consecutive tabs
# COLLAPSE and empty fields would shift. Every possibly-empty field is made
# non-empty at the source via tmux conditionals ('-' sentinel / 'main' default).
# Prints "<pane_id>\t<state>" (state = alive|shell|dead, see pane_agent_state)
# for the first match and returns 0; else 1.
find_agent_pane() {
    local my_token="$1" want_topic="${2:-main}"
    local fmt
    fmt="#{pane_id}"$'\t'"#{?@${OPT_PREFIX}_claude6,#{@${OPT_PREFIX}_claude6},-}"$'\t'"#{?@${OPT_PREFIX}_topic,#{@${OPT_PREFIX}_topic},main}"$'\t'"#{pane_dead}"$'\t'"#{pane_pid}"$'\t'"#{?@${OPT_PREFIX}_bin,#{@${OPT_PREFIX}_bin},-}"
    local pid mark topic dead ppid bin state
    while IFS=$'\t' read -r pid mark topic dead ppid bin; do
        [[ "$mark" == "$my_token" ]] || continue
        [[ "$topic" == "$want_topic" ]] || continue
        state="dead"
        if [[ "${dead:-0}" != "1" ]]; then
            if agent_running_under "$ppid" "$bin"; then state="alive"; else state="shell"; fi
        fi
        printf '%s\t%s\n' "$pid" "$state"
        return 0
    done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)
    return 1
}

# Split an agent pane, finalize its options (all guarded — the pane may already
# be gone if the agent exited instantly), and echo the new pane id. Returns 1 if
# the split itself failed.
# Args: ref_pane orient size cwd sandbox my_token topic  [agent argv...]
_split_agent_pane() {
    local ref_pane="$1" orient="$2" size="$3" cwd="$4" sandbox="$5" my_token="$6" topic="$7"
    shift 7
    local title="$WIN_PREFIX-$my_token"
    [[ "$topic" != "main" ]] && title="$WIN_PREFIX-$topic-$my_token"
    local new_pane
    new_pane="$(tmux split-window -t "$ref_pane" "$orient" -l "${size}%" -d -c "$cwd" \
        -P -F '#{pane_id}' "$(compose_launch_cmd "$@")" 2>/dev/null)" || return 1
    [[ -z "$new_pane" ]] && return 1
    tmux set-option -p -t "$new_pane" remain-on-exit "$REMAIN_ON_EXIT" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_claude6" "$my_token" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_topic" "$topic" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_cwd" "$cwd" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_created" "$(date '+%Y-%m-%dT%H:%M:%S%z')" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_sandbox" "$sandbox" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_model" "$AGENT_MODEL" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_effort" "$AGENT_EFFORT" 2>/dev/null || true
    tmux set-option -p -t "$new_pane" "@${OPT_PREFIX}_bin" "$AGENT_BIN" 2>/dev/null || true
    tmux select-pane -t "$new_pane" -T "$title" 2>/dev/null || true
    printf '%s' "$new_pane"
}

cmd_pane() {
    # Spawn / locate / reuse an agent instance as a PANE in the CURRENT Claude
    # window (the window holding Claude Code's own pane). This is the default
    # when running inside tmux; it returns exit 3 (with a hint) when not inside
    # tmux so the skill can fall back to `bind` (dedicated-window mode).
    # --topic (default "main" = the primary pane) resolves/reuses/spawns an
    # EXTRA topic-named pane in the same window, with identical semantics
    # applied per-topic.
    local cwd="$PWD"
    local sandbox="$SANDBOX_DEFAULT"
    local approval="$APPROVAL_DEFAULT"
    local want_sandbox=""
    local orient="-h"          # horizontal split (agent to the right)
    local size="45"            # percent of the reference pane
    local topic="main"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cwd) cwd="$2"; shift 2 ;;
            --topic) topic="$2"; shift 2 ;;
            --full-auto) sandbox="workspace-write"; want_sandbox="workspace-write"; shift ;;
            --read-only) sandbox="read-only"; want_sandbox="read-only"; shift ;;
            --vertical) orient="-v"; shift ;;
            --horizontal) orient="-h"; shift ;;
            --size) size="$2"; shift 2 ;;
            -*) echo "$LABEL pane: unknown flag '$1'" >&2; return 2 ;;
            *) echo "$LABEL pane: unexpected arg '$1'" >&2; return 2 ;;
        esac
    done

    if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size < 10 || size > 90 )); then
        echo "$LABEL pane: --size must be an integer 10-90 (got '$size')" >&2
        return 2
    fi
    validate_topic "$topic" || return 2

    ensure_tmux_or_die

    local ref_pane window my_token
    ref_pane="$(current_ref_pane)"
    if [[ -z "$ref_pane" ]]; then
        echo "$LABEL pane: not inside tmux (TMUX_PANE unset). Use 'bind' for dedicated-window mode." >&2
        return 3
    fi
    window="$(pane_window_target "$ref_pane" 2>/dev/null || true)"
    if [[ -z "$window" ]]; then
        echo "$LABEL pane: cannot resolve current window from pane '$ref_pane'. Use 'bind'." >&2
        return 3
    fi
    my_token="$(compute_claude6)"
    local title="$WIN_PREFIX-$my_token"
    [[ "$topic" != "main" ]] && title="$WIN_PREFIX-$topic-$my_token"
    local topic_flag=""
    [[ "$topic" != "main" ]] && topic_flag=" --topic $topic"

    # Locate this Claude's existing agent pane for this topic anywhere on the
    # server.
    local match pane pstate
    if match="$(find_agent_pane "$my_token" "$topic")"; then
        pane="${match%%$'\t'*}"
        pstate="${match##*$'\t'}"
        if [[ "$pstate" == "alive" || "$pstate" == "shell" ]]; then
            # Keep the agent in Claude's CURRENT window. If the pane (live agent
            # OR kept shell) is in a different window, relocate it here
            # (join-pane) so it always sits beside Claude and is never
            # duplicated. If the relocate fails, drop the stray and spawn fresh
            # below.
            local pane_win
            pane_win="$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}' 2>/dev/null || true)"
            if [[ -n "$pane_win" && "$pane_win" != "$window" ]]; then
                if tmux join-pane -h -s "$pane" -t "$ref_pane" 2>/dev/null; then
                    tmux select-pane -t "$pane" -T "$title" 2>/dev/null || true
                else
                    tmux kill-pane -t "$pane" 2>/dev/null || true
                    pane=""
                fi
            fi
            # Final state re-check closes a TOCTOU race: the pane found above
            # could die/vanish (or the agent could exit) before we return it.
            [[ -n "$pane" ]] && pstate="$(pane_agent_state "$pane")"
            if [[ -n "$pane" && "$pstate" == "alive" ]]; then
                # Reuse; warn (don't fail) on a sandbox mismatch.
                local existing
                existing="$(tmux show-option -p -qv -t "$pane" "@${OPT_PREFIX}_sandbox" 2>/dev/null || true)"
                if [[ -n "$want_sandbox" && -n "$existing" && "$want_sandbox" != "$existing" ]]; then
                    echo "$LABEL pane: $KIND pane '$pane' is '$existing'; requested '$want_sandbox'. Kill and re-create to switch ($LABEL.sh kill $pane && $LABEL.sh pane --$want_sandbox$topic_flag)." >&2
                fi
                # Same for an explicit model/effort override: it cannot apply to
                # an already-running agent, so warn instead of silently ignoring.
                local existing_model existing_effort
                existing_model="$(tmux show-option -p -qv -t "$pane" "@${OPT_PREFIX}_model" 2>/dev/null || true)"
                existing_effort="$(tmux show-option -p -qv -t "$pane" "@${OPT_PREFIX}_effort" 2>/dev/null || true)"
                if { [[ -n "${CC_AGENT_MODEL+x}" && -n "$existing_model" && "$AGENT_MODEL" != "$existing_model" ]]; } \
                    || { [[ -n "${CC_AGENT_EFFORT+x}" && -n "$existing_effort" && "$AGENT_EFFORT" != "$existing_effort" ]]; }; then
                    echo "$LABEL pane: reusing pane '$pane' (model '${existing_model:-?}', effort '${existing_effort:-?}'); ${ENV_PREFIX}_MODEL/${ENV_PREFIX}_EFFORT do NOT apply to a reused pane. Kill and re-create to switch ($LABEL.sh kill $pane && $LABEL.sh pane$topic_flag)." >&2
                fi
                echo "$pane"
                if [[ "$topic" == "main" ]]; then
                    echo "Reusing $KIND pane $pane (in your current window)."
                else
                    echo "Reusing $KIND pane $pane for topic '$topic' (in your current window)."
                fi
                return 0
            fi
            if [[ -n "$pane" && "$pstate" == "shell" ]]; then
                # Keep-shell pane: the agent exited but the pane sits at an
                # interactive shell. Relaunch the agent inside it — same pane
                # id, geometry and scrollback preserved. A relaunch is a fresh
                # start, so the requested sandbox/model/effort apply now.
                if relaunch_agent_in "$pane" "$cwd" "$sandbox" "$approval"; then
                    tmux set-option -p -t "$pane" "@${OPT_PREFIX}_cwd" "$cwd" 2>/dev/null || true
                    tmux set-option -p -t "$pane" "@${OPT_PREFIX}_sandbox" "$sandbox" 2>/dev/null || true
                    tmux set-option -p -t "$pane" "@${OPT_PREFIX}_model" "$AGENT_MODEL" 2>/dev/null || true
                    tmux set-option -p -t "$pane" "@${OPT_PREFIX}_effort" "$AGENT_EFFORT" 2>/dev/null || true
                    tmux set-option -p -t "$pane" "@${OPT_PREFIX}_bin" "$AGENT_BIN" 2>/dev/null || true
                    tmux select-pane -t "$pane" -T "$title" 2>/dev/null || true
                    echo "$pane"
                    if [[ "$topic" == "main" ]]; then
                        echo "Relaunched $KIND in kept pane $pane (in your current window)."
                    else
                        echo "Relaunched $KIND in kept pane $pane for topic '$topic' (in your current window)."
                    fi
                    return 0
                fi
                # Relaunch failed: drop the pane and spawn fresh below.
                tmux kill-pane -t "$pane" 2>/dev/null || true
            fi
        else
            # Dead pane: remove it and respawn below.
            tmux kill-pane -t "$pane" 2>/dev/null || true
        fi
    fi

    build_agent_cmd "$sandbox" "$approval"

    # Width floor: agent TUIs want >= ~80 cols. If a horizontal split would
    # leave the agent too narrow, fall back to a vertical (full-width) split.
    if [[ "$orient" == "-h" ]]; then
        local ref_w
        ref_w="$(tmux display-message -p -t "$ref_pane" '#{pane_width}' 2>/dev/null || echo 0)"
        if (( ref_w > 0 && ref_w * size / 100 < 80 )); then
            orient="-v"
            echo "$LABEL pane: horizontal split would be <80 cols; using a vertical (full-width) split." >&2
        fi
    fi

    # Spawn, then verify the agent survived launch; retry once on immediate
    # exit (transient home-dir / MCP init hiccups happen). Without this, a
    # dead-on-arrival pane id would be returned and driven blindly.
    local new_pane attempt=0
    while (( attempt < 2 )); do
        attempt=$(( attempt + 1 ))
        new_pane="$(_split_agent_pane "$ref_pane" "$orient" "$size" "$cwd" "$sandbox" "$my_token" "$topic" "${AGENT_CMD[@]}")" \
            || { echo "$LABEL pane: split-window failed (window too small? try --vertical or 'bind')" >&2; return 1; }
        sleep 0.4
        if [[ "$(pane_agent_state "$new_pane")" == "alive" ]]; then
            echo "$new_pane"
            if [[ "$topic" == "main" ]]; then
                echo "$AGENT_TITLE pane $new_pane in window $window (visible next to Claude)."
            else
                echo "$AGENT_TITLE pane $new_pane for topic '$topic' in window $window (visible next to Claude)."
            fi
            return 0
        fi
        echo "$LABEL pane: $KIND exited immediately in $new_pane (attempt $attempt):" >&2
        tmux capture-pane -t "$new_pane" -p -S -20 2>/dev/null | sed 's/^/  | /' >&2 || true
        tmux kill-pane -t "$new_pane" 2>/dev/null || true
        sleep 0.5
    done
    echo "$LABEL pane: $KIND exited immediately twice; aborting. Re-run, or use 'bind'." >&2
    return 4
}

cmd_panes() {
    # Read-only detection: list agent PANES server-wide (matched by the
    # @<opt>_claude6 marker), filtered to the current Claude session's
    # claude6 unless --all. Prints one TSV line per pane:
    #   <pane_id>\t<topic>\t<state>\t<session:window_index>\t<cwd>
    # (state = alive|shell|dead). Exits 0 if anything was printed, 1 otherwise.
    # Never creates the shared session (ensure_tmux_or_die only).
    local all=0 json=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) all=1; shift ;;
            --json) json=1; shift ;;
            *) echo "$LABEL panes: unknown arg '$1'" >&2; return 2 ;;
        esac
    done

    ensure_tmux_or_die
    local my_token=""
    (( all )) || my_token="$(compute_claude6)"

    # Every possibly-empty field is made non-empty at the source via tmux
    # conditionals so tab-IFS parsing never collapses/shifts fields (see
    # find_agent_pane). Rows whose marker is the '-' sentinel are not agent
    # panes and are skipped.
    local fmt
    fmt="#{pane_id}"$'\t'"#{?@${OPT_PREFIX}_claude6,#{@${OPT_PREFIX}_claude6},-}"$'\t'"#{?@${OPT_PREFIX}_topic,#{@${OPT_PREFIX}_topic},main}"$'\t'"#{pane_dead}"$'\t'"#{pane_pid}"$'\t'"#{?@${OPT_PREFIX}_bin,#{@${OPT_PREFIX}_bin},-}"$'\t'"#{session_name}:#{window_index}"$'\t'"#{?@${OPT_PREFIX}_cwd,#{@${OPT_PREFIX}_cwd},-}"
    local found=0 rows=""
    local pid mark topic dead ppid bin win cwd state
    while IFS=$'\t' read -r pid mark topic dead ppid bin win cwd; do
        [[ "$mark" == "-" ]] && continue
        [[ -n "$my_token" && "$mark" != "$my_token" ]] && continue
        state="dead"
        if [[ "$dead" != "1" ]]; then
            if agent_running_under "$ppid" "$bin"; then state="alive"; else state="shell"; fi
        fi
        if (( json )); then
            rows+="$(printf '{"pane_id":"%s","topic":"%s","state":"%s","window":"%s","cwd":"%s"}' \
                "$(json_escape "$pid")" "$(json_escape "$topic")" "$(json_escape "$state")" \
                "$(json_escape "$win")" "$(json_escape "$cwd")"),"
        else
            printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$topic" "$state" "$win" "$cwd"
        fi
        found=$(( found + 1 ))
    done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)

    (( json )) && printf '[%s]\n' "${rows%,}"
    (( found > 0 ))
}

# Compute the state of a window: alive | shell | dead | unknown.
#   alive — an agent process is running in the window's pane
#   shell — the pane is alive but the agent exited (keep-shell window sitting
#           at an interactive shell; manually usable / relaunchable)
#   dead  — the pane's root process exited (kept by remain-on-exit)
# Determined entirely from tmux/process state (no pane buffer parsing).
window_state() {
    local window="$1"
    if ! window_exists "$window"; then
        echo "unknown"
        return
    fi
    local pane_pid dead
    pane_pid="$(window_pane_pid "$window")"
    [[ -z "$pane_pid" ]] && { echo "dead"; return; }
    dead="$(tmux list-panes -t "$SESSION_NAME:$window" -F '#{pane_dead}' 2>/dev/null | head -n1)"
    if [[ "$dead" == "1" ]] || ! kill -0 "$pane_pid" 2>/dev/null; then
        echo "dead"
        return
    fi
    local bin
    bin="$(tmux show-option -wqv -t "$SESSION_NAME:$window" "@${OPT_PREFIX}_bin" 2>/dev/null || true)"
    if agent_running_under "$pane_pid" "$bin"; then
        echo "alive"
    else
        echo "shell"
    fi
}

cmd_find() {
    # Locate agent windows matching a topic (and optionally a cwd) within the
    # current Claude session's claude6 namespace. Prints one match per line in
    # the form "<window>\t<state>\t<cwd>". Exits 0 if any matches were printed,
    # 1 otherwise.
    local topic=""
    local cwd_filter=""
    local include_dead=0
    local any_session=0
    local json=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cwd) cwd_filter="$2"; shift 2 ;;
            --include-dead) include_dead=1; shift ;;
            --any-session) any_session=1; shift ;;
            --json) json=1; shift ;;
            -*) echo "$LABEL find: unknown flag '$1'" >&2; return 2 ;;
            *) topic="$1"; shift ;;
        esac
    done

    [[ -z "$topic" ]] && { echo "$LABEL find: <topic> required" >&2; return 2; }
    validate_topic "$topic" || return 2

    # Read-only: don't auto-create the shared session (avoids leaving an empty
    # session behind). An absent session simply yields no matches.
    ensure_tmux_or_die
    local my_token=""
    (( any_session )) || my_token="$(compute_claude6)"

    local found=0 rows=""
    while IFS= read -r win; do
        [[ "$win" == "_placeholder" ]] && continue
        [[ "$win" != "$WIN_PREFIX"-* ]] && continue
        # Filter by current claude6 unless --any-session. Accept both extra
        # windows (<kind>-<topic>-<claude6>-<rand2>) and the bound window
        # (<kind>-<claude6>).
        if [[ -n "$my_token" && "$win" != *"-$my_token-"* && "$win" != "$WIN_PREFIX-$my_token" ]]; then
            continue
        fi
        local win_topic win_cwd state
        win_topic="$(tmux show-option -wqv -t "$SESSION_NAME:$win" "@${OPT_PREFIX}_topic" 2>/dev/null)"
        [[ "$win_topic" != "$topic" ]] && continue
        if [[ -n "$cwd_filter" ]]; then
            win_cwd="$(tmux show-option -wqv -t "$SESSION_NAME:$win" "@${OPT_PREFIX}_cwd" 2>/dev/null)"
            [[ "$win_cwd" != "$cwd_filter" ]] && continue
        else
            win_cwd="$(tmux show-option -wqv -t "$SESSION_NAME:$win" "@${OPT_PREFIX}_cwd" 2>/dev/null)"
        fi
        state="$(window_state "$win")"
        if (( ! include_dead )) && [[ "$state" != "alive" ]]; then
            continue
        fi
        if (( json )); then
            rows+="$(printf '{"window":"%s","state":"%s","cwd":"%s"}' \
                "$(json_escape "$win")" "$(json_escape "$state")" "$(json_escape "${win_cwd:--}")"),"
        else
            printf '%s\t%s\t%s\n' "$win" "$state" "${win_cwd:--}"
        fi
        found=$(( found + 1 ))
    done < <(tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null)

    (( json )) && printf '[%s]\n' "${rows%,}"
    (( found > 0 ))
}

cmd_ls() {
    local mine_only=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mine) mine_only=1; shift ;;
            *) echo "$LABEL ls: unknown arg '$1'" >&2; return 2 ;;
        esac
    done

    # Read-only: don't auto-create the shared session; absent = no rows.
    ensure_tmux_or_die
    local my_token=""
    if (( mine_only )); then
        my_token="$(compute_claude6)"
    fi

    printf '%-32s %-12s %-7s %-30s %s\n' "WINDOW" "TOPIC" "STATE" "CWD" "CREATED"
    while IFS= read -r win; do
        # Skip the internal placeholder window.
        [[ "$win" == "_placeholder" ]] && continue
        # Only windows for this kind.
        [[ "$win" != "$WIN_PREFIX"-* ]] && continue
        if (( mine_only )) && [[ "$win" != *"-$my_token-"* && "$win" != "$WIN_PREFIX-$my_token" ]]; then
            continue
        fi
        local topic cwd created state
        topic="$(tmux show-option -wqv -t "$SESSION_NAME:$win" "@${OPT_PREFIX}_topic" 2>/dev/null)"
        cwd="$(tmux show-option -wqv -t "$SESSION_NAME:$win" "@${OPT_PREFIX}_cwd" 2>/dev/null)"
        created="$(tmux show-option -wqv -t "$SESSION_NAME:$win" "@${OPT_PREFIX}_created" 2>/dev/null)"
        state="$(window_state "$win")"
        printf '%-32s %-12s %-7s %-30s %s\n' "$win" "${topic:--}" "$state" "${cwd:--}" "${created:--}"
    done < <(tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null)
}

cmd_attach() {
    local window="$1"
    [[ -z "$window" ]] && { echo "$LABEL attach: window required" >&2; return 2; }
    ensure_tmux_or_die
    window_exists "$window" || { echo "$LABEL attach: window '$window' not found" >&2; return 6; }
    echo "tmux attach -t $SESSION_NAME \\; select-window -t $window"
}

cmd_rename() {
    local old="$1"
    local new_topic="$2"
    [[ -z "$old" || -z "$new_topic" ]] && {
        echo "$LABEL rename: old-window and new-topic required" >&2; return 2; }
    validate_topic "$new_topic" || return 2
    ensure_tmux_or_die
    window_exists "$old" || { echo "$LABEL rename: window '$old' not found" >&2; return 6; }

    # Pattern: <kind>-<topic>-<claude6>-<rand2>
    # Preserve the trailing '-<claude6>-<rand2>'.
    local pat="^${WIN_PREFIX}-[a-z0-9-]+-([a-z0-9]{6})-([a-z0-9]{2})$"
    if [[ ! "$old" =~ $pat ]]; then
        echo "$LABEL rename: window '$old' does not follow naming convention" >&2
        return 2
    fi
    local claude6="${BASH_REMATCH[1]}"
    local rand2="${BASH_REMATCH[2]}"
    local new_name="$WIN_PREFIX-${new_topic}-${claude6}-${rand2}"

    tmux rename-window -t "$SESSION_NAME:$old" "$new_name"
    tmux set-option -w -t "$SESSION_NAME:$new_name" "@${OPT_PREFIX}_topic" "$new_topic"
    echo "$new_name"
}

cmd_kill() {
    if [[ "${1:-}" == "--orphaned" ]]; then
        ensure_tmux_or_die
        local removed=0
        # Dead agent windows in the shared session.
        while IFS= read -r win; do
            [[ "$win" == "_placeholder" ]] && continue
            [[ "$win" != "$WIN_PREFIX"-* ]] && continue
            if [[ "$(window_state "$win")" == "dead" ]]; then
                tmux kill-window -t "$SESSION_NAME:$win" 2>/dev/null || true
                removed=$(( removed + 1 ))
            fi
        done < <(tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null)
        # Dead agent PANES anywhere on the server (any Claude session). The
        # marker field is made non-empty via a tmux conditional ('-' sentinel
        # = unmarked) so tab-IFS parsing never collapses/shifts fields.
        local fmt
        fmt="#{pane_id}"$'\t'"#{?@${OPT_PREFIX}_claude6,#{@${OPT_PREFIX}_claude6},-}"$'\t'"#{pane_dead}"
        local pid mark dead
        while IFS=$'\t' read -r pid mark dead; do
            [[ "$mark" != "-" && "$dead" == "1" ]] || continue
            tmux kill-pane -t "$pid" 2>/dev/null || true
            removed=$(( removed + 1 ))
        done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)
        echo "removed $removed orphan window(s)/pane(s)"
        return 0
    fi

    if [[ "${1:-}" == "--mine" ]]; then
        ensure_tmux_or_die
        local my_token removed=0
        my_token="$(compute_claude6)"
        # This Claude's agent windows.
        while IFS= read -r win; do
            [[ "$win" == "_placeholder" ]] && continue
            [[ "$win" != "$WIN_PREFIX"-* ]] && continue
            [[ "$win" != *"-$my_token-"* && "$win" != "$WIN_PREFIX-$my_token" ]] && continue
            tmux kill-window -t "$SESSION_NAME:$win" 2>/dev/null || true
            removed=$(( removed + 1 ))
        done < <(tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null)
        # This Claude's agent PANES anywhere on the server (alive or dead,
        # ALL topics). The marker field is made non-empty via a tmux
        # conditional ('-' sentinel = unmarked) so tab-IFS parsing never
        # collapses/shifts fields.
        local fmt
        fmt="#{pane_id}"$'\t'"#{?@${OPT_PREFIX}_claude6,#{@${OPT_PREFIX}_claude6},-}"
        local pid mark
        while IFS=$'\t' read -r pid mark; do
            [[ "$mark" == "$my_token" ]] || continue
            tmux kill-pane -t "$pid" 2>/dev/null || true
            removed=$(( removed + 1 ))
        done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)
        echo "removed $removed window(s)/pane(s) for claude6=$my_token"
        return 0
    fi

    local window="$1"
    [[ -z "$window" ]] && { echo "$LABEL kill: window, pane-id, --mine, or --orphaned required" >&2; return 2; }
    # Pane-id target (e.g. %53): kill the agent pane directly (pane mode).
    if [[ "$window" == %* ]]; then
        ensure_tmux_or_die
        tmux kill-pane -t "$window" 2>/dev/null \
            || { echo "$LABEL kill: pane '$window' not found" >&2; return 6; }
        return 0
    fi
    ensure_tmux_or_die
    window_exists "$window" || { echo "$LABEL kill: window '$window' not found" >&2; return 6; }
    tmux kill-window -t "$SESSION_NAME:$window"
}

# ---------- Driving verbs (send → wait → read → cancel) ----------

# Normalize a drive target: %pane-id and session:window pass through; a bare
# window name gets the shared session prefixed.
norm_target() {
    local t="$1"
    if [[ "$t" == %* || "$t" == *:* ]]; then printf '%s' "$t"; else printf '%s:%s' "$SESSION_NAME" "$t"; fi
}

# State of a drive target regardless of placement: pane targets via
# pane_agent_state, window targets via window_state (name part only).
target_state() {
    local t="$1"
    if [[ "$t" == %* ]]; then pane_agent_state "$t"; else window_state "${t##*:}"; fi
}

# Resolve the target for a driving verb: --target wins; otherwise THIS Claude
# session's pane for the topic (default main), found server-wide. Prints the
# normalized target; returns 1 when nothing was found.
resolve_drive_target() {
    local explicit="${1:-}" topic="${2:-main}"
    if [[ -n "$explicit" ]]; then
        norm_target "$explicit"
        return 0
    fi
    local match
    if match="$(find_agent_pane "$(compute_claude6)" "$topic")"; then
        printf '%s' "${match%%$'\t'*}"
        return 0
    fi
    return 1
}

capture_full() { tmux capture-pane -t "$1" -p -S - 2>/dev/null; }

buf_hash() { printf '%s' "$1" | cksum; }

# Escape a string for inclusion in a JSON double-quoted value.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Shared settled-state wait. Args: target timeout activity_timeout.
# Uses the @<opt>_basehash recorded by `prompt` for the activity phase (skipped
# when absent — a standalone `wait` just asks "is it idle now?"), then requires
# the buffer stable over consecutive polls AND the idle regex at the bottom of
# the pane. Exit: 0 idle, 5 timeout, 8 stalled (no activity), 9 agent exited.
wait_impl() {
    local target="$1" timeout="$2" activity_timeout="$3"
    local basehash buf state
    basehash="$(tmux show-option -p -qv -t "$target" "@${OPT_PREFIX}_basehash" 2>/dev/null || true)"

    local deadline
    if [[ -n "$basehash" ]]; then
        # Activity phase: the pane must first CHANGE from the prompt-time
        # baseline, else the pre-send idle line reads as a false "done".
        deadline=$(( $(date +%s) + activity_timeout ))
        while :; do
            state="$(target_state "$target")"
            case "$state" in
                gone|unknown) echo "$LABEL wait: target '$target' not found" >&2; return 6 ;;
                shell|dead) echo "$LABEL wait: $KIND exited (state $state)" >&2; return 9 ;;
            esac
            buf="$(capture_full "$target")"
            [[ "$(buf_hash "$buf")" != "$basehash" ]] && break
            if (( $(date +%s) >= deadline )); then
                echo "$LABEL wait: stalled — no activity within ${activity_timeout}s of the prompt" >&2
                return 8
            fi
            sleep 0.5
        done
    fi

    # Stability + idle phase. Matched against only the BOTTOM of the pane so a
    # response echoing the idle marker mid-buffer can't trigger a false idle.
    local prev="" stable=0 need=2
    [[ -z "$IDLE_REGEX" ]] && need=4
    deadline=$(( $(date +%s) + timeout ))
    while (( $(date +%s) < deadline )); do
        state="$(target_state "$target")"
        case "$state" in
            gone|unknown) echo "$LABEL wait: target '$target' not found" >&2; return 6 ;;
            shell|dead) echo "$LABEL wait: $KIND exited (state $state)" >&2; return 9 ;;
        esac
        buf="$(tmux capture-pane -t "$target" -p -S -200 2>/dev/null || true)"
        if [[ -n "$BUSY_REGEX" ]] && printf '%s\n' "$buf" | tail -15 | grep -qE "$BUSY_REGEX"; then
            # Busy marker on screen: the turn is still running even if the
            # buffer looks momentarily stable.
            stable=0
        elif [[ -n "$buf" && "$buf" == "$prev" ]]; then
            if [[ -z "$IDLE_REGEX" ]] || printf '%s\n' "$buf" | tail -3 | grep -qE "$IDLE_REGEX"; then
                stable=$(( stable + 1 ))
                if (( stable >= need )); then
                    tmux set-option -p -u -t "$target" "@${OPT_PREFIX}_basehash" 2>/dev/null || true
                    echo "idle"
                    return 0
                fi
            else
                stable=0
            fi
        else
            stable=0
        fi
        prev="$buf"
        sleep 0.5
    done
    echo "$LABEL wait: timeout after ${timeout}s (agent still busy or idle marker never matched)" >&2
    return 5
}

cmd_prompt() {
    # Type a prompt into the agent pane: literal send-keys, short pause, then
    # Enter as its own key event. Records a baseline (line count + hash) as
    # pane options so `read --delta` and `wait` anchor to this prompt. Long or
    # multi-line text goes via a tmp file the agent is pointed at.
    local target="" topic="main" file="" do_wait=0 timeout=600 activity_timeout=30
    local -a words=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --topic) topic="$2"; shift 2 ;;
            --file) file="$2"; shift 2 ;;
            --wait) do_wait=1; shift ;;
            --timeout) timeout="$2"; shift 2 ;;
            --activity-timeout) activity_timeout="$2"; shift 2 ;;
            --) shift; words+=( "$@" ); break ;;
            -*) echo "$LABEL prompt: unknown flag '$1'" >&2; return 2 ;;
            *) words+=( "$1" ); shift ;;
        esac
    done
    if [[ ! "$timeout" =~ ^[0-9]+$ || ! "$activity_timeout" =~ ^[0-9]+$ ]]; then
        echo "$LABEL prompt: --timeout/--activity-timeout must be integers (seconds)" >&2
        return 2
    fi
    local text="${words[*]:-}"
    if [[ -n "$file" && -n "$text" ]] || [[ -z "$file" && -z "$text" ]]; then
        echo "$LABEL prompt: exactly one of <text> or --file PATH required" >&2
        return 2
    fi
    if [[ -n "$file" && ! -f "$file" ]]; then
        echo "$LABEL prompt: file '$file' not found" >&2
        return 2
    fi
    ensure_tmux_or_die

    local t
    t="$(resolve_drive_target "$target" "$topic")" \
        || { echo "$LABEL prompt: no $KIND pane for topic '$topic' — run 'pane' first" >&2; return 6; }
    local state
    state="$(target_state "$t")"
    case "$state" in
        alive) : ;;
        gone|unknown) echo "$LABEL prompt: target '$t' not found" >&2; return 6 ;;
        *) echo "$LABEL prompt: target '$t' is not alive (state $state) — run 'pane'/'bind' to relaunch" >&2; return 9 ;;
    esac

    local msg
    if [[ -n "$file" ]]; then
        msg="Read @$file and follow its instructions."
    elif [[ "$text" == *$'\n'* || "${#text}" -gt 500 ]]; then
        # Multi-line / long prompt: hand it over via a tmp file to avoid
        # quoting and TUI paste issues.
        local tmpf
        tmpf="$(mktemp "${TMPDIR:-/tmp}/cc-${KIND}-prompt.XXXXXX")" || return 1
        printf '%s\n' "$text" > "$tmpf"
        msg="Read @$tmpf and follow its instructions."
    else
        msg="$text"
    fi

    # Baseline BEFORE sending: anchor for wait's activity phase and read's
    # delta. The full text also goes to a baseline file — TUIs that pad/redraw
    # the whole screen (Claude Code) never grow the line count within one
    # screen, so `read --delta` falls back to a first-divergence diff against
    # this file when the line-count tail comes up empty.
    local buf hash lines basefile
    buf="$(capture_full "$t")"
    hash="$(buf_hash "$buf")"
    lines="$(printf '%s\n' "$buf" | wc -l | tr -d ' ')"
    basefile="${TMPDIR:-/tmp}/cc-${KIND}-base-${t//[%:.]/_}"
    printf '%s\n' "$buf" > "$basefile" 2>/dev/null || basefile=""
    tmux set-option -p -t "$t" "@${OPT_PREFIX}_mark" "$lines" 2>/dev/null || true
    tmux set-option -p -t "$t" "@${OPT_PREFIX}_basehash" "$hash" 2>/dev/null || true
    [[ -n "$basefile" ]] && tmux set-option -p -t "$t" "@${OPT_PREFIX}_basefile" "$basefile" 2>/dev/null || true

    tmux send-keys -t "$t" -l -- "$msg" 2>/dev/null \
        || { echo "$LABEL prompt: send-keys to '$t' failed" >&2; return 6; }
    sleep 0.3
    tmux send-keys -t "$t" Enter 2>/dev/null || { echo "$LABEL prompt: send-keys to '$t' failed" >&2; return 6; }

    if (( do_wait )); then
        wait_impl "$t" "$timeout" "$activity_timeout"
        return
    fi
    echo "sent to $t"
}

cmd_wait() {
    # Block until the agent's turn settles (idle marker + stable pane).
    # Standalone `wait` (no prior prompt baseline) just answers "is it idle
    # now?" — the activity phase only runs against a `prompt`-recorded baseline.
    local target="" topic="main" timeout=600 activity_timeout=30
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --topic) topic="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --activity-timeout) activity_timeout="$2"; shift 2 ;;
            *) echo "$LABEL wait: unknown arg '$1'" >&2; return 2 ;;
        esac
    done
    if [[ ! "$timeout" =~ ^[0-9]+$ || ! "$activity_timeout" =~ ^[0-9]+$ ]]; then
        echo "$LABEL wait: --timeout/--activity-timeout must be integers (seconds)" >&2
        return 2
    fi
    ensure_tmux_or_die
    local t
    t="$(resolve_drive_target "$target" "$topic")" \
        || { echo "$LABEL wait: no $KIND pane for topic '$topic'" >&2; return 6; }
    wait_impl "$t" "$timeout" "$activity_timeout"
}

cmd_read() {
    # Read the pane. --delta prints only what the agent emitted since the last
    # `prompt` (line-count tail against the recorded baseline — robust on
    # redraw-heavy TUIs); the default prints the last --lines of scrollback.
    # Works on shell/dead panes too (their scrollback is still readable).
    local target="" topic="main" delta=0 lines=200
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --topic) topic="$2"; shift 2 ;;
            --delta) delta=1; shift ;;
            --lines) lines="$2"; shift 2 ;;
            *) echo "$LABEL read: unknown arg '$1'" >&2; return 2 ;;
        esac
    done
    if [[ ! "$lines" =~ ^[0-9]+$ ]]; then
        echo "$LABEL read: --lines must be an integer" >&2
        return 2
    fi
    ensure_tmux_or_die
    local t
    t="$(resolve_drive_target "$target" "$topic")" \
        || { echo "$LABEL read: no $KIND pane for topic '$topic'" >&2; return 6; }
    local state
    state="$(target_state "$t")"
    if [[ "$state" == "gone" || "$state" == "unknown" ]]; then
        echo "$LABEL read: target '$t' not found" >&2
        return 6
    fi

    if (( delta )); then
        local buf mark total basefile
        buf="$(capture_full "$t")"
        mark="$(tmux show-option -p -qv -t "$t" "@${OPT_PREFIX}_mark" 2>/dev/null || true)"
        [[ "$mark" =~ ^[0-9]+$ ]] || mark=0
        total="$(printf '%s\n' "$buf" | wc -l | tr -d ' ')"
        if (( total > mark )); then
            # Growing-buffer TUI (codex, plain CLIs): everything after the
            # prompt-time line count is new output.
            printf '%s\n' "$buf" | tail -n "$(( total - mark ))"
            return 0
        fi
        # Screen-padding TUI (Claude Code): the buffer redraws in place, so
        # print from the first line that DIFFERS from the prompt-time
        # baseline, trailing blank lines trimmed.
        basefile="$(tmux show-option -p -qv -t "$t" "@${OPT_PREFIX}_basefile" 2>/dev/null || true)"
        if [[ -n "$basefile" && -r "$basefile" ]]; then
            printf '%s\n' "$buf" \
                | awk 'NR==FNR { base[NR]=$0; next }
                       started { print; next }
                       !(FNR in base) || $0 != base[FNR] { started=1; print }' \
                    "$basefile" - \
                | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
        fi
        return 0
    fi
    tmux capture-pane -t "$t" -p -S "-$lines" 2>/dev/null
}

cmd_cancel() {
    # Cancel the in-flight turn (agent TUIs bind Esc to cancel), then the
    # caller re-runs `wait` before sending anything else.
    local target="" topic="main"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --topic) topic="$2"; shift 2 ;;
            *) echo "$LABEL cancel: unknown arg '$1'" >&2; return 2 ;;
        esac
    done
    ensure_tmux_or_die
    local t
    t="$(resolve_drive_target "$target" "$topic")" \
        || { echo "$LABEL cancel: no $KIND pane for topic '$topic'" >&2; return 6; }
    tmux send-keys -t "$t" Escape 2>/dev/null \
        || { echo "$LABEL cancel: target '$t' not found" >&2; return 6; }
    echo "cancel sent to $t"
}

# ---------- Usage ----------
usage() {
    cat <<EOF
Usage: agent-tmux.sh --kind <kind> <subcommand> [args...]

Generic lifecycle engine for driving an interactive agent CLI in tmux.
Kind-specific settings (binary, model/effort defaults, launch flags, resume
hint) load from profiles/<kind>.sh. Normally invoked through a kind wrapper
(e.g. codex-tmux.sh), which maps its legacy environment variables and adds
kind-only verbs.

Subcommands (identical semantics to the codex wrapper's documentation):
  pane [--topic SLUG] [--cwd DIR] [--full-auto|--read-only]
       [--horizontal|--vertical] [--size PCT]
  panes [--all] [--json]
  bind [--cwd DIR] [--full-auto|--read-only]
  new <topic> [--cwd DIR] [--full-auto|--read-only]
  prompt [--target T|--topic SLUG] [--file PATH] [--wait] [--timeout SECS]
         [--activity-timeout SECS] [--] <text...>
      Type a prompt into the agent pane (literal send-keys, pause, Enter).
      Long/multi-line text goes via a tmp file automatically. Records the
      baseline that 'wait' and 'read --delta' anchor to. --wait chains
      straight into 'wait'. Default target: this session's main-topic pane.
  wait [--target T|--topic SLUG] [--timeout SECS] [--activity-timeout SECS]
      Block until the turn settles: after a 'prompt', first requires pane
      activity (else exit 8, stalled), then stability + the profile's idle
      regex at the pane bottom. Standalone = "is it idle now?". Prints
      "idle" and exits 0; 5 = timeout, 6 = no target, 9 = agent exited.
  read [--target T|--topic SLUG] [--delta] [--lines N]
      Print the pane. --delta = only output since the last 'prompt'
      (works on kept-shell/dead panes too); default = last N (200) lines.
  cancel [--target T|--topic SLUG]
      Send Escape to cancel the in-flight turn; re-run 'wait' after.
  ls [--mine]
  find <topic> [--cwd DIR] [--include-dead] [--any-session] [--json]
  attach <window>
  rename <old-window> <new-topic>
  kill <window> | kill <%pane-id> | kill --mine | kill --orphaned

Environment (generic; kind wrappers map their legacy names onto these):
  CC_AGENT_KIND           kind to drive (or pass --kind)
  CC_AGENT_SESSION_NAME   (default: cc-<kind>)
  CC_AGENT_BIN            (default: profile's binary)
  CC_AGENT_MODEL          (default: profile's model)
  CC_AGENT_EFFORT         (default: profile's effort)
  CC_AGENT_KEEP_SHELL     (default: 1)
  CC_AGENT_EXIT_SHELL     (default: \$SHELL)
  CC_AGENT_REMAIN_ON_EXIT (default: failed)
  CC_AGENT_REF_PANE       (default: \$TMUX_PANE)
  CC_AGENT_IDLE_REGEX     (default: profile's idle regex; matched against the
                          bottom 3 pane lines by 'wait'. Empty = stability-only)
  CC_AGENT_BUSY_REGEX     (default: profile's busy regex; while it matches the
                          bottom 15 lines, 'wait' treats the turn as running)
EOF
}

# ---------- Dispatch ----------
main() {
    # Peel --kind (must precede the subcommand); CC_AGENT_KIND is the fallback.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kind) KIND="${2:-}"; shift 2 ;;
            --kind=*) KIND="${1#--kind=}"; shift ;;
            *) break ;;
        esac
    done
    KIND="${KIND:-${CC_AGENT_KIND:-}}"
    if [[ -z "$KIND" ]]; then
        echo "agent-tmux: --kind <kind> (or CC_AGENT_KIND) required" >&2
        exit 2
    fi
    if [[ ! "$KIND" =~ ^[a-z0-9]+$ ]]; then
        echo "agent-tmux: invalid kind '$KIND' (must be [a-z0-9]+)" >&2
        exit 2
    fi
    local profile="$SCRIPT_DIR/profiles/$KIND.sh"
    if [[ ! -f "$profile" ]]; then
        echo "agent-tmux: no profile for kind '$KIND' ($profile not found)" >&2
        exit 2
    fi
    # shellcheck source=/dev/null
    source "$profile"
    init_globals

    if [[ $# -eq 0 ]]; then
        usage >&2
        exit 2
    fi

    # Note: named `subcmd` (not `cmd`) to keep shellcheck happy about scopes.
    local subcmd="$1"
    shift || true

    case "$subcmd" in
        -h|--help|help)
            usage
            ;;
        pane) cmd_pane "$@" ;;
        panes) cmd_panes "$@" ;;
        bind) cmd_bind "$@" ;;
        new) cmd_new "$@" ;;
        prompt) cmd_prompt "$@" ;;
        wait) cmd_wait "$@" ;;
        read) cmd_read "$@" ;;
        cancel) cmd_cancel "$@" ;;
        ls) cmd_ls "$@" ;;
        find) cmd_find "$@" ;;
        attach) cmd_attach "$@" ;;
        rename) cmd_rename "$@" ;;
        kill) cmd_kill "$@" ;;
        _internal)
            local sub="${1:-}"
            shift || true
            case "$sub" in
                claude6) compute_claude6; echo ;;
                validate_topic) validate_topic "$@" ;;
                rand_suffix) rand_suffix; echo ;;
                compose_window_name) compose_window_name "$@" ;;
                ensure_session) ensure_session ;;
                window_exists) window_exists "$@" ;;
                window_pane_pid) window_pane_pid "$@" ;;
                *) echo "$LABEL: unknown _internal subcommand '$sub'" >&2; exit 2 ;;
            esac
            ;;
        *)
            echo "$LABEL: unknown subcommand '$subcmd'" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
