# ADR 0010: base Margine on Universal Blue's silverblue-main, not on Bluefin DX

Status: **Accepted and shipping** (2026-10-11)
Supersedes: [0005](0005-base-on-bluefin-dx.md) (base on Bluefin DX).

## Context

Margine built `FROM ghcr.io/ublue-os/bluefin-dx:stable` since 2026-05-25
(ADR 0005). Universal Blue has been moving Bluefin to the projectbluefin
organisation and announced the end of the `-dx` images once developer
tooling moves to userspace (`ujust devmode`); the exact date was never
given. From 2026-08-25 the base was a build argument (`ARG BASE_IMAGE`),
`build_files/15-devstack` installed what DX added whenever the base lacked
it, `build_files/12-base-trim` removed what a base carried that Margine
does not want, and trial builds (`build.yml`, `workflow_dispatch` with
`base_image`, published as `:trial` only) kept the switch rehearsed.

The package audit of 2026-10-10 (image 14.1 GB) showed that most of what
DX added was unused in Margine: Docker CE, Tailscale, incus, cockpit, the
eBPF and host toolchains, the HIP compiler, rclone, restic, borgbackup.
Those became `ujust` recipes on demand (#472, #475). What remained of
"Bluefin" in the image was then listed by a trial build on
`ghcr.io/ublue-os/silverblue-main:44` and made Margine's own (#480): the
systemd unit that runs `flatpak preinstall` at boot, Bazaar in the
preinstall lists, `uupd` from the `ublue-os/packages` COPR, fastfetch and
the Dash to Dock, Caffeine and GSConnect extensions as Fedora packages,
Gradia Capture and Bazaar Companion built from pinned commits.

## Decision

Build `FROM ghcr.io/ublue-os/silverblue-main:44`: Universal Blue's plain
Fedora Silverblue image, which adds to Fedora only their automation
(`ujust`, update services, signing policy, udev rules, the Flathub remote)
and is rebuilt daily. The Fedora release in the tag is bumped on purpose
(`build_files/11-fedora-release-gate` checks it). `ID_LIKE=fedora`.

Not chosen: raw Fedora Silverblue (would mean re-creating Universal Blue's
automation), `projectbluefin/bluefin` (its channels were not reliably
published when checked, 2026-08-25 and 2026-10-10), Bluefin Dakota (alpha,
no Secure Boot chain, no `FROM` derivation).

## Evidence

- Trial build on silverblue-main from main `388fcf9`: validators PASSED
  (run 38094759058).
- Trial build from main `e16946f` (run 38100181141) and smoke-boot of that
  image (run 38102328262): boot to a usable state in 55 s, GUI probe PASS
  with 9 extensions, security probe PASS (no failed unit, validator PASS),
  gaming-native dry run PASS. The one failure of the first smoke,
  `margine-docs-refresh.service` (226/NAMESPACE), was fixed in #484.
- Image size: 13.8 GB on silverblue-main before the DX trim, against
  14.1 GB on Bluefin DX; after the trims the image is about 7 GB lighter
  than on 2026-10-09.

## Consequences

- Existing installs move to the new base with the next update of
  `:stable`; the first download is a full image, not a delta.
- What Margine shows as its lineage (os-release, labels, `/etc/issue`, the
  status page, `margine-system`) says Fedora Silverblue and Universal
  Blue; Bluefin stays in the credits as the base of the first five months
  and the source of many ideas.
- The handbook (`docs/spec/atomic-distro-handbook.md` and its split copy)
  and the older spec pages still describe the Bluefin DX era in places;
  they are updated separately, this ADR being the reference meanwhile.
- `Containerfile.plan-b-from-bluefin` is removed: the contingency it
  described landed differently (silverblue-main, not plain Bluefin).
