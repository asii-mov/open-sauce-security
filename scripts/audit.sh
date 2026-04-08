#!/usr/bin/env bash
# Open Sauce — Local Security Audit
# Run this script from the root of your GitHub repository to check its
# security posture. Outputs a pass/fail checklist with fix suggestions.
#
# Requirements: gh (GitHub CLI, authenticated), git, jq
# Optional: pinact, zizmor (will skip checks if not installed)
#
# Usage:
#   ./audit.sh
#   ./audit.sh --repo owner/repo   # audit a specific repo's GitHub settings

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass=0
fail=0
warn=0

check_pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  ((pass++))
}

check_fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  echo -e "        ${YELLOW}Fix:${NC} $2"
  ((fail++))
}

check_warn() {
  echo -e "  ${YELLOW}[WARN]${NC} $1"
  echo -e "        ${YELLOW}Tip:${NC} $2"
  ((warn++))
}

check_skip() {
  echo -e "  ${BLUE}[SKIP]${NC} $1"
}

section() {
  echo ""
  echo -e "${BOLD}$1${NC}"
  echo "  $(printf '%.0s─' {1..60})"
}

# --- Parse args ---
REPO=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Detect repo from git remote if not specified
if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
  if [[ -z "$REPO" ]]; then
    echo "Error: Could not detect repo. Run from a git repo or pass --repo owner/name"
    exit 1
  fi
fi

echo ""
echo -e "${BOLD}Open Sauce Security Audit${NC}"
echo -e "Repo: ${BLUE}$REPO${NC}"
echo -e "Date: $(date -u '+%Y-%m-%d %H:%M UTC')"

# =====================================================================
# 1. Workflow Security
# =====================================================================
section "1. GitHub Actions Workflow Security"

# Check for dangerous triggers
if compgen -G ".github/workflows/*.yml" > /dev/null 2>&1 || compgen -G ".github/workflows/*.yaml" > /dev/null 2>&1; then
  dangerous=$(grep -Erl 'pull_request_target|workflow_run' .github/workflows/ 2>/dev/null || true)
  if [[ -n "$dangerous" ]]; then
    check_warn "Dangerous triggers found (pull_request_target or workflow_run)" \
      "Review these files and consider safer alternatives:\n${dangerous//$'\n'/$'\n          '}"
  else
    check_pass "No dangerous workflow triggers detected"
  fi
else
  check_skip "No workflow files found in .github/workflows/"
fi

# Check action pinning with pinact
if command -v pinact &> /dev/null; then
  if pinact run --check 2>/dev/null; then
    check_pass "All GitHub Actions are SHA-pinned"
  else
    check_fail "Some GitHub Actions are not SHA-pinned" \
      "Run: pinact run"
  fi
else
  check_skip "pinact not installed — install from https://github.com/suzuki-shunsuke/pinact"
fi

# Check workflow permissions with zizmor
if command -v zizmor &> /dev/null; then
  findings=$(zizmor --format plain . 2>/dev/null || true)
  if [[ -z "$findings" ]]; then
    check_pass "zizmor found no workflow security issues"
  else
    count=$(echo "$findings" | wc -l)
    check_fail "zizmor found $count potential issues" \
      "Run: zizmor ."
  fi
else
  check_skip "zizmor not installed — install: pip install zizmor"
fi

# =====================================================================
# 2. Repository Security Settings
# =====================================================================
section "2. Repository Settings"

# Check branch protection on default branch
default_branch=$(gh api "repos/$REPO" --jq '.default_branch' 2>/dev/null || echo "main")
protection=$(gh api "repos/$REPO/branches/$default_branch/protection" 2>/dev/null || echo "")

if [[ -z "$protection" ]]; then
  check_fail "No branch protection on '$default_branch'" \
    "Enable branch protection or rulesets in repo Settings > Rules"
else
  check_pass "Branch protection enabled on '$default_branch'"

  # Check specific protections
  force_push=$(echo "$protection" | jq -r '.allow_force_pushes.enabled // "unknown"')
  if [[ "$force_push" == "false" ]]; then
    check_pass "Force pushes disabled on '$default_branch'"
  elif [[ "$force_push" == "true" ]]; then
    check_fail "Force pushes allowed on '$default_branch'" \
      "Disable force pushes in branch protection rules"
  fi

  pr_reviews=$(echo "$protection" | jq -r '.required_pull_request_reviews // empty')
  if [[ -n "$pr_reviews" ]]; then
    check_pass "Pull request reviews required"
  else
    check_warn "Pull request reviews not required" \
      "Require at least 1 review before merging"
  fi
