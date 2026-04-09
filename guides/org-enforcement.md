# Org-Wide Enforcement Guide

This guide is for **organization admins** who want to enforce the Open Sauce toolkit (or similar security practices) across **every repo** in their GitHub organization — not just opt-in per repo.

GitHub gives you several layered mechanisms. Use them together: org settings for baseline defaults, org rulesets for per-branch/tag rules, and a continuous-enforcement tool for the gaps.

## Mechanism 1: Organization Settings (baseline defaults)

The fastest wins are org-level toggles that apply to all current and future repos. Enable these in **Organization Settings > Code security**:

| Setting | Effect | Notes |
|---------|--------|-------|
| **Require 2FA for everyone** | Blocks members without 2FA | Start with TOTP minimum; move to WebAuthn/passkeys-only when available |
| **Dependabot alerts** | Default-enable on all repos | Free on public, available on private |
| **Dependabot security updates** | Auto-PRs for vulnerable deps | Combine with cooldowns — see `templates/dependabot.yml` |
| **Secret scanning** | Scans for leaked credentials | Free on public repos |
| **Push protection** | Blocks pushes containing secrets | Enable as default for new AND existing repos |
| **Private vulnerability reporting** | Lets researchers report securely | Pairs with `SECURITY.md` |

Also under **Organization Settings > Actions > General**:

| Setting | Effect |
|---------|--------|
| **Allowed actions and reusable workflows** | Restrict to `Allow actions created by GitHub` + `Allow actions by Marketplace verified creators` + explicit allowlist of trusted SHAs |
| **Workflow permissions** | Default to `Read repository contents and packages permissions` (not read/write) |
| **Fork pull request workflows** | Require approval for first-time contributors |

Apply these once and they cover every repo, including new ones.

## Mechanism 2: Organization Rulesets (branch, tag, push, repo)

Rulesets are the modern replacement for branch protection. Unlike per-repo branch protection, **organization rulesets apply across all repos** you target (via name patterns, topics, visibility, or `~ALL`).

Four target types are supported:
- **branch** — enforce PR reviews, status checks, required workflows, linear history
- **tag** — prevent tag deletion/modification (release immutability)
- **push** — block file patterns, oversized files, secrets
- **repository** — control repo creation/deletion/transfer

### Apply the toolkit rulesets org-wide

The repo-level templates (`templates/branch-rulesets.json`, `templates/tag-rulesets.json`) are also importable at the org level — just post them to the org endpoint and add `conditions.repository_name`:

```bash
# Create an org-wide branch ruleset that protects 'main' on every repo
cat templates/branch-rulesets.json | jq '. + {
  conditions: {
    ref_name: .conditions.ref_name,
    repository_name: {include: ["~ALL"], exclude: []}
  }
}' > /tmp/org-branch-ruleset.json

gh api orgs/YOUR_ORG/rulesets --method POST --input /tmp/org-branch-ruleset.json
```

The same pattern works for the tag ruleset. You can scope more narrowly with `repository_name.include: ["*-prod", "api-*"]` or by repo topic: `conditions.repository_property`.

### Require a specific workflow on all repos

The `workflows` rule type makes a given workflow file a **required status check** on every PR in the targeted repos. This is how you force `ci-security-audit.yml` (or any workflow) to run without asking maintainers to opt in.

```json
{
  "name": "Require CI security audit",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []},
    "repository_name": {"include": ["~ALL"], "exclude": []}
  },
  "rules": [
    {
      "type": "workflows",
      "parameters": {
        "workflows": [
          {
            "path": ".github/workflows/ci-security-audit.yml",
            "ref": "refs/heads/main",
            "repository_id": 0
          }
        ]
      }
    }
  ]
}
```

The trick: put the workflow file in a **central admin repo** that every other repo references. Set `repository_id` to that admin repo's numeric ID (get it via `gh api repos/YOUR_ORG/admin-repo --jq .id`). Every repo in the ruleset scope will then be required to pass that workflow before merging, even though the workflow file itself only lives in one place.

## Mechanism 3: Bulk Setup for Per-Repo Files

Rulesets cover branch/tag/push rules and required workflows, but they **can't** push files (SECURITY.md, dependabot.yml) into repos. For those, use a one-time bulk script:

