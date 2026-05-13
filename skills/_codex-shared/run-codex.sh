#!/usr/bin/env bash
# Shared helper for codex-{review,confer,check,debug,plan} skills.
#
# Runs `codex exec` (or `codex review`) with sane defaults:
#   - read-only sandbox (codex cannot mutate the working tree)
#   - --skip-git-repo-check (works in worktrees)
#   - --output-last-message → clean final answer to a temp file
#   - --ignore-rules so codex's own .rules don't add noise
#
# Logs every call to .codex-log/<timestamp>-<command>.md so the
# operator can audit what was asked and what came back.
#
# Usage:
#   run-codex.sh <command-tag> exec [extra args...] -- "<prompt>"
#   run-codex.sh <command-tag> review [extra args...]   # reads prompt from stdin
#
# Outputs (on stdout):
#   1. Header line with the log file path
#   2. The clean final answer
#
# Suppresses the verbose intermediate event stream so the parent
# Claude Code session doesn't drown in tool-call traces.

set -euo pipefail

cmd_tag="${1:?command tag required (e.g. review|confer|check|debug|plan)}"
shift

mode="${1:?mode required (exec|review)}"
shift

# Find repo root for log placement; fall back to cwd.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
log_dir="$repo_root/.codex-log"
mkdir -p "$log_dir"

ts="$(date +%Y%m%d-%H%M%S)"
log_file="$log_dir/${ts}-${cmd_tag}.md"
last_msg="$(mktemp -t codex-last-XXXXXX.md)"

# Split args: anything before `--` is passed to codex, anything after is the prompt.
# Wrapper-level flags intercepted here (not passed to codex):
#   --resume <session-id>   — call `codex exec resume <session-id>` instead of plain `codex exec`
#                              (continues a previous session's context; iterative-loop pattern)
#   --resume --last         — resume the most recent session
codex_args=()
prompt=""
resume_session=""
resume_last=false
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    prompt="${1:-}"
    shift || true
    break
  fi
  if [[ "$1" == "--resume" ]]; then
    shift
    if [[ "${1:-}" == "--last" ]]; then
      resume_last=true
      shift
    else
      resume_session="${1:-}"
      shift || true
    fi
    continue
  fi
  codex_args+=("$1")
  shift
done

# `codex exec` accepts -s, --skip-git-repo-check, --output-last-message.
# `codex review` does NOT — its supported flags are -c, --uncommitted,
# --base, --commit, --enable, --disable, --title. The whole stdout of
# `codex review` IS the final answer (no intermediate event stream),
# so we capture stdout to the log and surface it directly.
exec_flags=(
  -s read-only
  --skip-git-repo-check
  --output-last-message "$last_msg"
)

# Default reasoning effort. Codex CLI defaults to `xhigh` which is
# overkill for routine review / check / confer calls and burns the
# subscription cap faster. `medium` is the sensible default for
# every skill (operator-confirmed 2026-05-13: medium for everything
# unless real high is needed). Override per-call by passing
# `-c reasoning_effort=high` in the codex_args (anything before `--`)
# ONLY when the task genuinely needs the depth — high + many context
# files can burn the budget on exploration loops and return empty.
default_reasoning="medium"
case " ${codex_args[*]:-} " in
  *" -c reasoning_effort"*) ;;  # caller already specified — respect it.
  *) codex_args=(-c "reasoning_effort=$default_reasoning" ${codex_args[@]+"${codex_args[@]}"}) ;;
esac

# Build the call. `codex review` reads its prompt from stdin via `-`;
# `codex exec` takes it as a positional arg (or stdin via `-`).
{
  echo "# codex-$cmd_tag — $ts"
  echo
  echo "**Mode:** \`codex $mode\`"
  echo "**Args:** \`${codex_args[*]:-}\`"
  echo
  echo "## Prompt"
  echo
  echo '```'
  if [[ -n "$prompt" ]]; then
    echo "$prompt"
  else
    echo "(stdin)"
  fi
  echo '```'
  echo
  echo "## Codex final answer"
  echo
} > "$log_file"

# Run codex. Stream verbose output to a sibling file (for debugging
# if codex misbehaves), but only the last message goes to stdout.
verbose_log="$log_dir/${ts}-${cmd_tag}.verbose.log"

