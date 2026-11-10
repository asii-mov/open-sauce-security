<!-- open-sauce:start -->
## Open Sauce security baseline

These rules come from https://github.com/asii-mov/open-sauce-security and apply in any git repo with a GitHub remote.

### Always: when creating or editing GitHub Actions workflows
- Pin every third-party action to a full 40-character commit SHA with a version comment (`uses: owner/action@<sha> # v1.2.3`). Never use tags or branches.
- Declare top-level `permissions: {}` and grant each job only the scopes it needs.
- Set `persist-credentials: false` on `actions/checkout` unless the job must push.
- Don't use `pull_request_target` or `workflow_run` to check out or run PR code. Prefer `pull_request`.
- Never interpolate `${{ github.event.* }}` or other attacker-controllable context directly into `run:`. Pass it through `env:` instead.
- Don't cache in release or publish jobs. Use OIDC or trusted publishing instead of long-lived registry tokens, scope secrets to environments, and attest release artifacts.
- If `zizmor` or `pinact` is available, run it on changed workflows before finishing.

### Always: dependencies
- Before adding a dependency, consider maintenance, transitive dependency count and binary blobs, and prefer fewer dependencies. Never commit secrets, tokens or private keys.

### Once per session: baseline check
The baseline applies when the repo is on GitHub, is not a fork and is not archived, and I have admin or maintain permission (`gh repo view --json isFork,isArchived,viewerPermission`; if `gh` is unavailable, assume it applies only if I own the remote). It is skipped if the repo's AGENTS.md or CLAUDE.md contains `open-sauce: skip`.

When it applies, run a quick read-only check for these files: `.github/workflows/ci-security-audit.yml`, `.github/dependabot.yml` (or a Renovate config), and `SECURITY.md`. If any are missing, tell me in one line which ones and offer to run the Open Sauce setup. Don't make changes unless I say yes. If I say yes, or I ask you to "set up open sauce", download https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/agents/setup-prompt.md with `curl -fsSL` and follow it. Download every file it references from the same commit as that URL, not from `main`. Don't bring it up again in this session after I've answered.

This block is pinned to one commit. To update it, re-run `install-agent-instructions.sh`.
<!-- open-sauce:end -->
