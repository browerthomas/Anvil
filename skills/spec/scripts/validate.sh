#!/usr/bin/env bash
# anvil/spec — plan validator. Lints a plan markdown (flat or folder) for
# completeness + structural integrity before /grind accepts it.
#
# Usage:
#   validate.sh <plan-path>      # exit 0 = valid, 1 = errors, 2 = warnings only
#   validate.sh <plan-path> --strict   # warnings treated as errors

set -u

# Resolve ANVIL_ROOT (in order):
#   1. existing env var       — operator override
#   2. anvil-config.sh next to skills/ — post-install (any prefix; copy or symlink)
#   3. env-honoured anvil-config.sh    — $ANVIL_HOME/$CLAUDE_HOME/$HOME/.claude
#   4. relative-path fallback ($SCRIPT_DIR/../../..)  — in-checkout / dev mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${ANVIL_ROOT:-}" ]; then
  # The script lives at <install-root>/skills/<name>/scripts/<file>.sh; the
  # config file is at <install-root>/anvil-config.sh — 3 levels up.
  _av_cfg="$SCRIPT_DIR/../../../anvil-config.sh"
  if [ -f "$_av_cfg" ]; then
    # shellcheck source=/dev/null
    . "$_av_cfg"
  fi
  unset _av_cfg
fi
if [ -z "${ANVIL_ROOT:-}" ] && [ -f "${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}/anvil-config.sh" ]; then
  # shellcheck source=/dev/null
  . "${ANVIL_HOME:-${CLAUDE_HOME:-${HOME}/.claude}}/anvil-config.sh"
fi
if [ -z "${ANVIL_ROOT:-}" ]; then
  ANVIL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi
# shellcheck source=/dev/null
. "$ANVIL_ROOT/shared/lib.sh"

PLAN_PATH="${1:-}"
STRICT=0
[ "${2:-}" = "--strict" ] && STRICT=1

if [ -z "$PLAN_PATH" ]; then
  av_fail "usage: validate.sh <plan-path> [--strict]"
  exit 1
fi

if [ -d "$PLAN_PATH" ]; then
  TASKS_FILE="$PLAN_PATH/tasks.md"
  PROPOSAL_FILE="$PLAN_PATH/proposal.md"
  DESIGN_FILE="$PLAN_PATH/design.md"
  LAYOUT="folder"
  [ ! -f "$TASKS_FILE" ] && { av_fail "folder plan missing tasks.md: $PLAN_PATH"; exit 1; }
elif [ -f "$PLAN_PATH" ]; then
  TASKS_FILE="$PLAN_PATH"
  PROPOSAL_FILE="$PLAN_PATH"
  DESIGN_FILE="$PLAN_PATH"
  LAYOUT="flat"
else
  av_fail "plan not found: $PLAN_PATH"
  exit 1
fi

ERRORS=()
WARNINGS=()
err()  { ERRORS+=("$1"); }
warn() { WARNINGS+=("$1"); }

# 1. Goal section
if ! grep -qE "^##\s+Goal" "$PROPOSAL_FILE"; then
  err "missing ## Goal section"
fi

# 2. Scope lists
grep -qE "^### In scope|^## Scope" "$PROPOSAL_FILE" || warn "no In-scope section found"
grep -qE "^### Out of scope" "$PROPOSAL_FILE" || warn "no Out-of-scope section found"

# 3. Hard constraints
if ! grep -qE "^## Hard constraints" "$DESIGN_FILE"; then
  err "missing ## Hard constraints section"
fi

# 4. Slice manifest YAML
yaml=$(awk '/^```yaml/{flag=1; next} /^```/{if(flag){exit}; next} flag {print}' "$TASKS_FILE")
if ! echo "$yaml" | grep -q "slices:"; then
  err "no slices: YAML block found"
else
  if command -v yq >/dev/null 2>&1; then
    slices_json=$(echo "$yaml" | yq -o=json 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    slices_json=$(echo "$yaml" | python3 -c 'import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.stdin)))' 2>/dev/null)
  else
    err "need yq or python3+pyyaml to parse YAML"
    slices_json=""
  fi

  if [ -z "$slices_json" ] || ! echo "$slices_json" | jq -e '.slices' >/dev/null 2>&1; then
    err "could not parse slices YAML (check syntax)"
  else
    # 5+6. Cycle + dep resolution combined
    bad_deps=$(echo "$slices_json" | jq -r '
      .slices as $s
      | ($s | map(.id)) as $ids
      | $s
      | map(. as $sl | (.["depends-on"] // []) | map(select(. as $d | $ids | index($d) | not)) | map("\($sl.id) -> \(.)"))
      | flatten | unique | .[]
    ' 2>/dev/null)
    if [ -n "$bad_deps" ]; then
      while IFS= read -r dep; do err "unresolved dependency: $dep"; done <<< "$bad_deps"
    fi

    # 7. Acceptance criteria
    no_acceptance=$(echo "$slices_json" | jq -r '.slices | map(select((.acceptance // []) | length == 0)) | .[].id' 2>/dev/null)
    if [ -n "$no_acceptance" ]; then
      while IFS= read -r sid; do err "slice '$sid' has no acceptance criteria"; done <<< "$no_acceptance"
    fi

    # 8. Operator-decision shape
    bad_decisions=$(echo "$slices_json" | jq -r '
      .slices
      | map(select(.["operator-decision"].ask != null))
      | map(select(((.["operator-decision"].verbs // []) | length == 0) or (.["operator-decision"].default == null)))
      | .[].id
    ' 2>/dev/null)
    if [ -n "$bad_decisions" ]; then
      while IFS= read -r sid; do err "slice '$sid' has operator-decision.ask but missing verbs or default"; done <<< "$bad_decisions"
    fi
  fi
fi

# Verdict
echo
echo "===================="
echo "Plan validation: $PLAN_PATH"
echo "Layout: $LAYOUT"
echo

if [ "${#ERRORS[@]}" -gt 0 ]; then
  printf "${AV_RED}ERRORS (%d):${AV_RESET}\n" "${#ERRORS[@]}"
  for e in "${ERRORS[@]}"; do printf "  ${AV_RED}x${AV_RESET} %s\n" "$e"; done
  echo
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  printf "${AV_YELLOW}WARNINGS (%d):${AV_RESET}\n" "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do printf "  ${AV_YELLOW}~${AV_RESET} %s\n" "$w"; done
  echo
fi

if [ "${#ERRORS[@]}" -eq 0 ] && [ "${#WARNINGS[@]}" -eq 0 ]; then
  printf "${AV_GREEN}PLAN VALIDATES${AV_RESET}\n"
  exit 0
elif [ "${#ERRORS[@]}" -eq 0 ]; then
  printf "${AV_GREEN}plan validates with warnings${AV_RESET}\n"
  [ "$STRICT" -eq 1 ] && exit 1
  exit 2
else
  printf "${AV_RED}plan has errors - fix before /grind${AV_RESET}\n"
  exit 1
fi
