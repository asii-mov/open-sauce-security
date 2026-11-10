#!/usr/bin/env bash
# Open Sauce — install standing instructions for AI coding agents
#
# Adds (or updates) the Open Sauce instruction block in the instruction files
# that Codex and Claude Code load automatically, so the agent applies the
# security baseline in every applicable repo you work in.
#
# The block is delimited by <!-- open-sauce:start --> / <!-- open-sauce:end -->.
# Re-running replaces the block in place; nothing outside the markers is touched.
#
# Usage:
#   ./install-agent-instructions.sh [targets...] [--ref <git-ref>] [--remove]
#
# Targets (pick one or more):
#   --codex          $CODEX_HOME/AGENTS.md (default ~/.codex/AGENTS.md) — all Codex sessions
#   --claude         $CLAUDE_CONFIG_DIR/CLAUDE.md (default ~/.claude/CLAUDE.md) — all Claude Code sessions
#   --global         both of the above
#   --repo-agents    ./AGENTS.md in the current repo (Codex, and other AGENTS.md-aware agents)
#   --repo-claude    ./CLAUDE.md in the current repo (imports AGENTS.md if it has the block)
#   --file <path>    any other instruction file
#
# Options:
#   --ref <ref>      Pin the instructions (and the setup prompt they link to) to a
#                    commit SHA or tag instead of `main`. Recommended.
#   --remove         Remove the Open Sauce block from the selected targets.
#
# Examples:
#   ./scripts/install-agent-instructions.sh --global
#   curl -fsSL https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/scripts/install-agent-instructions.sh \
#     | bash -s -- --global --ref <commit-sha>

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/asii-mov/open-sauce-security"
SNIPPET_PATH="agents/open-sauce-instructions.md"
START_MARKER="<!-- open-sauce:start -->"
END_MARKER="<!-- open-sauce:end -->"

REF="main"
REMOVE=false
targets=()

usage() { sed -n '2,/^$/p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --codex)       targets+=("${CODEX_HOME:-$HOME/.codex}/AGENTS.md"); shift ;;
    --claude)      targets+=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"); shift ;;
    --global)      targets+=("${CODEX_HOME:-$HOME/.codex}/AGENTS.md" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"); shift ;;
    --repo-agents) targets+=("$PWD/AGENTS.md"); shift ;;
    --repo-claude) targets+=("$PWD/CLAUDE.md"); shift ;;
    --file)        targets+=("$2"); shift 2 ;;
    --ref)         REF="$2"; shift 2 ;;
    --remove)      REMOVE=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "Error: choose at least one target (--codex, --claude, --global, --repo-agents, --repo-claude, --file <path>)" >&2
  exit 1
fi

if [[ ! "$REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "Error: invalid --ref '$REF'" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
snippet="$tmp/snippet.md"

# Prefer the local checkout when the script is run from a clone at the default ref;
# otherwise download the snippet at the requested ref.
script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
if [[ "$REF" == "main" && -n "$script_dir" && -f "$script_dir/../$SNIPPET_PATH" ]]; then
  cp "$script_dir/../$SNIPPET_PATH" "$snippet"
elif ! $REMOVE; then
  curl -fsSL "$BASE_URL/$REF/$SNIPPET_PATH" -o "$snippet"
fi

if ! $REMOVE; then
  if ! grep -qF "$START_MARKER" "$snippet" || ! grep -qF "$END_MARKER" "$snippet"; then
    echo "Error: downloaded snippet is missing its markers; refusing to install" >&2
    exit 1
  fi
  # Point the setup-prompt link at the pinned ref.
  if [[ "$REF" != "main" ]]; then
    sed -i.bak "s#open-sauce-security/main/#open-sauce-security/$REF/#g" "$snippet" && rm -f "$snippet.bak"
  fi
fi

# Remove any existing block from $1 (in place), plus the blank lines it leaves
# at the end of the file. Leaves the rest of the file intact.
strip_block() {
  awk -v s="$START_MARKER" -v e="$END_MARKER" '
    index($0, s) { skip = 1; next }
    skip && index($0, e) { skip = 0; next }
    skip { next }
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    { printf "%s", blanks; blanks = ""; print }
  ' "$1" > "$1.open-sauce.tmp" && mv "$1.open-sauce.tmp" "$1"
}

# Replace an existing block in place, or append one.
install_block() {
  local file=$1
  if grep -qF "$START_MARKER" "$file"; then
    awk -v s="$START_MARKER" -v e="$END_MARKER" -v snip="$snippet" '
      index($0, s) { while ((getline line < snip) > 0) print line; skip = 1; next }
      skip && index($0, e) { skip = 0; next }
      !skip { print }
    ' "$file" > "$file.open-sauce.tmp" && mv "$file.open-sauce.tmp" "$file"
    echo "  updated  $file"
  else
    if [[ -s "$file" ]]; then
      # Ensure a blank line separates existing content from the block.
      [[ -n "$(tail -c1 "$file")" ]] && echo >> "$file"
      echo >> "$file"
    fi
    cat "$snippet" >> "$file"
    echo "  added    $file"
  fi
}

# Process CLAUDE.md targets last so a repo AGENTS.md is in place before we
# decide whether the repo CLAUDE.md can just import it.
ordered=()
for f in "${targets[@]}"; do [[ "$(basename "$f")" != "CLAUDE.md" ]] && ordered+=("$f"); done
for f in "${targets[@]}"; do [[ "$(basename "$f")" == "CLAUDE.md" ]] && ordered+=("$f"); done

echo "Open Sauce agent instructions (ref: $REF)"
for file in "${ordered[@]}"; do
  if $REMOVE; then
    if [[ -f "$file" ]] && grep -qF "$START_MARKER" "$file"; then
      strip_block "$file"
      echo "  removed  $file"
    else
      echo "  absent   $file"
    fi
    continue
  fi

  # A repo CLAUDE.md can import AGENTS.md rather than duplicating the block.
  if [[ "$(basename "$file")" == "CLAUDE.md" && "$file" == "$PWD/CLAUDE.md" \
        && -f "$PWD/AGENTS.md" ]] && grep -qF "$START_MARKER" "$PWD/AGENTS.md"; then
    if [[ -f "$file" ]] && grep -qxF "@AGENTS.md" "$file"; then
      echo "  ok       $file (already imports AGENTS.md)"
    else
      [[ -s "$file" && -n "$(tail -c1 "$file")" ]] && echo >> "$file"
      echo "@AGENTS.md" >> "$file"
      echo "  added    $file (imports AGENTS.md)"
    fi
    continue
  fi

  mkdir -p "$(dirname "$file")"
  touch "$file"
  install_block "$file"
done
