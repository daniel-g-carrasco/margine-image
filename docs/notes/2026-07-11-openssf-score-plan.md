# Raising the OpenSSF Scorecard score (6.1 as of 2026-07-10)

Report: <https://scorecard.dev/viewer/?uri=github.com/daniel-g-carrasco/margine-image>. The scorecard.yml workflow re-runs weekly, so changes show up within a week (or dispatch it manually).

## Where the 6.1 comes from, check by check

Already at 10 (keep them there): Dangerous-Workflow, Binary-Artifacts, Dependency-Update-Tool, Vulnerabilities, Security-Policy, SAST, License, CI-Tests. Pinned-Dependencies sits at 9 (the pip version-pin-without-hashes in the IA jobs, documented as accepted in #297).

### Fixed in this PR: Token-Permissions (was 0, HIGH weight)

Scorecard zeroes the check when any workflow has a top-level write permission or no top-level block at all. Round 1 (#297) covered four workflows; this round finishes the job: top-level `permissions: {}` added to build.yml and build-disk.yml (every job already declared its own), and the top-level writes in otiling-pin-sha.yml and build-nvidia.yml moved down to their single jobs. Expected: 0 to ~9 (job-level writes still cost a warn each, and they are all genuinely needed).

### Fixes itself: Maintained (0, HIGH weight)

Scored 0 only because the repo is younger than 90 days ("project was created within the last 90 days"). With the current commit cadence it goes to 10 on its own around mid-September 2026. No action possible or needed.

### Daniel's call: Branch-Protection (currently "?", HIGH weight)

Scorecard could not assess it (needs admin scope), which scores as unknown; enabling protection on main earns real points. The solo-maintainer-compatible setup: require a PR before merging, require the lint status check, block force pushes. NOT "require approvals" (nobody can approve but you). One command when you decide:

```sh
gh api -X PUT repos/daniel-g-carrasco/margine-image/branches/main/protection \
  -f 'required_status_checks[strict]=false' \
  -f 'required_status_checks[checks][][context]=lint' \
  -F enforce_admins=false \
  -F 'required_pull_request_reviews=null' \
  -F 'restrictions=null' \
  -F allow_force_pushes=false -F allow_deletions=false
```

Caveat: after this, direct pushes to main are blocked, everything must go through a PR (our flow already does; it binds you too).

### Daniel's call: CII-Best-Practices badge (0, LOW weight)

Register the project at <https://www.bestpractices.dev>, answer the questionnaire, aim for "passing". Margine already satisfies most of it (docs, HTTPS site, security policy, signed releases via cosign, CI tests, static analysis). Roughly an hour of honest form-filling with your account; I can pre-draft the answers. Passing badge is worth the full 10 on this LOW-weight check.

## Accepted zeros (do not chase these)

- **Code-Review (0, HIGH):** counts changesets approved by a second human. A solo-maintainer project structurally cannot score here without a second reviewer; self-approval does not count. Revisit if a co-maintainer ever joins.
- **Fuzzing (0, MEDIUM):** there is nothing meaningful to fuzz in an image-build pipeline of shell, YAML and Python glue. OSS-Fuzz integration would be theater.
- **Contributors (0, LOW):** wants contributors from multiple organizations. Same structural reality as Code-Review.

## Expected landing zone

Token-Permissions (this PR) plus Maintained (September, automatic) are the two HIGH-weight recoveries: that alone should put the score around 7.5. Branch-Protection adds another HIGH-weight chunk on top (roughly +0.5 to +1 depending on tier), CII a small LOW-weight bump: realistic ceiling for a solo project is around 8 to 8.5, with Code-Review/Fuzzing/Contributors as the structural remainder.
