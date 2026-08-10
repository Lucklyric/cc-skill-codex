# shellcheck shell=bash
# shellcheck disable=SC2034  # PROFILE_* vars are consumed by the sourcing engine
# profiles/claude.sh — Claude Code CLI kind profile for agent-tmux.sh
# (sourced, not run). See profiles/codex.sh for the full profile contract.
#
# PoC profile (spec 016 T3): proves the engine drives a second kind. Deepened
# in T8 (dedicated claude skill + live calibration).

PROFILE_TITLE="Claude"
PROFILE_BIN_DEFAULT="claude"
# Empty = inherit the user's configured default model; set CC_AGENT_MODEL
# (e.g. sonnet, opus, haiku, or a full model id) to pin one per spawn.
PROFILE_MODEL_DEFAULT=""
# Claude Code has no reasoning-effort flag; kept empty.
PROFILE_EFFORT_DEFAULT=""
PROFILE_ENV_PREFIX="CC_AGENT"
PROFILE_RESUME_CMD="claude --continue"
PROFILE_LOGIN_HINT="claude /login"
# Generic safety defaults. read-only maps to Claude Code's default permission
# mode (every edit needs an approval, visible in the pane for the human);
# workspace-write maps to --permission-mode acceptEdits.
PROFILE_SANDBOX_DEFAULT="read-only"
PROFILE_APPROVAL_DEFAULT="on-request"
# First-run gates: theme picker on the very first launch, and a per-directory
# "Do you trust the files in this folder?" prompt (Enter accepts). Auth gate:
# run PROFILE_LOGIN_HINT inside the pane.
PROFILE_FIRST_RUN_GATE='trust prompt: "Do you trust the files in this folder?" -> Enter'
# Idle/busy calibration. Claude Code's idle footer is USER-CONFIGURABLE
# (custom statuslines, vim mode indicators), so no positive idle marker is
# reliable across setups — leave IDLE_REGEX empty (stability-only) and anchor
# on the universal BUSY marker instead: while a turn runs, the TUI shows
# "esc to interrupt" near the input box (verified live on Claude Code 2.1.x).
PROFILE_IDLE_REGEX=''
PROFILE_BUSY_REGEX='esc to interrupt'
PROFILE_VERSION_FLOOR="2.0.0"

agent_compose_cmd() {
    local sandbox="$1"
    AGENT_CMD=( "$AGENT_BIN" )
    [[ -n "$AGENT_MODEL" ]] && AGENT_CMD+=( --model "$AGENT_MODEL" )
    if [[ "$sandbox" == "workspace-write" ]]; then
        AGENT_CMD+=( --permission-mode acceptEdits )
    fi
    return 0
}
