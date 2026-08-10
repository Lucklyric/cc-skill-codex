#!/usr/bin/env bats
# Tests for the T2 driving verbs (prompt / wait / read / cancel) and the
# --json output of panes/find. Runs against a DEDICATED detached test session
# with the mock codex fixture (which prints the production-default idle status
# line), exactly like test_codex_pane.bats. See README.md.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/codex-tmux.sh"

setup() {
    PANE_SESSION="cc-codex-verbs-test-$$"
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$PANE_SESSION" -x 220 -y 50
    REF_PANE="$(tmux list-panes -t "$PANE_SESSION" -F '#{pane_id}' | head -n1)"
    export CC_CODEX_REF_PANE="$REF_PANE"
    export CC_CODEX_BIN="$BATS_TEST_DIRNAME/fixtures/mock-codex.sh"
    export CLAUDE_CODE_SESSION_ID="ee61e624-1494-4aec-9b46-31d2a9534099"  # claude6=ee61e6
    export CC_CODEX_SESSION_NAME="cc-codex-verbstest-$$"
    export CC_CODEX_EXIT_SHELL="/bin/bash"
}

teardown() {
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux kill-session -t "$CC_CODEX_SESSION_NAME" 2>/dev/null || true
}

spawn_pane() {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    PANE="${lines[0]}"
    [[ "$PANE" =~ ^%[0-9]+$ ]]
}

@test "prompt+wait+read --delta: full roundtrip returns the mock response" {
    spawn_pane
    run "$SCRIPT" prompt --wait --timeout 20 "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle"* ]]
    run "$SCRIPT" read --delta
    [ "$status" -eq 0 ]
    [[ "$output" == *"[mock-response] you said: hello"* ]]
}

@test "prompt: multi-line text is handed over via a tmp file" {
    spawn_pane
    run "$SCRIPT" prompt --wait --timeout 20 $'line one\nline two'
    [ "$status" -eq 0 ]
    run "$SCRIPT" read --delta
    [ "$status" -eq 0 ]
    # The mock echoes the pointer message, not the body: prove the tmp-file path.
    [[ "$output" == *"you said: Read @"* ]]
}

@test "prompt without --wait reports the target it sent to" {
    spawn_pane
    run "$SCRIPT" prompt "quick one"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sent to $PANE"* ]]
}

@test "wait standalone on an idle pane returns 0 and prints idle" {
    spawn_pane
    sleep 0.5
    run "$SCRIPT" wait --timeout 15
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]
}

@test "wait: exits 5 on timeout when the idle regex never matches" {
    spawn_pane
    CC_CODEX_IDLE_REGEX='WILL-NEVER-MATCH-12345' run "$SCRIPT" wait --timeout 2
    [ "$status" -eq 5 ]
}

@test "prompt: exits 6 when no codex pane exists for the topic" {
    run "$SCRIPT" prompt "nobody home"
    [ "$status" -eq 6 ]
}

@test "prompt: exits 2 when both text and --file are given" {
    run "$SCRIPT" prompt --file /tmp/whatever "and text"
    [ "$status" -eq 2 ]
}

@test "prompt: exits 9 when the pane is a kept shell (codex exited)" {
    spawn_pane
    tmux send-keys -t "$PANE" "/exit" Enter
    sleep 1.0
    run "$SCRIPT" prompt "anyone there"
    [ "$status" -eq 9 ]
    [[ "$output" == *"not alive"* ]]
}

@test "read: default prints recent scrollback including the mock banner" {
    spawn_pane
    sleep 0.5
    run "$SCRIPT" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-codex v0.0.0 ready"* ]]
}

@test "read --delta on a kept-shell pane still prints the last response" {
    spawn_pane
    run "$SCRIPT" prompt --wait --timeout 20 "final words"
    [ "$status" -eq 0 ]
    tmux send-keys -t "$PANE" "/exit" Enter
    sleep 1.0
    run "$SCRIPT" read --delta
    [ "$status" -eq 0 ]
    [[ "$output" == *"you said: final words"* ]]
}

@test "cancel: sends Escape and reports the target" {
    spawn_pane
    run "$SCRIPT" cancel
    [ "$status" -eq 0 ]
    [[ "$output" == *"cancel sent to $PANE"* ]]
}

@test "panes --json: emits a JSON array with pane_id/state fields" {
    spawn_pane
    run "$SCRIPT" panes --json
    [ "$status" -eq 0 ]
    [[ "$output" == \[* ]]
    [[ "$output" == *'"pane_id":"'"$PANE"'"'* ]]
    [[ "$output" == *'"state":"alive"'* ]]
}

@test "find --json: prints [] and exits 1 when nothing matches" {
    run "$SCRIPT" find nomatch --json
    [ "$status" -eq 1 ]
    [ "$output" = "[]" ]
}
