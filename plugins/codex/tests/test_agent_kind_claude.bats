#!/usr/bin/env bats
# Second-consumer tests (spec 016 T3): the SAME engine drives kind=claude.
# Invokes agent-tmux.sh directly with CC_AGENT_* (no wrapper), using the mock
# fixture as the "claude" binary — what's under test is the engine's kind
# parameterization (naming, markers, verbs), not the real Claude CLI.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/agent-tmux.sh"

setup() {
    PANE_SESSION="cc-claude-kind-test-$$"
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$PANE_SESSION" -x 220 -y 50
    REF_PANE="$(tmux list-panes -t "$PANE_SESSION" -F '#{pane_id}' | head -n1)"
    export CC_AGENT_REF_PANE="$REF_PANE"
    export CC_AGENT_BIN="$BATS_TEST_DIRNAME/fixtures/mock-codex.sh"
    export CLAUDE_CODE_SESSION_ID="cc61e624-1494-4aec-9b46-31d2a9534099"  # claude6=cc61e6
    export CC_AGENT_SESSION_NAME="cc-claude-kindtest-$$"
    export CC_AGENT_EXIT_SHELL="/bin/bash"
    # The mock prints the codex-style status line; override the claude
    # profile's idle regex so wait/prompt --wait settle against the mock.
    export CC_AGENT_IDLE_REGEX='gpt-5\.[0-9].*·'
}

teardown() {
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux kill-session -t "$CC_AGENT_SESSION_NAME" 2>/dev/null || true
}

@test "kind=claude pane: spawns and stamps @cc_claude_* markers" {
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    local pane="${lines[0]}"
    [[ "$pane" =~ ^%[0-9]+$ ]]
    [ "$(tmux show-option -p -qv -t "$pane" '@cc_claude_claude6')" = "cc61e6" ]
    [ "$(tmux show-option -p -qv -t "$pane" '@cc_claude_topic')" = "main" ]
    # No cross-kind leakage: the codex marker namespace stays empty.
    [ -z "$(tmux show-option -p -qv -t "$pane" '@cc_codex_claude6')" ]
}

@test "kind=claude pane: is idempotent per session" {
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    local first="${lines[0]}"
    sleep 0.3
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$first" ]
}

@test "kind=claude panes: lists the pane with state alive" {
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    local pane="${lines[0]}"
    run "$SCRIPT" --kind claude panes
    [ "$status" -eq 0 ]
    [[ "$output" == *"$pane"$'\t'"main"$'\t'"alive"* ]]
}

@test "kind=claude prompt+wait+read --delta: engine verbs are kind-agnostic" {
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    run "$SCRIPT" --kind claude prompt --wait --timeout 20 "ping from claude kind"
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle"* ]]
    run "$SCRIPT" --kind claude read --delta
    [ "$status" -eq 0 ]
    [[ "$output" == *"you said: ping from claude kind"* ]]
}

@test "kind=claude bind: creates the claude-<claude6> window in the shared session" {
    unset CC_AGENT_REF_PANE
    run "$SCRIPT" --kind claude bind --cwd /tmp
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "claude-cc61e6" ]
    tmux list-windows -t "$CC_AGENT_SESSION_NAME" -F '#{window_name}' | grep -Fxq "claude-cc61e6"
}

@test "kind=claude keep-shell: exit drops to shell state, relaunch reuses the pane" {
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    local pane="${lines[0]}"
    tmux send-keys -t "$pane" "/exit" Enter
    sleep 1.0
    run "$SCRIPT" --kind claude panes
    [ "$status" -eq 0 ]
    [[ "$output" == *"$pane"$'\t'"main"$'\t'"shell"* ]]
    run "$SCRIPT" --kind claude pane --cwd /tmp
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$pane" ]
    [[ "$output" == *"Relaunched claude in kept pane"* ]]
}
