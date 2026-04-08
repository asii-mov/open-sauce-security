# OSS Maintainer Security Guide

This guide covers security practices that require human judgment and can't be fully automated. For the automated parts, see the [workflows](../workflows/) and [audit script](../scripts/audit.sh).

This draws heavily from [Astral's open source security practices](https://astral.sh/blog/open-source-security-at-astral), [OpenSSF Scorecard](https://securityscorecards.dev/), and [SLSA](https://slsa.dev/).

---

## Account Security

### Enforce strong 2FA across your org

Every account with write access is a potential entry point. A compromised maintainer account can push malicious code, modify releases, or change CI workflows.

**What to do:**
- Require 2FA for all org members (GitHub org Settings > Authentication security)
- Set the minimum to TOTP (time-based one-time password)
- Prefer passkeys or hardware security keys (WebAuthn/FIDO2) — these are phishing-resistant
- When GitHub adds the option to require phishing-resistant 2FA only, enable it

### Limit privileged access

**What to do:**
- Keep the number of org admins to the absolute minimum (2-3 people)
- Most contributors should have write access only to repos they work on
- Review org member roles quarterly
- Use GitHub teams to scope permissions rather than granting broad repo access

**Why it matters:** An admin can disable branch protections, delete rulesets, and modify org-level settings. Fewer admins = smaller blast radius.

---

## CI/CD Security

### Avoid dangerous workflow triggers

`pull_request_target` and `workflow_run` triggers run with elevated privileges and can be exploited by malicious PRs from forks.

**What to do:**
- Use `pull_request` instead of `pull_request_target` wherever possible
- If you must use `pull_request_target`, never checkout the PR's head ref — only the base
- Audit any `workflow_run` triggers to ensure they don't pass untrusted data to privileged contexts
- Consider moving privileged operations (commenting on PRs, labeling) to a GitHub App instead

**Why it matters:** A malicious fork can submit a PR that modifies workflow files. With `pull_request_target`, those modifications run with write access to your repo and access to your secrets.

### Use a GitHub App for privileged operations

Operations like commenting on external PRs, managing labels, or posting to external services should not run inside GitHub Actions where they mix with untrusted code.

**What to do:**
- Create a GitHub App with only the permissions it needs
- Host it on a small server or serverless function
- Use it for: PR comments/labels, issue triage, notifications to Slack/Discord
- Libraries like [gidgethub](https://github.com/gidgethub/gidgethub) (Python) or [octokit](https://github.com/octokit/octokit.js) (JS) simplify development
- Treat the app's code with the same security rigor as production code

**Why it matters:** A GitHub App runs independently of your CI/CD pipeline. Even if a workflow is compromised, the app's credentials and logic remain isolated.

### Review action dependencies for mutability

SHA-pinning your actions (which the `ci-security-audit.yml` workflow enforces) protects against tag manipulation, but some actions pull mutable resources at runtime.

**What to do:**
- Read the source of third-party actions before adopting them
- Check if they download binaries at runtime — if so, verify they use checksums
- Prefer actions that are well-maintained and have a security policy
- Consider vendoring critical actions into your repo

**Why it matters:** An action pinned to a SHA is immutable, but if that action's code downloads `latest` from an external URL, pinning gives you a false sense of security.

---

## Secrets Management

### Scope secrets to environments

**What to do:**
- Never use org-level secrets if you can avoid it
- Prefer environment-scoped secrets over repo-level secrets
- Create separate environments (`release`, `staging`, `production`) with different secrets
- Restrict which branches can deploy to each environment (main only for release)
- Require manual approval for environments with publishing credentials

**Why it matters:** If a CI job is compromised, environment-scoped secrets limit what the attacker can access. A test job shouldn't be able to publish to your package registry.

### Eliminate long-lived credentials

**What to do:**
- Use Trusted Publishing (OIDC) for PyPI, npm, and crates.io — no stored tokens needed
- For other registries, use short-lived tokens where possible
- Rotate any remaining long-lived tokens on a regular schedule
- Audit which secrets exist and who/what has access to them

**Why it matters:** A leaked long-lived token gives an attacker persistent access. OIDC tokens are scoped to a specific workflow run and expire immediately.

---

## Release Security

### Require multi-person approval

**What to do:**
- Set up a `release` deployment environment with required reviewers
- The person who triggers the release should not be the only approver
- Use a separate privileged account for approval (not the same account that pushed the code)
- For high-value projects, consider a `release-gate` pattern with a mediator GitHub App

**Why it matters:** If a single account is compromised, multi-person approval prevents that account from unilaterally publishing a malicious release.

### Enable immutable releases

**What to do:**
- Turn on "Immutable releases" in your repo settings (if available)
- Use tag protection rulesets to prevent tag deletion/modification (see `templates/tag-rulesets.json`)
- Gate tag creation on successful deployment via rulesets

**Why it matters:** An attacker who gains write access could replace a release artifact with a backdoored version. Immutable releases prevent post-publication tampering.

### Disable caching in release workflows

**What to do:**
- Do not use `actions/cache` or similar caching in your release/publish jobs
- Caching is fine for test/lint/CI jobs — just not for builds that produce release artifacts

**Why it matters:** Cache poisoning attacks can inject malicious code into cached build artifacts. If a release build uses a poisoned cache, the published artifact is compromised.

### Sign and attest your releases

**What to do:**
- Use [Sigstore](https://www.sigstore.dev/) attestations for binary releases (the `release-hardened.yml` workflow includes this)
- For Docker images, use `docker buildx build --attest type=provenance`
- For macOS/Windows binaries, pursue code signing with official developer certificates
- Document how users can verify your releases

**Why it matters:** Attestations let users verify that a release artifact was actually produced by your official CI/CD pipeline, not by a compromised account uploading a modified binary.

---

## Dependency Management

### Be conservative about adding dependencies

**What to do:**
- Evaluate new dependencies before adding: Is the project well-maintained? Does it have a security policy? How many transitive dependencies does it pull in?
- Prefer dependencies with fewer transitive deps
- Remove dependencies you no longer use
- Avoid dependencies that include binary blobs
- Disable unnecessary features/optional dependencies

**Why it matters:** Every dependency is an attack surface. The `event-stream` incident was a malicious dependency injected via a small, seemingly-harmless package.

### Use dependency cooldowns

**What to do:**
- Configure Dependabot or Renovate to wait 3-7 days before opening PRs for new releases
- This gives time for the community to catch compromised packages before you adopt them
- Renovate: set `stabilityDays: 3` in your config
- Dependabot: doesn't have native cooldowns, but you can review PRs on a weekly cadence instead of immediately merging

**Why it matters:** Many supply chain attacks are discovered within hours or days. A short delay between a package release and your adoption dramatically reduces your exposure window.

### Invest in upstream relationships

**What to do:**
- Contribute security improvements to your dependencies (CI hardening, action pinning, etc.)
- Report vulnerabilities responsibly through your dependencies' security channels
- Join relevant security working groups (e.g., Python Packaging Authority, Rust Security Response WG)
- Consider funding critical dependencies through programs like the [Astral OSS Fund](https://astral.sh/blog/astral-oss-fund) or [GitHub Sponsors](https://github.com/sponsors)

**Why it matters:** Your security is only as strong as your weakest dependency. Helping your dependencies get more secure directly improves your own security posture.

---

## Incident Response

### Have a plan before you need one

**What to do:**
- Document what to do if a maintainer account is compromised
- Document what to do if a dependency is found to be malicious
- Know how to yank/unpublish a release from your package registry
- Know how to rotate all secrets and tokens quickly
- Keep a list of who has admin access and how to reach them urgently

**Why it matters:** When an incident happens, you don't have time to figure out the process. Having a playbook ready turns a crisis into a checklist.

---

## Checklist Summary

| Practice | Automated? | How |
|----------|-----------|-----|
| SHA-pin all actions | Yes | `ci-security-audit.yml` + pinact |
| Audit workflows for vulns | Yes | `ci-security-audit.yml` + zizmor |
| OpenSSF Scorecard | Yes | `scorecard.yml` |
| Block vulnerable dependencies | Yes | `dependency-review.yml` |
| Hardened releases with attestation | Yes | `release-hardened.yml` |
| Branch/tag protection | Semi | `templates/*.json` (import via gh CLI) |
| Dependabot config | Semi | `templates/dependabot.yml` (copy to repo) |
| Security policy | Semi | `templates/SECURITY.md` (copy to repo) |
| Audit repo posture | Semi | `scripts/audit.sh` (run manually) |
| Enforce strong 2FA | Manual | GitHub org settings |
| Limit privileged access | Manual | Org role review |
| Scope secrets to environments | Manual | GitHub environment config |
| Use Trusted Publishing (OIDC) | Manual | Registry-specific setup |
| Multi-person release approval | Manual | GitHub environment protection |
| Dependency cooldowns | Manual | Renovate/Dependabot config |
| Review action source code | Manual | Human judgment |
| Incident response plan | Manual | Write it down |
