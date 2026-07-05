# Gaming Runtime

Margine Fedora Atomic should support a real gaming runtime, but it should do so
with the same discipline as the rest of the system: Fedora Atomic first,
channel-aware, declarative, validated, and reversible.

> **As shipped (2026-06):** the gaming layer is opt-in via two `ujust`
> recipes, not a separate image. **`ujust margine-gaming`** (default) layers
> only the two strictly gaming-only RPMs (gamescope + vkBasalt) and installs
> Steam/Lutris/Heroic/Bottles/Protontricks/ProtonPlus/RetroArch as Flatpaks.
> **`ujust margine-gaming-native`** instead layers steam + lutris + retroarch
> as RPMs (maximum Proton/anti-cheat/VR compatibility, +30–60 s per
> `bootc upgrade`) and keeps only the launchers without an RPM as Flatpaks.
> Either is undone with the matching `-remove` recipe. Everything else
> (mangohud, goverlay, steam-devices, gamemode, tuned, scx-scheds) is already
> in base Margine. `validate-gaming-runtime` models both paths.

This document takes inspiration from two places:

- Margine Personal, which split gaming runtime compatibility from launchers and
  kept the split-lock kernel policy explicit;
- Bazzite, which shows what a mature Fedora Atomic gaming image can provide out
  of the box.

The goal is not to become a Bazzite clone. The goal is to learn from Bazzite's
image-first gaming model while keeping Margine's GNOME/Silverblue lab, Secure
Boot, TPM2, and CachyOS-kernel experiments understandable.

## Phase Position

Gaming is part of the target profile, but it comes after the base hardware/media
stack is validated.

Order:

1. validate stock Silverblue GNOME;
2. validate Secure Boot and TPM2 unlock;
3. validate Intel/AMD graphics, Vulkan, VA-API, OpenCL, PipeWire, and codecs;
4. enable the desktop gaming runtime;
5. evaluate Steam Gaming Mode or a Bazzite-style gaming image only after the
   desktop runtime is stable.

## What Bazzite Teaches

Bazzite is useful evidence because it is a Fedora Atomic gaming system, not an
Arch-style mutable install. The important ideas to borrow are:

- build gaming support into an image when it becomes stable;
- keep user applications and host components separated;
- prefer Flatpak, containers, and image content over long-lived ad-hoc
  `rpm-ostree` layering;
- ship a working hardware/media stack before promising a gaming stack;
- provide rollback and update tooling as first-class user workflows;
- make Steam Gaming Mode a dedicated session for handheld and couch devices,
  not a random desktop autostart.

Bazzite-specific choices that should not be copied blindly:

- rebasing Margine to Bazzite as the default;
- Steam Gaming Mode as the first GNOME phase;
- Bazzite's custom kernel and patch set as a hidden assumption;
- NVIDIA images as a baseline;
- handheld-specific services on non-handheld machines;
- Bazzite Portal or `ujust` as required Margine control planes;
- Bazzite Secure Boot key enrollment as a substitute for Margine's own target
  boot policy.

## Margine Layer Model

Keep three gaming layers distinct.

| Layer | Purpose | Default phase |
| --- | --- | --- |
| `gaming-runtime-desktop` | Steam/Proton/Lutris/Bottles plus host runtime helpers | after hardware/media validation |
| `gaming-tools-overlays` | Gamescope, MangoHud, vkBasalt, OBS capture, per-game tools | optional after desktop runtime |
| `gaming-mode-session` | Steam Gaming Mode / gamescope-session style session | future image or bootc work |

This mirrors Margine Personal's separation between runtime compatibility and
launcher/overlay tools, but maps it to Fedora Atomic channels.

## Channel Policy

| Component | Preferred channel |
| --- | --- |
| Steam | Flatpak first in phase 1 |
| Lutris, Heroic, Bottles, Protontricks, ProtonPlus | Flatpak |
| Gamescope | host package or future image content |
| MangoHud and vkBasalt | host package or Flatpak runtime extension, validated per app |
| GameMode | host package or future image content |
| OBS Studio | Flatpak first |
| OBS VkCapture | host package only if host OBS/game capture path is chosen |
| Wine/Winetricks | Flatpak app runtime first; toolbox/distrobox for experiments |
| Proton GE | ProtonPlus-managed user install, not AUR |
| Controller udev rules | host package if needed |
| LACT/GPU control | future hardware policy exception, not default |
| Steam Gaming Mode | future image/session layer |

Avoid long-lived `rpm-ostree install` for app launchers. If a host component is
needed repeatedly, it should later move from client-side layering into a native
image or bootc build.

## Desktop Runtime

Initial Flatpak applications:

```text
com.valvesoftware.Steam
net.lutris.Lutris
com.heroicgameslauncher.hgl
com.usebottles.bottles
com.github.Matoking.protontricks
com.vysp3r.ProtonPlus
```

Optional emulation/library tools:

```text
org.libretro.RetroArch
net.retrodeck.retrodeck
page.kramo.Cartridges
```

Initial host candidates after validation:

```text
gamescope
mangohud
vkBasalt
gamemode
goverlay
steam-devices
vulkan-tools
mesa-demos
```

