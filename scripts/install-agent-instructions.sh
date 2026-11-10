#!/usr/bin/env bash
# Open Sauce — install standing instructions for AI coding agents
#
# Adds (or updates) the Open Sauce instruction block in the instruction files
# that Codex and Claude Code load automatically, so the agent applies the
# security baseline in every applicable repo you work in.
#
# The block is delimited by <!-- open-sauce:start --> / <!-- open-sauce:end -->.
# It is always pinned to a single commit SHA (never `main`), so a later push to
# Open Sauce can't change what your agent follows. Re-run to update: the block
# is replaced in place, and nothing outside the markers is touched.
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
#   --ref <ref>      Branch, tag or commit SHA to install (default: main). It is
#                    resolved to a commit SHA once, at install time, and the
#                    instructions (and the setup prompt they link to) are pinned to it.
#   --remove         Remove the Open Sauce block from the selected targets.
#
# Examples:
#   ./scripts/install-agent-instructions.sh --global
#   curl -fsSL https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/scripts/install-agent-instructions.sh \
#     | bash -s -- --global

set -euo pipefail

REPO_URL="https://github.com/asii-mov/open-sauce-security"
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

# Resolve the ref to an immutable commit SHA and download the snippet at that
# commit, so the installed text matches exactly what its pinned URLs serve.
SHA=""
if ! $REMOVE; then
  if [[ "$REF" =~ ^[0-9a-f]{40}$ ]]; then
    SHA="$REF"
  else
    if ! command -v git &> /dev/null; then
      echo "Error: git is required to resolve --ref '$REF' to a commit SHA" >&2
      exit 1
    fi
    refs=$(git ls-remote "$REPO_URL" "refs/heads/$REF" "refs/tags/$REF" "refs/tags/$REF^{}")
    # Prefer a peeled annotated tag, then a branch, then a lightweight tag.
    SHA=$(awk -v r="$REF" '$2 == "refs/tags/" r "^{}" { print $1 }' <<< "$refs")
    [[ -z "$SHA" ]] && SHA=$(awk -v r="$REF" '$2 == "refs/heads/" r { print $1 }' <<< "$refs")
    [[ -z "$SHA" ]] && SHA=$(awk -v r="$REF" '$2 == "refs/tags/" r { print $1 }' <<< "$refs")
  fi
  if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Error: could not resolve --ref '$REF' to a commit SHA in $REPO_URL" >&2
    exit 1
  fi

  curl -fsSL "$BASE_URL/$SHA/$SNIPPET_PATH" -o "$snippet"
  if ! grep -qF "$START_MARKER" "$snippet" || ! grep -qF "$END_MARKER" "$snippet"; then
    echo "Error: downloaded snippet is missing its markers; refusing to install" >&2
    exit 1
  fi
  # Point every Open Sauce URL in the block at the pinned commit.
  sed -i.bak "s#open-sauce-security/main/#open-sauce-security/$SHA/#g" "$snippet" && rm -f "$snippet.bak"
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

if $REMOVE; then
  echo "Open Sauce agent instructions: removing"
else
  echo "Open Sauce agent instructions: pinned to $SHA (from $REF)"
fi
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

if ! $REMOVE; then
  echo "Re-run this script to update to a newer Open Sauce version."
fi
