# Open Sauce

Drop-in security hardening for open source projects.

A collection of GitHub Actions workflows, templates, and guides that help OSS maintainers protect their projects from supply chain attacks. Inspired by [Astral's open source security practices](https://astral.sh/blog/open-source-security-at-astral), [OpenSSF Scorecard](https://securityscorecards.dev/), and [SLSA](https://slsa.dev/).

## Guides

- **[Maintainer Guide](guides/maintainer-guide.md)** — what to do for things that can't be automated: 2FA, access control, secrets, releases, dependencies, incident response.
- **[Org Enforcement Guide](guides/org-enforcement.md)** — for org admins: how to enforce this toolkit across **every repo** in your organization using org rulesets, required workflows, and continuous-enforcement tools like Allstar.

## Quick Start

### 1. Add the CI workflows

Copy the workflows you want into your repo's `.github/workflows/` directory:

```bash
# Security audit (zizmor + pinact)
curl -o .github/workflows/ci-security-audit.yml \
  https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/.github/workflows/ci-security-audit.yml

# OpenSSF Scorecard
curl -o .github/workflows/scorecard.yml \
  https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/.github/workflows/scorecard.yml

# Dependency review
curl -o .github/workflows/dependency-review.yml \
  https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/.github/workflows/dependency-review.yml
```

### 2. Set up release hardening

Copy and customize the release workflow for your build system:

```bash
curl -o .github/workflows/release.yml \
  https://raw.githubusercontent.com/asii-mov/open-sauce-security/main/workflows/release-hardened.yml
```

Then in your repo's GitHub Settings:
1. Create a `release` deployment environment
2. Add required reviewers
3. Restrict deployment to the `main` branch

### 3. Add templates

```bash
# Security policy
cp templates/SECURITY.md SECURITY.md  # Edit contact info

# Dependabot config
cp templates/dependabot.yml .github/dependabot.yml  # Uncomment your ecosystems

# Branch protection (import via GitHub CLI)
gh api repos/OWNER/REPO/rulesets --method POST --input templates/branch-rulesets.json

# Tag protection
gh api repos/OWNER/REPO/rulesets --method POST --input templates/tag-rulesets.json
```

### 4. Run the audit

Check your repo's current security posture:

```bash
./scripts/audit.sh
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
| [`branch-rulesets.json`](templates/branch-rulesets.json) | Branch protection: no force-push, require reviews, require status checks |
| [`tag-rulesets.json`](templates/tag-rulesets.json) | Tag protection: prevent deletion and modification of release tags |
| [`dependabot.yml`](templates/dependabot.yml) | Automated dependency updates with grouped PRs |

### Manual (guides)

| Guide | Audience | What it covers |
|-------|----------|---------------|
| [`maintainer-guide.md`](guides/maintainer-guide.md) | Repo maintainers | 2FA enforcement, access control, secrets management, dependency review, release approval, incident response |
| [`org-enforcement.md`](guides/org-enforcement.md) | Org admins | Applying this toolkit across **every** repo in an org: org rulesets, required workflows, Allstar, safe-settings, bulk setup scripts |

### Local audit

| Script | What it does |
|--------|-------------|
| [`audit.sh`](scripts/audit.sh) | Checks your repo for: unpinned actions, workflow vulnerabilities, missing branch protection, missing SECURITY.md, missing dependency updates, binary artifacts, hardcoded secrets |

## Why This Exists

Open source supply chain attacks are increasing in frequency and sophistication:

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