```bash
#!/usr/bin/env bash
# Bulk-apply Open Sauce templates to every repo in an org.
# Requires: gh (authenticated with admin:org), jq

ORG="YOUR_ORG"
TOOLKIT_DIR="$(pwd)"  # path to open-sauce checkout

gh api "orgs/$ORG/repos" --paginate --jq '.[].name' | while read -r repo; do
  echo "=== $repo ==="
  tmpdir=$(mktemp -d)
  gh repo clone "$ORG/$repo" "$tmpdir" -- --depth 1 --quiet
  cd "$tmpdir"

  # Drop in templates if missing
  [[ -f SECURITY.md ]] || cp "$TOOLKIT_DIR/templates/SECURITY.md" SECURITY.md
  [[ -f .github/dependabot.yml ]] || { mkdir -p .github; cp "$TOOLKIT_DIR/templates/dependabot.yml" .github/dependabot.yml; }

  if ! git diff --quiet; then
    branch="open-sauce-baseline-$(date +%s)"
    git checkout -b "$branch"
    git add -A
    git commit -m "Add Open Sauce security baseline"
    git push -u origin "$branch"
    gh pr create --title "Security baseline (Open Sauce)" --body "Adds SECURITY.md and dependabot.yml from the org security toolkit."
  fi

  cd - > /dev/null
  rm -rf "$tmpdir"
done
```

This runs once and opens a PR in every repo missing the baseline. Maintainers can review and merge.

## Mechanism 4: Continuous Enforcement

Org settings and rulesets cover **static** state — but repos drift. A maintainer can delete `SECURITY.md`, disable Dependabot, or commit a binary. For continuous enforcement you need a tool that monitors and either reports or auto-fixes.

Two options:

### OpenSSF Allstar

[Allstar](https://github.com/ossf/allstar) is a GitHub App that monitors every repo in your org and files an issue when a policy is violated. Policies it checks:

- Branch protection present
- No binary artifacts committed
- `CODEOWNERS` exists
- No outside collaborators with admin
- `SECURITY.md` exists
- No dangerous Actions triggers
- OpenSSF Scorecard score above threshold
- GitHub Actions config meets org standards
- At least one repo admin

Install the OpenSSF-managed app and opt into policies via a central `.allstar` repo. It runs continuously and surfaces drift as issues, not PR checks.

### GitHub safe-settings

[safe-settings](https://github.com/github/safe-settings) is GitHub's own **Policy-as-Code** app. You define org/suborg/repo settings in YAML files in a central admin repo, and the app reconciles them on every repo — branch protection, rulesets, teams, collaborators, metadata.

Use safe-settings if you want declarative settings-as-code for everything, not just security. Use Allstar if you just want continuous drift detection for security policy specifically. They can coexist.

## Recommended Rollout

For a mid-sized org (~20–200 repos):

1. **Week 1**: Enable org-level baseline settings (2FA, Dependabot, secret scanning, push protection, action allowlist, default workflow permissions).
2. **Week 2**: Apply org rulesets for branch protection (`~ALL` default branch) and tag protection (`~ALL` `refs/tags/v*`).
3. **Week 3**: Create a central admin repo containing `ci-security-audit.yml` and add a workflow-requiring ruleset that points to it. Communicate to maintainers.
4. **Week 4**: Run the bulk template script to open baseline PRs for `SECURITY.md` and `dependabot.yml` across all repos.
5. **Week 5+**: Install Allstar (or safe-settings) for continuous enforcement. Triage the issues it files.

Rolling out in this order gives you coverage fast (org settings take effect immediately) while avoiding a flood of failing CI on day one (rulesets come after the workflow is available).

## Limits to know about

- **Org rulesets require GitHub Team or Enterprise.** Free/Pro accounts can only set rulesets per repo.
- **Required workflows via rulesets** need the workflow file to live in an accessible repo (public, or a private repo the ruleset's target repos can read).
- **Rulesets can be bypassed** by users you list in `bypass_actors`. Keep that list empty or limited to break-glass accounts.
- **Enforcement mode** can be `active` (enforce), `evaluate` (log only, Enterprise only), or `disabled`. Start in evaluate mode to find violations before you block merges — but only if you have Enterprise.

## Verification

After rolling out, verify:

```bash
# Are the rulesets active?
gh api orgs/YOUR_ORG/rulesets --jq '.[] | {name, target, enforcement}'

# Which repos still lack SECURITY.md?
gh api "orgs/YOUR_ORG/repos" --paginate --jq '.[].name' | while read -r repo; do
  gh api "repos/YOUR_ORG/$repo/contents/SECURITY.md" &>/dev/null || echo "missing: $repo"
done

# Org-wide 2FA status
gh api "orgs/YOUR_ORG" --jq '{two_factor_required: .two_factor_requirement_enabled}'
```

Run `scripts/audit.sh --repo YOUR_ORG/SOME_REPO` against a sample of repos to confirm the baseline is actually applied.
