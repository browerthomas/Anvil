#!/usr/bin/env bats
# Smoke tests for /dispatch-slice Step 6:
#   - `agent-completed` event appended to .anvil/grind-events.jsonl
#   - Block / inline / JSON `<usage>` shapes all parse
#   - Soft-fail when usage block is missing (no event written, exit 0)
#   - Soft-fail when notification file absent (no event written, exit 0)
#   - Multiple events per slice accumulate (each call adds one row)

load ../test_helper

RECORD_SCRIPT="$ANVIL_ROOT/skills/dispatch-slice/scripts/record-agent-completed.sh"
EVENTS_FILE_REL=".anvil/grind-events.jsonl"

setup() {
  setup_fresh_repo
  mkdir -p .anvil
}

# --- block form ------------------------------------------------------------

@test "agent-completed: block-form <usage> writes one event with parsed counters" {
  cat > notif.txt <<'EOF'
Done.

<usage>
  total_tokens: 278901
  tool_uses: 171
  duration_ms: 1478669
</usage>
EOF
  run bash "$RECORD_SCRIPT" \
    --slice slice-block \
    --agent agent-1 \
    --model opus \
    --branch feat-block \
    --notification-file notif.txt
  [ "$status" -eq 0 ]
  [ -f "$EVENTS_FILE_REL" ]
  # Exactly one line in the log.
  [ "$(wc -l < "$EVENTS_FILE_REL" | tr -d ' ')" -eq 1 ]
  # JSON shape check.
  ev=$(cat "$EVENTS_FILE_REL")
  echo "$ev" | jq -e '.ev == "agent-completed"' >/dev/null
  echo "$ev" | jq -e '.slice == "slice-block"' >/dev/null
  echo "$ev" | jq -e '.data.agent == "agent-1"' >/dev/null
  echo "$ev" | jq -e '.data.model == "opus"' >/dev/null
  echo "$ev" | jq -e '.data.branch == "feat-block"' >/dev/null
  echo "$ev" | jq -e '.data.total_tokens == 278901' >/dev/null
  echo "$ev" | jq -e '.data.tool_uses == 171' >/dev/null
  echo "$ev" | jq -e '.data.duration_ms == 1478669' >/dev/null
}

# --- inline form -----------------------------------------------------------

@test "agent-completed: inline self-closing <usage .../> parses counters" {
  cat > notif.txt <<'EOF'
Inline:
<usage total_tokens="500" tool_uses="3" duration_ms="9000" />
EOF
  run bash "$RECORD_SCRIPT" \
    --slice slice-inline \
    --agent agent-2 --model opus --branch feat-inline \
    --notification-file notif.txt
  [ "$status" -eq 0 ]
  ev=$(cat "$EVENTS_FILE_REL")
  echo "$ev" | jq -e '.data.total_tokens == 500' >/dev/null
  echo "$ev" | jq -e '.data.tool_uses == 3' >/dev/null
  echo "$ev" | jq -e '.data.duration_ms == 9000' >/dev/null
}

# --- JSON-body form --------------------------------------------------------

@test "agent-completed: JSON-body <usage>{...}</usage> parses counters" {
  cat > notif.txt <<'EOF'
JSON:
<usage>{"total_tokens": 1234, "tool_uses": 7, "duration_ms": 60000}</usage>
EOF
  run bash "$RECORD_SCRIPT" \
    --slice slice-json \
    --agent agent-3 --model opus --branch feat-json \
    --notification-file notif.txt
  [ "$status" -eq 0 ]
  ev=$(cat "$EVENTS_FILE_REL")
  echo "$ev" | jq -e '.data.total_tokens == 1234' >/dev/null
  echo "$ev" | jq -e '.data.tool_uses == 7' >/dev/null
  echo "$ev" | jq -e '.data.duration_ms == 60000' >/dev/null
}

# --- soft-fail: missing usage block ---------------------------------------