Fedora 44 repository checks showed `gamescope`, `mangohud`, `vkBasalt`,
`gamemode`, `goverlay`, and `steam-devices` as Fedora package candidates. Steam
itself should remain Flatpak-first in phase 1.

## Gamescope

Gamescope has two different roles:

- per-game wrapper from the desktop;
- full Steam Gaming Mode session.

Phase 1 only targets the per-game wrapper:

```sh
gamescope -- steam steam://rungameid/<appid>
```

Do not make Gamescope a GNOME autostart item. Do not replace GDM/GNOME with a
gamescope session until there is a separate `gaming-mode-session` design.

## MangoHud, vkBasalt, and Capture Layers

MangoHud, vkBasalt, and OBS VkCapture are useful, but they are injection layers.
They must be visible and testable.

Validation should inspect:

- host packages;
- Flatpak runtime extensions if Steam or OBS is Flatpak;
- Vulkan implicit and explicit layer JSON files;
- `vulkaninfo --summary`;
- per-game launch environment.

Do not assume that a host Vulkan layer automatically applies inside every
Flatpak.

## GameMode and Process Policy

GameMode can be useful for per-game scheduling and governor hints. It should not
be mixed blindly with other process-priority systems.

Phase 1 policy:

- GameMode is allowed as an optional host helper;
- CachyOS `ananicy-cpp` policy is not part of the Fedora Atomic baseline;
- do not enable multiple process-priority systems without a specific conflict
  test;
- validate `gamemoded` presence and session behavior before declaring support.

## Split-Lock Policy

`kernel.split_lock_mitigate=0` remains an explicit operator override.

Rules:

- the gaming runtime must not set it implicitly;
- the default expected value is mitigation active when the kernel exposes it;
- any persistent drop-in disabling it is a validation warning;
- a future toggle must report runtime state, persistent state, and the file that
  owns the setting.

This preserves the Margine Personal decision: package composition and kernel
mitigation policy are separate.

## Steam Gaming Mode

Steam Gaming Mode is not the first target.

It becomes relevant for:

- handhelds;
- couch gaming;
- HTPC setups;
- a future Bazzite-like image profile.

Before adding it, the project needs:

- a validated desktop gaming runtime;
- a decision about GDM session integration;
- a decision about Gamescope session packaging;
- controller input validation;
- rollback from a broken gaming session;
- Secure Boot and TPM2 behavior after any kernel/session changes;
- a decision whether this belongs in `bootc` rather than client-side layering.

## Bazzite Rebase Position

Rebasing to Bazzite is a useful comparison test, not the Margine target.

Acceptable lab use:

- compare Bazzite GNOME against Margine Fedora Atomic GNOME;
- record package, Flatpak, kernel, codec, Gamescope, and Secure Boot behavior;
- identify which Bazzite ideas should become Margine declarations.

Not acceptable as the default:

- replacing the Margine base with Bazzite without documenting the inherited
  image policy;
- treating Bazzite's custom kernel, codecs, NVIDIA variants, or handheld
  services as Margine defaults.

## Validation Commands

Run:

```sh
scripts/validate-gaming-runtime
```

Manual checks:

```sh
flatpak list | grep -Ei 'Steam|Lutris|Heroic|Bottles|Proton|RetroArch|RetroDECK|Cartridges' || true
flatpak info com.valvesoftware.Steam
flatpak info --show-permissions com.valvesoftware.Steam
rpm -qa | grep -Ei 'gamescope|mangohud|vkbasalt|gamemode|steam-devices|obs.*capture|goverlay|lact|wine|lutris|protontricks' | sort || true
command -v gamescope mangohud vkbasalt gamemoded || true
gamescope --help | sed -n '1,40p'
mangohud --version
vkbasalt --version
gamemoded -s
find /usr/share/vulkan /etc/vulkan "$HOME/.local/share/vulkan" -maxdepth 3 -type f 2>/dev/null | sort
vulkaninfo --summary
cat /proc/sys/kernel/split_lock_mitigate 2>/dev/null || true
grep -RHsnE '^[[:space:]]*kernel\.split_lock_mitigate[[:space:]]*=[[:space:]]*0' /etc/sysctl.d /usr/lib/sysctl.d 2>/dev/null || true
```

Pass criteria:

- Steam and selected launchers are installed through the declared channel;
- Vulkan works before gaming apps are blamed;
- Gamescope runs or is explicitly absent from the active profile;
- MangoHud/vkBasalt state is visible and not assumed;
- GameMode is present only when declared;
- split-lock mitigation is not disabled by default;
- no gaming package breaks rpm-ostree upgrade, rollback, Secure Boot, or TPM2.

## References

- Bazzite and Fedora Atomic comparison: https://docs.bazzite.gg/General/Fedora_Atomic_Comparison/
- Bazzite package layering guidance: https://docs.bazzite.gg/Installing_and_Managing_Software/rpm-ostree/
- Bazzite Steam Gaming Mode overview: https://docs.bazzite.gg/Handheld_and_HTPC_edition/Steam_Gaming_Mode/
- Bazzite repository: https://github.com/ublue-os/bazzite
- Fedora Gamescope documentation: https://docs.fedoraproject.org/en-US/gaming/gamescope/
