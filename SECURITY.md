# Security Policy

Margine is a personal, single-maintainer atomic Linux image. Security is
taken seriously — the published image is [cosign](https://github.com/sigstore/cosign)-signed
by digest, the CachyOS kernel and every kernel module are signed for Secure
Boot with the Margine MOK, and the build supply chain is locked down
(SHA-pinned GitHub Actions, least-privilege workflow tokens, generated and
signed SBOMs, Renovate dependency updates). Please calibrate expectations
accordingly, though: triage and fixes are best-effort, by one person.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's private vulnerability reporting:

- **Build pipeline / published image** —
  <https://github.com/daniel-g-carrasco/margine-image/security/advisories/new>
- **Spec / configuration / validators** —
  <https://github.com/daniel-g-carrasco/margine-fedora-atomic/security/advisories/new>

If you cannot use GitHub Security Advisories, email **ai@danielgrasso.com**
with `[margine-security]` in the subject (PGP available on request).

Please include, where you can: the affected component and version or image
digest, a description, reproduction steps or a proof of concept, and the
impact you foresee.

## What to expect

This is a best-effort process for a personal project:

- **Acknowledgement:** typically within 14 days.
- **Assessment & fix:** triaged by severity; a fix or mitigation ships in a
  new atomic image as soon as practical. Because Margine is delivered as an
  OCI image with automatic daily updates (`uupd.timer`) and atomic rollback,
  an accepted fix reaches users on the next update with no manual steps.
- **Disclosure:** coordinated; credit is given to reporters who want it.

## Scope

**In scope:** the Margine build pipeline, the published OCI image
(`ghcr.io/daniel-g-carrasco/margine:stable`), the kernel-signing / MOK flow,
the declarative spec and configuration helpers, and the live ISO.

**Out of scope / not a vulnerability:**

- **The MOK enrollment passphrase `margine-os` is public by design.** A MOK
  passphrase only authorizes enrolling the *already-built, already-signed*
  Margine key on the local machine during a physically-present reboot — it
  is not a secret and grants no remote capability. See the
  [handbook](https://margine.the-empty.place/handbook) for the threat model.
- Issues in upstream components shipped unchanged (Fedora, Bluefin DX, the
  CachyOS kernel, Flatpak apps): please report those to the respective
  upstreams. Margine picks up their fixes on the next rebuild.

## Verifying what you run

The published image is cosign-signed. See the **Verify the image signature**
section of the [README](README.md#verify-the-image-signature) for the
verification command.
