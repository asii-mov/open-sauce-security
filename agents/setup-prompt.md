Set up Open Sauce security hardening (https://github.com/asii-mov/open-sauce-security) in the repository in my current working directory. Follow the steps below in order and work autonomously, except where a step says to ask me.

## Source

- Pin one commit for this whole run. If this prompt came from a URL that contains a commit SHA, use that SHA. Otherwise resolve `main` once with `git ls-remote https://github.com/asii-mov/open-sauce-security refs/heads/main`. Call the result `SHA` and mention it in the final report.
- Download every Open Sauce file from `https://raw.githubusercontent.com/asii-mov/open-sauce-security/SHA/<path>` using `curl -fsSL`. Never use `main` in a download URL, so all files come from the same commit.
- If the network is blocked, ask me to allow it. Never write these files from memory: they contain SHA-pinned action references that must be exact.

## Ground rules

- Do all file changes on a new local branch named `open-sauce/hardening`.
- Never silently overwrite an existing file. If a file serving the same purpose already exists (a workflow with the same name, `dependabot.yml`, a Renovate config, `SECURITY.md`, a release workflow), merge the missing parts in, or leave it alone and tell me why.
- Do not push, open a pull request, or change any GitHub repository setting unless I approve it in Step 1.
- Do not change the behavior of the repo's existing workflows. Pinning their actions to commit SHAs is the one exception.
- Be idempotent: if something from a step is already in place, say so and move on.

## Step 0: Inspect (read-only)

1. Confirm this is a git repo with a GitHub remote. Record `OWNER/REPO`, the default branch, and whether the repo is public, private or a fork. Use `gh repo view --json nameWithOwner,defaultBranchRef,visibility,isFork,viewerPermission` if `gh` is installed and authenticated, otherwise parse `git remote -v`. If there is no GitHub remote, stop and tell me that Open Sauce only applies to GitHub repos.
2. Detect package ecosystems and the directories they live in (monorepos may have several): `package.json` = npm, `pyproject.toml`/`requirements*.txt`/`setup.py` = pip (`uv.lock` = uv), `Cargo.toml` = cargo, `go.mod` = gomod, `Dockerfile` = docker, `Gemfile` = bundler, `composer.json` = composer, `pom.xml` = maven, `build.gradle*` = gradle, `*.csproj`/`*.sln` = nuget, `.github/workflows/` = github-actions. Skip `node_modules/`, `vendor/`, `.venv/` and similar.
3. Check what already exists: `.github/workflows/*`, `.github/dependabot.y*ml`, Renovate config, `SECURITY.md` (root, `.github/` or `docs/`), any release or publish workflow.
4. Work out whether the project publishes releases: `v*` tags, an existing release workflow, or publish configuration (npm `publishConfig`, PyPI or crates.io metadata, GoReleaser, and so on).

## Step 1: Ask me once

Show a short summary of what you found and the plan, then ask all of these in a single message (lettered, with your recommended default for each):

a. Security contact for `SECURITY.md`: an email address, or "GitHub private vulnerability reporting only".
b. Add the hardened release workflow? Recommend yes only if the project publishes releases.
c. Apply GitHub settings with `gh` (needs admin)? That is: branch ruleset, tag ruleset, Dependabot alerts, private vulnerability reporting, and a `release` environment if (b) is yes. If I'm the only maintainer, warn that the branch ruleset's required approving review would block me from merging my own PRs, and offer to set `required_approving_review_count` to 0 and `require_last_push_approval` to false. That still requires PRs and still blocks force pushes.
d. When done: leave the changes uncommitted, commit them on the branch, or commit, push and open a PR?
e. Install the Open Sauce standing instructions, so that Codex and Claude Code apply this baseline to every applicable repo I work in? Options (multi-select): Codex global (`$CODEX_HOME/AGENTS.md`, default `~/.codex/AGENTS.md`), Claude Code global (`~/.claude/CLAUDE.md`), this repo's `AGENTS.md`, this repo's `CLAUDE.md`, or none.

If I don't answer (for example in a non-interactive run), use these defaults: (a) GitHub reporting only, (b) no, (c) no, (d) leave uncommitted, (e) none.

## Step 2: CI security workflows

1. `git checkout -b open-sauce/hardening`, or switch to that branch if it already exists.
2. Download each of these into `.github/workflows/`:
   - `workflows/ci-security-audit.yml`: zizmor and pinact.
   - `workflows/dependency-review.yml`: blocks vulnerable or restrictively licensed dependencies in PRs. On private repos, note that it needs GitHub Advanced Security.
   - `workflows/scorecard.yml`: public repos only, so skip it for private repos. If the default branch isn't `main`, change the `push.branches` entry to match.
3. Pin every action in the repo's existing workflows to a full commit SHA with a version comment (`uses: owner/action@<40-char-sha> # vX.Y.Z`); otherwise the new pinact check fails. Prefer `pinact run` if it's installed. Otherwise resolve each tag with `git ls-remote --tags https://github.com/OWNER/ACTION 'refs/tags/vX*'`, and for annotated tags use the peeled `^{}` SHA. Leave local actions (`./...`) and `docker://` refs alone.
4. If zizmor is available (`zizmor`, `uvx zizmor` or `pipx run zizmor`), run it on `.github/workflows/`. Report the findings in existing workflows with a proposed fix for each, but don't apply those fixes.

## Step 3: Dependabot

- If Renovate is configured, leave it in place and skip this step.
- If `.github/dependabot.yml` exists, add only what's missing: a `github-actions` entry, an entry for each detected ecosystem, and `cooldown` settings. Keep existing entries unchanged.
- Otherwise download `templates/dependabot.yml` to `.github/dependabot.yml`, keep the `github-actions` entry, uncomment the detected ecosystems, delete the commented-out ones that don't apply, and set `directory` (or `directories` for several) to the real manifest paths. For a detected ecosystem the template doesn't include, add an entry following the same pattern. Note that `github-actions` only supports `cooldown.default-days`.
- Check that the result parses as YAML.

## Step 4: Security policy

If there is no `SECURITY.md`, download `templates/SECURITY.md` to the repo root. Replace the relative advisories link with `https://github.com/OWNER/REPO/security/advisories/new`, and either set the email from 1a or remove the email option. Leave an existing policy unchanged.

## Step 5: Release workflow (only if 1b is yes)

- If a release or publish workflow already exists, don't replace it. Review it against the header comment of `workflows/release-hardened.yml` (minimal per-job permissions, a `release` environment, no caching, OIDC or trusted publishing, attestation) and list the gaps with proposed edits.
- Otherwise download `workflows/release-hardened.yml` to `.github/workflows/release.yml`, then fill in the build and publish steps for the detected ecosystem using the commented examples in the file. Use trusted publishing (OIDC) instead of long-lived tokens where the registry supports it. Keep every action SHA-pinned.

## Step 6: GitHub settings (only if 1c is yes)

Use `gh api`. Before each change, read the current state and skip it if it's already applied, so nothing gets duplicated. Download any JSON to a temp directory, not into the repo.
- Branch ruleset: `templates/branch-rulesets.json`. Set `conditions.ref_name.include` to `["~DEFAULT_BRANCH"]` and apply the solo-maintainer adjustment if I chose it. `gh api repos/OWNER/REPO/rulesets --method POST --input <file>`.
- Tag ruleset: `templates/tag-rulesets.json`, using the same call.
- Dependabot alerts: `gh api -X PUT repos/OWNER/REPO/vulnerability-alerts`.
- Private vulnerability reporting (public repos): `gh api -X PUT repos/OWNER/REPO/private-vulnerability-reporting`.
- `release` environment (if 1b is yes): create it with me as a required reviewer. Restrict deployments to a custom tag policy `v*` (`deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}`, then POST `{"name":"v*","type":"tag"}` to `.../environments/release/deployment-branch-policies`). The release workflow runs on tag pushes, so a branch-only policy would block it.
If a call fails because I lack permission, record it as a manual step and continue.

## Step 7: Verify

- Download `scripts/audit.sh` to a temp directory (not the repo) and run it from the repo root with `bash <tmp>/audit.sh --repo OWNER/REPO`. Checks that need tools I don't have (gh, pinact, zizmor) report SKIP; that's fine.
- Check that every new or edited YAML file parses.
- Run `git diff --stat` and review the full diff for mistakes.

## Step 8: Commit / PR (as chosen in 1d)

- Commit message: `chore(security): add Open Sauce hardening baseline`, with a body listing what was added.
- Push and open a PR only if I chose that. Write the PR body with the summary from Step 10.

## Step 9: Standing instructions (as chosen in 1e)

1. Download `scripts/install-agent-instructions.sh` at `SHA` to a temp directory (not the repo), read it, then run it from the repo root with `--ref SHA` and one flag for each target I chose: `--codex`, `--claude`, `--repo-agents`, `--repo-claude`. It pins the block to that commit, updates an existing block in place, never touches anything outside the `<!-- open-sauce:start -->`/`<!-- open-sauce:end -->` markers, and makes a repo `CLAUDE.md` import `AGENTS.md` rather than duplicating the block.
2. Don't hand-edit the instruction files. If the script can't run, tell me and stop this step.
3. Repo-level files are part of the commit in Step 8. Global files live outside the repo, so tell me exactly which files changed and which commit they're pinned to.

## Step 10: Report

Finish with a concise summary:
- **Added or changed:** each file, with one line on what it does.
- **GitHub settings applied:** or "none".
- **Open Sauce version:** the pinned `SHA`.
- **Audit result:** pass/fail/warn counts and any remaining failures.
- **Needs a human:** what's left from https://github.com/asii-mov/open-sauce-security/blob/main/guides/maintainer-guide.md that applies to this repo, for example 2FA, more release reviewers, trusted publishing setup on the registry, scoping secrets to environments, and enabling the dependency graph if it's off.
