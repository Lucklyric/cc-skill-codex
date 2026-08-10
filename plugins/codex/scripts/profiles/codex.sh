# shellcheck shell=bash
# shellcheck disable=SC2034  # PROFILE_* vars are consumed by the sourcing engine
# profiles/codex.sh — codex kind profile for agent-tmux.sh (sourced, not run).
#
# Profile contract — every profile defines:
#   PROFILE_TITLE          display name used in success messages ("Codex pane %s ...")
#   PROFILE_BIN_DEFAULT    binary launched when CC_AGENT_BIN is unset
#   PROFILE_MODEL_DEFAULT  model pinned at every spawn (CC_AGENT_MODEL overrides)
#   PROFILE_EFFORT_DEFAULT reasoning effort pinned at every spawn
#   PROFILE_ENV_PREFIX     legacy env-var prefix shown in user-facing messages
#   PROFILE_RESUME_CMD     command a human types in the kept shell to continue
#                          the previous conversation (keep-shell hint text)
#   PROFILE_LOGIN_HINT     auth command suggested when the CLI dies at launch
#   PROFILE_IDLE_REGEX     input-ready status-line regex (consumed by the skill
#                          recipes today; the `wait` verb in a later ticket)
#   PROFILE_VERSION_FLOOR  minimum CLI version these defaults assume
#   agent_compose_cmd SANDBOX APPROVAL
#                          append the full launch argv to the AGENT_CMD array,
#                          starting from $AGENT_BIN and using $AGENT_MODEL /
#                          $AGENT_EFFORT (already env-resolved by the engine)
#
# Version-sensitive facts live HERE (single source of truth) — a codex CLI
# upgrade should only ever touch this file and the codex skill references.

PROFILE_TITLE="Codex"
PROFILE_BIN_DEFAULT="codex"
# gpt-5.6-sol requires codex CLI >= 0.144.0; on older CLIs users set
# CC_CODEX_MODEL=gpt-5.5. Other 5.6 slugs: gpt-5.6-terra (balanced),
# gpt-5.6-luna (fast). Effort ladder: low<medium<high<xhigh<max<ultra
# (max/ultra are 5.6-series; ultra is sol/terra only).
PROFILE_MODEL_DEFAULT="gpt-5.6-sol"
PROFILE_EFFORT_DEFAULT="xhigh"
PROFILE_ENV_PREFIX="CC_CODEX"
PROFILE_RESUME_CMD="codex resume --last"
PROFILE_LOGIN_HINT="codex login"
# Safety defaults applied when the caller passes no --full-auto/--read-only:
# sandbox mode and approval policy for every fresh start (spawn or relaunch).
PROFILE_SANDBOX_DEFAULT="read-only"
PROFILE_APPROVAL_DEFAULT="on-request"
# First-run gate: on a fresh CODEX_HOME the TUI shows a "Hooks need review"
# prompt before accepting work — dismiss with: send-keys "2" Enter ("Trust
# all and continue"). Auth gate: "Not authenticated" → PROFILE_LOGIN_HINT.
# Consumed by the skill recipes (tmux-mode.md) and T5's blocked-state work.
PROFILE_FIRST_RUN_GATE='Hooks need review -> send "2" Enter (Trust all and continue)'
# Model-agnostic across the 5.x slugs; anchored to the middot before the cwd
# path in the status line ("gpt-5.6-sol xhigh · /path"). No script consumer
# yet: T2's `wait` verb reads it; until T6 migrates the docs, the skill
# references still carry their own copy of the same regex.
PROFILE_IDLE_REGEX='gpt-5\.[0-9].*·'
PROFILE_VERSION_FLOOR="0.144.0"

agent_compose_cmd() {
    local sandbox="$1" approval="$2"
    AGENT_CMD=(
        "$AGENT_BIN"
        -m "$AGENT_MODEL"
        -c "approval_policy=$approval"
        -c "model_reasoning_effort=$AGENT_EFFORT"
        -s "$sandbox"
    )
    if [[ "$sandbox" == "workspace-write" ]]; then
        AGENT_CMD+=( -c "sandbox_workspace_write.network_access=true" )
    fi
}
