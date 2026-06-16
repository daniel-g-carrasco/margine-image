# Security Policy

This repository holds the declarative spec, configuration helpers, and
validators for **Margine** — a personal, single-maintainer atomic Linux
image. The image it produces is [cosign](https://github.com/sigstore/cosign)-signed
by digest and its CachyOS kernel and modules are signed for Secure Boot with
the Margine MOK; the build supply chain is locked down (SHA-pinned GitHub
Actions, least-privilege workflow tokens, signed SBOMs, Renovate). Please
calibrate expectations accordingly, though: triage and fixes are best-effort,
by one person.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's private vulnerability reporting:

- **Spec / configuration / validators** (this repo) —
  <https://github.com/daniel-g-carrasco/margine-fedora-atomic/security/advisories/new>
- **Build pipeline / published image** —
  <https://github.com/daniel-g-carrasco/margine-image/security/advisories/new>

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

**In scope:** the declarative spec (`declarations/`), the `margine-configure-*`
helpers, the `margine-validate-*` / `validate-margine-system` validators, and
the documentation. Image-build and signing issues belong in the
[`margine-image`](https://github.com/daniel-g-carrasco/margine-image) repo.

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

The published image is cosign-signed. The verification command is in the
[`margine-image` README](https://github.com/daniel-g-carrasco/margine-image#verify-the-image-signature).
