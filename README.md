# Open Sauce

Drop-in security hardening for open source projects.

A collection of GitHub Actions workflows, templates, and guides that help OSS maintainers protect their projects from supply chain attacks. Inspired by [Astral's open source security practices](https://astral.sh/blog/open-source-security-at-astral), [OpenSSF Scorecard](https://securityscorecards.dev/), and [SLSA](https://slsa.dev/).

## Guides

- **[Maintainer Guide](guides/maintainer-guide.md)** — what to do for things that can't be automated: 2FA, access control, secrets, releases, dependencies, incident response.
- **[Org Enforcement Guide](guides/org-enforcement.md)** — for org admins: how to enforce this toolkit across **every repo** in your organization using org rulesets, required workflows, and continuous-enforcement tools like Allstar.

## Set Up With an AI Agent (Codex / Claude Code)

The fastest path: let your coding agent do the setup. It inspects the repo, asks you a few questions in one go (security contact, release workflow, GitHub settings, commit/PR), then adds the workflows, Dependabot config and security policy, pins existing actions, runs the audit and reports back.

**Option A: paste a prompt.** Open [`agents/setup-prompt.md`](agents/setup-prompt.md), click **Copy raw file**, and paste it into Codex or Claude Code from the root of your repo. Or launch it straight from your shell:

```bash
claude "$(curl -fsSL https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/agents/setup-prompt.md)"
```

```bash
codex "$(curl -fsSL https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/agents/setup-prompt.md)"
```

**Option B: apply it to every repo you work in.** Install the Open Sauce [standing instructions](agents/open-sauce-instructions.md) into the instruction file your agent always loads. After that, the agent:

- follows hardened-CI rules whenever it writes or edits workflows (SHA-pinned actions, least-privilege `permissions`, no `pull_request_target` footguns, no script injection);
- does a quick baseline check once per session in each applicable repo (on GitHub, not a fork, not archived, and you have admin or maintain access) and offers to run the setup if anything is missing;
- runs the full setup when you say "set up open sauce".

The last step of the setup prompt (Option A) offers to install these for you. To install them yourself:

```bash
curl -fsSL https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/scripts/install-agent-instructions.sh -o install-agent-instructions.sh
```

```bash
bash install-agent-instructions.sh --global
```

| Flag | Writes to | Applies to |
|------|-----------|------------|
| `--codex` | `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) | every Codex session |
| `--claude` | `~/.claude/CLAUDE.md` (or `$CLAUDE_CONFIG_DIR/CLAUDE.md`) | every Claude Code session |
| `--global` | both of the above | every session in either agent |
| `--repo-agents` | `./AGENTS.md` | this repo, for anyone using an AGENTS.md-aware agent |
| `--repo-claude` | `./CLAUDE.md` (imports `AGENTS.md` if it has the block) | this repo, Claude Code |

The block sits between `<!-- open-sauce:start -->` and `<!-- open-sauce:end -->` markers. Re-running updates it in place, `--remove` takes it out, and nothing else in the file is touched. To opt a single repo out, add `open-sauce: skip` to its `AGENTS.md` or `CLAUDE.md`.

> **Always pinned.** The installer never writes `main` into your instruction files. It resolves the current `main` commit (or the `--ref <sha|tag|branch>` you pass, if you want a version you've reviewed), pins both the instructions and the setup prompt they link to at that commit, and prints the SHA. A later push to this repo can't change what your agent follows. To pick up updates, including refreshed action pins, re-run the installer.

## Quick Start (manual)

Run these from the root of your repo. They download from `main`; swap `main` for a commit SHA in `BASE` to pin a version you've reviewed.

```bash
BASE=https://raw.githubusercontent.com/asii-mov/open-sauce-security/main
```

### 1. Add the CI workflows

```bash
mkdir -p .github/workflows
curl -fsSL "$BASE/workflows/ci-security-audit.yml" -o .github/workflows/ci-security-audit.yml   # zizmor + pinact
curl -fsSL "$BASE/workflows/scorecard.yml" -o .github/workflows/scorecard.yml                   # OpenSSF Scorecard (public repos)
curl -fsSL "$BASE/workflows/dependency-review.yml" -o .github/workflows/dependency-review.yml   # dependency review
```

The pinact check fails until every action in your existing workflows is pinned to a commit SHA. Run `pinact run` to pin them. Scorecard runs on pushes to `main`, so change `push.branches` in `scorecard.yml` if your default branch has a different name.

### 2. Set up release hardening

Copy the release workflow, then customize its build and publish steps for your project:

```bash
curl -fsSL "$BASE/workflows/release-hardened.yml" -o .github/workflows/release.yml
```

Then in your repo's GitHub Settings:
1. Create a `release` deployment environment
2. Add required reviewers
3. Restrict deployments to `v*` tags (Deployment branches and tags → add a tag rule). The workflow runs on tag pushes, so a branch-only policy would block it.

### 3. Add templates

```bash
# Security policy: edit the contact details after downloading
curl -fsSL "$BASE/templates/SECURITY.md" -o SECURITY.md

# Dependabot: uncomment the ecosystems you use
curl -fsSL "$BASE/templates/dependabot.yml" -o .github/dependabot.yml

# Branch and tag protection rulesets (needs gh with admin access)
curl -fsSL "$BASE/templates/branch-rulesets.json" -o /tmp/branch-rulesets.json
curl -fsSL "$BASE/templates/tag-rulesets.json" -o /tmp/tag-rulesets.json
gh api repos/OWNER/REPO/rulesets --method POST --input /tmp/branch-rulesets.json
gh api repos/OWNER/REPO/rulesets --method POST --input /tmp/tag-rulesets.json
```

> **Solo maintainer?** The branch ruleset requires one approving review from someone other than the last pusher, so you couldn't merge your own PRs. Before importing it, set `required_approving_review_count` to `0` and `require_last_push_approval` to `false`. PRs are still required and force pushes are still blocked.

### 4. Run the audit

Check your repo's current security posture (needs `gh`, `git` and `jq`; pinact and zizmor are optional):

```bash
curl -fsSL "$BASE/scripts/audit.sh" -o /tmp/open-sauce-audit.sh
```

```bash
bash /tmp/open-sauce-audit.sh
```

## What's Inside

### Automated (workflows you drop in)

| Workflow | What it does |
|----------|-------------|
| [`ci-security-audit.yml`](workflows/ci-security-audit.yml) | Runs [zizmor](https://github.com/woodruffw/zizmor) and [pinact](https://github.com/suzuki-shunsuke/pinact) to catch workflow vulnerabilities and unpinned actions |
| [`scorecard.yml`](workflows/scorecard.yml) | Runs [OpenSSF Scorecard](https://securityscorecards.dev/) and publishes results to GitHub Security tab |
| [`dependency-review.yml`](workflows/dependency-review.yml) | Blocks PRs that add vulnerable or restrictively-licensed dependencies |
| [`release-hardened.yml`](workflows/release-hardened.yml) | Release template with minimal permissions, Sigstore attestation, manual approval gate, no caching |

### Semi-automated (templates you import)

| Template | What it does |
|----------|-------------|
| [`SECURITY.md`](templates/SECURITY.md) | Security vulnerability reporting policy |
| [`branch-rulesets.json`](templates/branch-rulesets.json) | Branch protection for `main`/`master`: no deletion, no force-push, PRs with an approving review, resolved threads |
| [`tag-rulesets.json`](templates/tag-rulesets.json) | Tag protection: prevent deletion and modification of release tags |
| [`dependabot.yml`](templates/dependabot.yml) | Automated dependency updates with grouped PRs and release cooldowns |

### Manual (guides)

| Guide | Audience | What it covers |
|-------|----------|---------------|
| [`maintainer-guide.md`](guides/maintainer-guide.md) | Repo maintainers | 2FA enforcement, access control, secrets management, dependency review, release approval, incident response |
| [`org-enforcement.md`](guides/org-enforcement.md) | Org admins | Applying this toolkit across **every** repo in an org: org rulesets, required workflows, Allstar, safe-settings, bulk setup scripts |

### AI agent setup

| File | What it does |
|------|-------------|
| [`setup-prompt.md`](agents/setup-prompt.md) | Paste-in prompt for Codex or Claude Code that sets up the full baseline in the current repo |
| [`open-sauce-instructions.md`](agents/open-sauce-instructions.md) | Standing instructions for `AGENTS.md` / `CLAUDE.md`: hardened-CI rules plus a once-per-session baseline check |
| [`install-agent-instructions.sh`](scripts/install-agent-instructions.sh) | Installs or updates those instructions globally (Codex, Claude Code) or per repo |

### Local audit

| Script | What it does |
|--------|-------------|
| [`audit.sh`](scripts/audit.sh) | Checks your repo for: unpinned actions, workflow vulnerabilities, missing branch protection, missing SECURITY.md, missing dependency updates, binary artifacts, hardcoded secrets |

## Why This Exists

Open source supply chain attacks are increasing in frequency and sophistication:

- **tj-actions/changed-files (2025):** an attacker rewrote the action's version tags to point at malicious code that dumped CI secrets into build logs. That affected every repo referencing a tag instead of a commit SHA.
- **Ultralytics (2024):** a `pull_request_target` workflow ran attacker-controlled branch names in a shell. Together with cache poisoning, that led to malicious releases on PyPI.
- **xz-utils (2024):** a long-running social-engineering campaign gave an attacker maintainer access, which they used to ship a backdoor in release tarballs.
- **Codecov (2021):** attackers modified the Bash uploader script that CI pipelines downloaded without checksum verification. For about two months it sent the credentials in customers' CI environments to the attackers.
- **event-stream (2018):** a new maintainer of a popular npm package added a malicious dependency that targeted cryptocurrency wallets.

Most of these attacks exploited gaps in practices that are straightforward to fix: unpinned dependencies, overly-permissive CI, missing release controls, weak account security.

This project packages those fixes into forms that are easy to adopt.

## References

- [Open Source Security at Astral](https://astral.sh/blog/open-source-security-at-astral) — comprehensive writeup of Astral's security practices
- [OpenSSF Scorecard](https://securityscorecards.dev/) — automated security assessment for open source projects
- [SLSA](https://slsa.dev/) — Supply-chain Levels for Software Artifacts framework
- [zizmor](https://github.com/woodruffw/zizmor) — GitHub Actions static analysis
- [pinact](https://github.com/suzuki-shunsuke/pinact) — GitHub Actions SHA-pinning tool
- [Sigstore](https://www.sigstore.dev/) — Keyless signing and verification for software artifacts
- [OpenSSF Guides](https://openssf.org/resources/guides/) — Security guides for open source developers