fi

# Check tag protection
rulesets=$(gh api "repos/$REPO/rulesets" 2>/dev/null || echo "[]")
tag_rules=$(echo "$rulesets" | jq '[.[] | select(.conditions.ref_name.include[]? | test("refs/tags"))] | length')

if [[ "$tag_rules" -gt 0 ]]; then
  check_pass "Tag protection rulesets configured"
else
  check_warn "No tag protection rulesets found" \
    "Add tag rulesets to prevent tag deletion/modification. See templates/tag-rulesets.json"
fi

# =====================================================================
# 3. Security Policy & Documentation
# =====================================================================
section "3. Security Policy"

if [[ -f "SECURITY.md" || -f ".github/SECURITY.md" || -f "docs/SECURITY.md" ]]; then
  check_pass "SECURITY.md exists"
else
  check_fail "No SECURITY.md found" \
    "Add a security policy. See templates/SECURITY.md"
fi

# =====================================================================
# 4. Dependency Management
# =====================================================================
section "4. Dependency Management"

if [[ -f ".github/dependabot.yml" || -f ".github/dependabot.yaml" ]]; then
  check_pass "Dependabot configured"
elif [[ -f "renovate.json" || -f "renovate.json5" || -f ".renovaterc" || -f ".renovaterc.json" ]]; then
  check_pass "Renovate configured"
else
  check_fail "No automated dependency updates configured" \
    "Add .github/dependabot.yml or renovate.json. See templates/dependabot.yml"
fi

# Check for vulnerability alerts
if gh api "repos/$REPO/vulnerability-alerts" &>/dev/null; then
  check_pass "Vulnerability alerts enabled"
else
  check_warn "Could not verify vulnerability alerts (may require admin access)" \
    "Enable Dependabot alerts in repo Settings > Code security"
fi

# =====================================================================
# 5. Binary Artifacts
# =====================================================================
section "5. Binary Artifacts"

binaries=$(find . -not -path './.git/*' -not -path './node_modules/*' -not -path './.venv/*' \
  \( -name "*.exe" -o -name "*.dll" -o -name "*.so" -o -name "*.dylib" -o -name "*.bin" -o -name "*.wasm" \) \
  2>/dev/null || true)

if [[ -n "$binaries" ]]; then
  count=$(echo "$binaries" | wc -l)
  check_warn "$count binary artifact(s) found in repo" \
    "Binary artifacts can hide malicious code. Review:\n$(echo "$binaries" | head -10 | sed 's/^/          /')"
else
  check_pass "No binary artifacts detected"
fi

# =====================================================================
# 6. Secrets & Credentials
# =====================================================================
section "6. Secrets Hygiene"

# Check for common secret patterns in tracked files
secret_patterns='(PRIVATE.KEY|BEGIN RSA|BEGIN EC|BEGIN OPENSSH|password\s*=\s*["\x27][^"\x27]+|api_key\s*=\s*["\x27][^"\x27]+|secret_key\s*=\s*["\x27][^"\x27]+)'
secrets_found=$(git grep -lEi "$secret_patterns" -- ':!*.lock' ':!*.sum' ':!vendor/' 2>/dev/null || true)

if [[ -n "$secrets_found" ]]; then
  check_warn "Potential hardcoded secrets detected" \
    "Review these files for false positives:\n$(echo "$secrets_found" | head -10 | sed 's/^/          /')"
else
  check_pass "No obvious hardcoded secrets detected"
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo -e "${BOLD}Summary${NC}"
echo "  $(printf '%.0s─' {1..60})"
echo -e "  ${GREEN}Passed:${NC}  $pass"
echo -e "  ${RED}Failed:${NC}  $fail"
echo -e "  ${YELLOW}Warned:${NC}  $warn"
echo ""

if [[ $fail -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}Action required.${NC} Fix the failures above to harden your repo."
  exit 1
elif [[ $warn -gt 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}Good, but room to improve.${NC} Review the warnings above."
  exit 0
else
  echo -e "  ${GREEN}${BOLD}Looking solid.${NC} Keep it up."
  exit 0
fi