if [[ "$mode" == "review" ]]; then
  # codex review's whole stdout IS the answer — capture it directly.
  review_out="$log_dir/${ts}-${cmd_tag}.out"
  if [[ -n "$prompt" ]]; then
    echo "$prompt" | codex review ${codex_args[@]+"${codex_args[@]}"} - >"$review_out" 2>"$verbose_log" || true
  else
    codex review ${codex_args[@]+"${codex_args[@]}"} >"$review_out" 2>"$verbose_log" || true
  fi
  if [[ -s "$review_out" ]]; then
    cat "$review_out" >> "$log_file"
    echo "[codex-$cmd_tag] log: $log_file"
    echo
    cat "$review_out"
  else
    echo "[codex-$cmd_tag] WARNING: codex review produced no output; see $verbose_log" >&2
    echo "(no output; verbose log: $verbose_log)" >> "$log_file"
    exit 3
  fi
elif [[ "$mode" == "exec" ]]; then
  # Resume mode: `codex exec resume [SESSION_ID|--last] [PROMPT]`
  # Continues a prior exec session's context — useful for iterative-loop
  # patterns (Claude revises plan, re-asks Codex with same context).
  if [[ "$resume_last" == "true" ]]; then
    codex_invocation=(codex exec resume "${exec_flags[@]}" ${codex_args[@]+"${codex_args[@]}"} --last)
  elif [[ -n "$resume_session" ]]; then
    codex_invocation=(codex exec resume "${exec_flags[@]}" ${codex_args[@]+"${codex_args[@]}"} "$resume_session")
  else
    codex_invocation=(codex exec "${exec_flags[@]}" ${codex_args[@]+"${codex_args[@]}"})
  fi

  if [[ -n "$prompt" ]]; then
    "${codex_invocation[@]}" "$prompt" >"$verbose_log" 2>&1 || true
  else
    "${codex_invocation[@]}" >"$verbose_log" 2>&1 || true
  fi

  # Retry-on-empty fallback: if codex exited cleanly but never wrote a
  # final assistant turn, it almost certainly exhausted its reasoning
  # budget mid-thought (lesson learned 2026-05-13: high reasoning + many
  # context files → recursive grep loop → empty output). Retry once at
  # reduced effort with a "produce output now" preamble so we don't
  # silently fail.
  if [[ ! -s "$last_msg" && -n "$prompt" ]]; then
    echo "[codex-$cmd_tag] first attempt produced no final answer; retrying with reasoning_effort=low + 'time budget short' preamble" >&2

    # Strip any `-c reasoning_effort=*` pair from codex_args; force low.
    # Index-based iteration so we can peek the next arg cleanly. Preserves
    # other `-c key=value` pairs (e.g. `-c verbosity=high`) that aren't
    # reasoning_effort.
    retry_args=()
    i=0
    while [[ $i -lt ${#codex_args[@]} ]]; do
      arg="${codex_args[$i]}"
      if [[ "$arg" == "-c" && $((i+1)) -lt ${#codex_args[@]} ]]; then
        next="${codex_args[$((i+1))]}"
        if [[ "$next" == reasoning_effort=* ]]; then
          i=$((i+2))   # skip both `-c` and its reasoning_effort= value
          continue
        fi
      fi
      retry_args+=("$arg")
      i=$((i+1))
    done
    retry_args+=(-c "reasoning_effort=low")

    retry_prompt="**RETRY: time budget short. Your first attempt produced no output — likely exhausted on exploration. Produce your structured response NOW based on what you already know from the context. Do not re-grep, do not re-read files, do not explore further. Even a partial response is more useful than another empty one.**

$prompt"

    echo "" >> "$verbose_log"
    echo "===== RETRY ATTEMPT =====" >> "$verbose_log"
    codex exec "${exec_flags[@]}" "${retry_args[@]}" "$retry_prompt" >>"$verbose_log" 2>&1 || true
  fi

  # Append final answer to the log + emit on stdout
  if [[ -s "$last_msg" ]]; then
    cat "$last_msg" >> "$log_file"
    echo "[codex-$cmd_tag] log: $log_file"
    echo
    cat "$last_msg"
  else
    echo "[codex-$cmd_tag] WARNING: codex returned no final answer after retry; see $verbose_log" >&2
    echo "(no final answer after retry; verbose log: $verbose_log)" >> "$log_file"
    exit 3
  fi
  rm -f "$last_msg"
else
  echo "ERROR: unknown mode '$mode' (expected exec|review)" >&2
  exit 2
fi