@test "agent-completed: missing <usage> block soft-fails (exit 0, no event)" {
  cat > notif.txt <<'EOF'
No usage block in this notification.
EOF
  run bash "$RECORD_SCRIPT" \
    --slice slice-missing \
    --agent agent-4 --model opus --branch feat-missing \
    --notification-file notif.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping event append"* ]] || [[ "$output" == *"missing"* ]]
  [ ! -f "$EVENTS_FILE_REL" ] || [ "$(wc -l < "$EVENTS_FILE_REL" | tr -d ' ')" -eq 0 ]
}

# --- soft-fail: notification file absent ----------------------------------

@test "agent-completed: missing notification file soft-fails (exit 0, no event)" {
  run bash "$RECORD_SCRIPT" \
    --slice slice-nofile \
    --agent agent-5 --model opus --branch feat-nofile \
    --notification-file /nonexistent/notif.txt
  [ "$status" -eq 0 ]
  [ ! -f "$EVENTS_FILE_REL" ] || [ "$(wc -l < "$EVENTS_FILE_REL" | tr -d ' ')" -eq 0 ]
}

# --- soft-fail: no slice id ----------------------------------------------

@test "agent-completed: missing --slice soft-fails (exit 0, no event)" {
  cat > notif.txt <<'EOF'
<usage>total_tokens: 100 tool_uses: 1 duration_ms: 1000</usage>
EOF
  run bash "$RECORD_SCRIPT" \
    --agent agent-x --model opus --branch feat-x \
    --notification-file notif.txt
  [ "$status" -eq 0 ]
  [ ! -f "$EVENTS_FILE_REL" ] || [ "$(wc -l < "$EVENTS_FILE_REL" | tr -d ' ')" -eq 0 ]
}

# --- explicit counter flags (no notification file) -------------------------

@test "agent-completed: explicit --total-tokens / --tool-uses / --duration-ms flags write event without parsing" {
  run bash "$RECORD_SCRIPT" \
    --slice slice-flags \
    --agent agent-6 --model opus --branch feat-flags \
    --total-tokens 999 --tool-uses 12 --duration-ms 3600
  [ "$status" -eq 0 ]
  ev=$(cat "$EVENTS_FILE_REL")
  echo "$ev" | jq -e '.data.total_tokens == 999' >/dev/null
  echo "$ev" | jq -e '.data.tool_uses == 12' >/dev/null
  echo "$ev" | jq -e '.data.duration_ms == 3600' >/dev/null
}

# --- multiple agents per slice accumulate as separate rows ----------------

@test "agent-completed: multiple agents on the same slice append separate rows (each event is one line)" {
  for i in 1 2 3; do
    bash "$RECORD_SCRIPT" \
      --slice slice-multi \
      --agent "agent-$i" --model opus --branch feat-multi \
      --total-tokens "$((i * 1000))" --tool-uses "$((i * 5))" --duration-ms "$((i * 60000))" \
      >/dev/null
  done
  [ "$(wc -l < "$EVENTS_FILE_REL" | tr -d ' ')" -eq 3 ]
  # Every row has slice=slice-multi and ev=agent-completed.
  while IFS= read -r line; do
    echo "$line" | jq -e '.ev == "agent-completed"' >/dev/null
    echo "$line" | jq -e '.slice == "slice-multi"' >/dev/null
  done < "$EVENTS_FILE_REL"
}

# --- non-numeric counter is dropped, not smuggled into the event log -----

@test "agent-completed: non-numeric counter flag is dropped (defence-in-depth)" {
  # If the runtime emits a label instead of an integer, the writer must
  # not let it through as a string. The drop policy yields an event with
  # null for the bad field rather than rejecting the whole row.
  run bash "$RECORD_SCRIPT" \
    --slice slice-bad-num \
    --agent agent-7 --model opus --branch feat-bad-num \
    --total-tokens "abc" --tool-uses 4 --duration-ms 5000
  [ "$status" -eq 0 ]
  ev=$(cat "$EVENTS_FILE_REL")
  echo "$ev" | jq -e '.data.total_tokens == null' >/dev/null
  echo "$ev" | jq -e '.data.tool_uses == 4' >/dev/null
  echo "$ev" | jq -e '.data.duration_ms == 5000' >/dev/null
}
