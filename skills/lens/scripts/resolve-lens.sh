#!/usr/bin/env bash
# resolve-lens.sh — resolve a lens name (bare or category/<name>) to a prompt file
#
# Usage:
#   resolve-lens.sh <name>
#   resolve-lens.sh systems/sre-incident-responder    # explicit category
#   resolve-lens.sh privacy-lawyer                    # bare name; looks across categories
#
# Output:
#   - On match: prints the lens prompt contents to stdout. Status 0.
#   - On unknown name: prints error to stderr. Status 1.
#   - On ambiguous bare name: prints error listing matches to stderr. Status 2.
#
# Backward compat:
#   - `oncall-3am` (the pre-namespace name) resolves to `systems/sre-incident-responder`
#     and emits a deprecation notice to stderr (status 0 still).

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: resolve-lens.sh <name>" >&2
  exit 1
fi

NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LENSES_DIR="$SCRIPT_DIR/../lenses"

# Backward-compat shim for the pre-namespace name.
if [ "$NAME" = "oncall-3am" ]; then
  echo "deprecation: 'oncall-3am' has been renamed to 'systems/sre-incident-responder'." >&2
  echo "             update your invocations; the old name will be removed in a future release." >&2
  NAME="systems/sre-incident-responder"
fi

# Case 1: explicit category/name form.
if [[ "$NAME" == */* ]]; then
  TARGET="$LENSES_DIR/$NAME.md"
  if [ ! -f "$TARGET" ]; then
    echo "unknown lens: '$NAME'. file not found at $TARGET" >&2
    echo "see skills/lens/SKILL.md 'Available lenses' for the catalogue." >&2
    exit 1
  fi
  cat "$TARGET"
  exit 0
fi

# Case 2: bare name. Look across categories.
MATCHES=()
while IFS= read -r -d '' f; do
  MATCHES+=("$f")
done < <(find "$LENSES_DIR" -mindepth 2 -maxdepth 2 -type f -name "$NAME.md" -print0 2>/dev/null)

case ${#MATCHES[@]} in
  0)
    echo "unknown lens: '$NAME'. no match in saas/, systems/, or generic/." >&2
    echo "see skills/lens/SKILL.md 'Available lenses' for the catalogue." >&2
    exit 1
    ;;
  1)
    cat "${MATCHES[0]}"
    exit 0
    ;;
  *)
    echo "ambiguous lens: '$NAME' resolves to multiple categories:" >&2
    for m in "${MATCHES[@]}"; do
      # Print as category/name for the operator to disambiguate.
      cat_name=$(basename "$(dirname "$m")")
      echo "  - $cat_name/$NAME" >&2
    done
    echo "use the 'category/$NAME' form to pick one." >&2
    exit 2
    ;;
esac
