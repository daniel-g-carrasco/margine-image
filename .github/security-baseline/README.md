# Image security baseline

What `.github/scripts/scan-image-security.py` compares every built image
with (build.yml, step "Security scan of the image"). Each file is the
reviewed state of one category; a change to any of them is a security
decision and goes through a PR like code.

| file | content |
|---|---|
| `privileged.txt` | setuid / setgid files and files with capabilities |
| `writable.txt` | world-writable files and non-sticky dirs under usr and etc |
| `residue.txt` | entries left in run, tmp, var/tmp, the homes, root's home |
| `units.txt` | enabled systemd units (wants/requires/upholds links) |
| `configs/` | copies of security-relevant configuration files |
| `secrets-allow.txt` | the only exceptions to the secrets check, each with a reason |

Secrets (private keys, tokens, ssh host keys, a set machine-id) have no
baseline: they fail the build on every event.

## When the scan reports drift

- **On a pull request** the build fails and the step summary shows the diff.
  If the change is intended, download the `security-baseline-proposed`
  artifact of that run and commit its content here, in the same PR.
- **On main** (usually a base-image update) the build goes on, so security
  updates are never held back, and the "Security baseline drift" issue gets
  the diff. Review it, then commit the proposed baseline in a PR.
