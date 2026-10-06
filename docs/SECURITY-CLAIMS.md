# Security claims register

What Margine OS promises about security, what each promise defends
against, and **what proves it**. A promise without an automated proof is
listed as such: the point of this file is that nothing is assumed to work
because the code for it exists.

Started on 2026-10-07, after a week in which six real holes were found by
accident (see "Why this file exists" at the end). Reviewed every month by
the "Security review due" issue (`.github/workflows/security-review.yml`),
which also flags overdue items in the tables below.

Status values: **verified** (a CI gate fails when the promise breaks),
**pending #N** (the gate exists in an open PR), **partial** (some of it is
gated, the rest is not), **unverified** (nothing automated checks it),
**limitation** (known not to hold, accepted for now, with the reason).

## Claims

| ID | Promise | Defends against | Proof | Status |
|---|---|---|---|---|
| C1 | Shim, GRUB, the Margine kernel and every module form a signed chain; Secure Boot can enforce it | booting a tampered kernel or module | build: `sbverify` on vmlinuz, `sign-file` on modules, MOK check on the pushed image; smoke-boot boots with Secure Boot enforcing and the Margine key in MokList (#452) | pending #452 |
| C2 | Any install can enable Secure Boot later: the Margine key is enrolled whether Secure Boot is on or off | an install that can never turn Secure Boot on | `mok-enroll` every boot (#443), `tests/mok-enroll.test.sh`, validator A.4.mok, smoke `mok-key`/`mok-helper` (#452) | pending #452 |
| C3 | Every published image is signed with the Margine key, in the format devices read | an unsigned or wrongly signed image reaching users | sign job (classic + bundle, #448), job-condition lint (#450), ntfy UNSIGNED alarm (#450), smoke-boot refuses to promote without a valid classic signature (#448) | verified |
| C4 | Devices verify that signature before deploying an update | a compromised registry or account pushing an image | policy scope + key + `registries.d` (#449), installer `--enforce-container-sigpolicy`, migration of unverified installs, validator A.4.trust, smoke `trust-policy` + `image-signature` through the device stack (#452) | pending #449, #452 |
| C5 | The image carries no secret and no per-machine identity: every install generates its own keys | one leaked image = keys of every install (a root adb key shipped until 2026-10-04) | image scan, secrets fatal on every event (#451) | pending #451 |
| C6 | Security-relevant files, privileged binaries, enabled units and build residue only change through a reviewed diff | silent changes from our build or from the base image | image scan against `.github/security-baseline/` (#451): fails PRs, opens a drift issue on main | pending #451 |
| C7 | SELinux labels user homes correctly | a home relabeled to `default_t` (sshd cannot read keys; confined apps break) | build fix + validator A.4.selinux-home (#439), smoke `selinux-*` (#452) | verified (build); smoke pending #452 |
| C8 | A fresh install exposes no network service beyond the reviewed set | an unexpected listener reachable from any network | smoke `listener` check against `.github/smoke/listeners-allow.txt` (#452) | pending #452 |
| C9 | The firewall blocks unsolicited inbound traffic | services the user starts being reachable from the LAN | none: Fedora's `FedoraWorkstation` zone (inherited) allows all TCP/UDP ports above 1024 | limitation, decision D2 |
| C10 | The disk is encrypted | data read from a stolen disk | none: LUKS is offered by the installer, not enforced, and no CI install checks it | unverified |
| C11 | TPM auto-unlock does not weaken disk encryption | someone with the laptop in hand | `margine-tpm-unlock` keeps the passphrase slot; GRUB menu lock closes kernel command-line editing (#444, VM-tested); the initramfs on `/boot` is neither signed nor measured into PCR 7, so it can be replaced by someone who can boot other media | limitation, decision D1 |
| C12 | The build supply chain is pinned and least-privilege | a moved tag or an over-privileged token | SHA-pinned actions, per-job permissions (Scorecard), Renovate; workflow job-condition lint (#450) | partial |
| C13 | Two builds of the same tree publish the same layers | content changing without a source change | measured on #442 (127/127 layers equal); not re-checked automatically | partial, item E4 |
| C14 | SELinux denies nothing a Margine component needs | a service silently broken in enforcing mode | smoke reports denials logged in its permissive VM (#452); not gating yet | partial, item E2 |

## Decisions pending

Owner: the maintainer. A decision stays here until it is taken, and the
monthly review lists it until then.

| ID | Question | Options | Due |
|---|---|---|---|
| D1 | TPM unlock against an attacker with the laptop in hand | TPM + PIN (`--tpm2-with-pin`), passphrase only, or a signed UKI with a PCR 11 policy (ADR-0007) | 2026-10-31 |
| D2 | Default firewall zone | keep `FedoraWorkstation` (high ports open, Fedora default) or ship a stricter Margine zone | 2026-10-31 |
| D3 | LLMNR (systemd-resolved, port 5355 on all interfaces) | keep the Fedora default or turn it off | 2026-11-30 |
| D4 | `tailscaled` is enabled by default (inherited from Bluefin) and opens a UDP port on all interfaces | keep it (zero-setup VPN) or ship it disabled, enabled by the user when they log in to Tailscale | 2026-10-31 |

## Engineering items

| ID | Item | Due | Status |
|---|---|---|---|
| E1 | Make the in-image validator gating in smoke-boot once its first runs there are clean (#452) | 2026-10-31 | open |
| E2 | Make SELinux denials gating in smoke-boot (C14), after a reviewed baseline | 2026-11-30 | open |
| E3 | Boot the smoke VM enforcing: label the injected test files instead of `enforcing=0` | 2026-11-30 | open |
| E4 | Periodic double build to keep C13 verified | 2026-11-30 | open |
| E5 | CI install from the ISO with LUKS and TPM unlock, to verify C10 and C11 end to end | 2026-12-31 | open |
| E6 | Attack-surface review of the setuid/capability set the base ships (`.github/security-baseline/privileged.txt`): e.g. `ksu`, `fusermount-glusterfs`, `vmware-user-suid-wrapper`, `suexec` serve few desktops; drop what Margine does not need | 2026-11-30 | open |

## Why this file exists

In the first week of October 2026 six holes were found, none by a check
designed to find them: the Margine key never enrolled on installs made with
Secure Boot off; devices never verifying image signatures (no policy scope,
and signatures in a format the device stack cannot read); TPM unlock
bypassable from the GRUB menu; an SELinux home mapping inherited reversed
from the base image; a root adb private key baked into every image; and
image signing silently skipped by a workflow change. The 2026-06-05 audit
had already named device-side signature verification as the load-bearing
check and deferred it "until a running install is available". It stayed
deferred for four months. This register, its due dates and the monthly
review are there so that does not happen again.
