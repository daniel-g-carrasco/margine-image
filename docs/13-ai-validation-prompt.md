# AI Validation Prompt

Use this prompt with another AI assistant to validate the Margine Fedora Atomic
work against the existing Margine repositories.

```text
You are auditing a Linux distribution design and early repository implementation.

The user has three local repositories:

- /home/daniel/dev/margine-os
- /home/daniel/dev/margine-os-personal
- /home/daniel/dev/margine-fedora-atomic

Your primary target is:

- /home/daniel/dev/margine-fedora-atomic

The other two repositories are context only. Treat them as read-only historical
sources. Do not suggest copying their Arch/CachyOS implementation directly into
the Fedora Atomic repo.

Hard constraints:

- Do not modify /home/daniel/dev/margine-os.
- Do not modify /home/daniel/dev/margine-os-personal.
- If asked to write patches, only write to /home/daniel/dev/margine-fedora-atomic.
- Repository documentation and project artifacts must be in English.
- The user may speak Italian, but repo content should remain English.

Project being validated:

Margine Fedora Atomic is a new experimental Margine OS variant based on:

- Fedora Atomic Desktop / Fedora Silverblue
- GNOME as the first desktop environment
- Btrfs using Fedora's installer layout
- rpm-ostree / ostree atomic deployment model
- Secure Boot as a target requirement
- TPM2 automatic LUKS2 unlock as a target requirement
- optional CachyOS kernel from Fedora COPR as a lab experiment
- Intel/AMD open graphics and media stack
- PipeWire/WirePlumber audio stack
- OpenGL/EGL, Vulkan, VA-API, OpenCL, Rusticl, ROCm validation
- Flatpak-first graphical applications
- toolbox/distrobox for development or experiments
- a future declarative model
- possible future bootc/native image workflow

Explicit non-goals for phase 1:

- no Arch model hidden under Fedora naming
- no pacman, yay, paru, or AUR
- no Hyprland, Lua, Waybar, Walker, Fuzzel as phase 1 desktop requirements
- no root-on-ZFS, Limine, mkinitcpio, Arch UKI generation, or sbctl bootstrap
- no proprietary NVIDIA or out-of-tree modules by default
- no DaVinci Resolve support claim in the baseline
- no RPM Fusion codec replacement as a hidden default
- no implicit kernel.split_lock_mitigate=0 gaming tweak
- no Steam Gaming Mode as the first GNOME phase
- no Bazzite rebase as the default Margine base
- no custom update orchestrator: routine updates flow through Bluefin's
  `uupd.timer` (inherited from the base image); the on-demand validators in
  `scripts/` are the only update-adjacent tooling Margine maintains

Repository state to inspect in /home/daniel/dev/margine-fedora-atomic:

- README.md
- docs/00-goals.md
- docs/01-architecture.md
- docs/02-install-lab.md
- docs/03-cachyos-kernel.md
- docs/04-validation.md
- docs/05-known-risks.md
- docs/06-personal-migration-assessment.md
- docs/07-secure-boot-tpm2.md
- docs/08-gnome-personal-layer.md
- docs/09-declarative-model.md
- docs/10-hardware-media-stack.md
- docs/11-gaming-runtime.md
- declarations/README.md
- declarations/margine-atomic.yaml
- scripts/validate-atomic-layout
- scripts/validate-cachyos-kernel
- scripts/validate-hardware-media-stack
- scripts/validate-gaming-runtime
- scripts/validate-baseline-packages
- scripts/collect-diagnostics
- scripts/apply-margine-on-bluefin
- scripts/apply-host-layer
- scripts/configure-*
- scripts/install-user-extensions
- docs/adr/0005-base-on-bluefin-dx.md
- docs/15-host-layer.md

Context to inspect in /home/daniel/dev/margine-os and
/home/daniel/dev/margine-os-personal:

- package manifests
- AUR manifests
- Flatpak manifests
- update-all architecture (Margine's own update-all was deleted; reference only)
- Secure Boot and TPM2 docs
- root-on-ZFS docs
- post-install validation docs
- hardware/media manifests
- gaming runtime manifests
- Bazzite learning notes
- Framework 13 audio/power/color docs
- home organization docs
- fastfetch/branding assets if relevant

Important existing Margine Personal concepts that may carry over only after
Fedora-native redesign:

- home structure: ~/data, ~/dev, ~/scratch
- XDG user dirs and GTK/Nautilus bookmarks
- font and icon direction
- GNOME-compatible user settings
- Framework 13 EasyEffects preset, but only hardware-gated and runtime-resolved
- Framework 13 power/color ideas, but not Hyprland-specific integration
- Intel/AMD open graphics and media validation
- PipeWire/WirePlumber validation
- gaming runtime split between runtime helpers and launchers
- split-lock mitigation as explicit operator policy only
- update-all as orchestration concept, retired in Margine in favor of Bluefin's `uupd`

Validation tasks:

1. Read the Fedora Atomic repo first.
2. Read the existing Margine repos only to understand prior intent and risks.
3. Validate whether the Fedora Atomic repo respects Fedora Silverblue's model:
   - /usr and root from ostree deployment
   - /etc and /var writable
   - /home normally /var/home
   - rpm-ostree deployment semantics
   - Flatpak/toolbox/rpm-ostree channel separation
4. Validate whether the Secure Boot + TPM2 plan is Fedora-native:
   - Fedora shim/bootloader/kernel first
   - LUKS2 + systemd-cryptenroll
   - passphrase/recovery fallback kept
   - rpm-ostree-aware initramfs handling
   - no premature Limine/sbctl/mkinitcpio/root-on-ZFS assumptions
5. Validate the CachyOS kernel plan:
   - COPR only in lab
   - Fedora kernel fallback pinned or available
   - rollback documented
   - Secure Boot compliance treated as unproven unless validated
6. Validate the hardware/media stack:
   - Fedora package mappings are plausible
   - Intel and AMD are treated separately
   - Rusticl/ROCm/OpenCL are validated, not assumed
   - VA-API/Vulkan/OpenGL/FFmpeg/GStreamer checks are present
   - NVIDIA and Resolve remain explicit future exception layers
7. Validate gaming runtime decisions:
   - Flatpak-first launchers
   - Gamescope/MangoHud/vkBasalt/GameMode as host helpers or future image content
   - Steam Gaming Mode deferred
   - Bazzite used as reference, not default base
   - split-lock tweak not hidden
8. Validate update orchestration:
   - the repo does NOT ship a custom orchestrator; routine updates flow via
     Bluefin's `uupd.timer` (inherited from the base image)
   - `bootc` is the base-OS update path; `rpm-ostree upgrade` is its CLI alias
   - the on-demand validators in `scripts/` are available but not wired to
     `uupd` hooks
   - any reintroduction of an `update-all`-style script or a Topgrade profile
     is a regression — flag it
9. Validate the declarative model:
   - declarations are desired state, not secrets
   - channel-specific state stays separated
   - bootc/native image work is deferred until manual lab evidence exists
10. Validate script quality:
   - no destructive commands
   - read-only validators stay read-only
   - `apply-*` and `configure-*` scripts have dry-run as the default and an
     explicit `--apply` flag to take action
   - shell scripts pass `bash -n` and `shellcheck`
   - Python scripts pass `python3 -m py_compile`
   - YAML parses cleanly

Suggested commands:

cd /home/daniel/dev
find margine-fedora-atomic -maxdepth 3 -type f | sort
git -C margine-fedora-atomic status --short
rg -n "TODO|FIXME|pacman|yay|paru|AUR|Hyprland|Waybar|Walker|Limine|sbctl|mkinitcpio|ZFS|root-on-ZFS|NVIDIA|Resolve|split_lock|update-all|topgrade" margine-fedora-atomic -S
rg -n "gaming|Steam|Proton|Wine|Gamescope|MangoHud|vkBasalt|GameMode|split_lock|Bazzite|OpenCL|VA-API|Vulkan|PipeWire|WirePlumber|TPM2|Secure Boot" margine-os margine-os-personal -S

cd /home/daniel/dev/margine-fedora-atomic
# Bash scripts
for s in scripts/validate-* scripts/collect-diagnostics scripts/apply-host-layer scripts/apply-margine-on-bluefin; do
  bash -n "$s" && shellcheck -S warning "$s"
done
# Python scripts
for s in scripts/configure-* scripts/install-user-extensions; do
  python3 -m py_compile "$s"
done
# YAML parse
python3 -c "import yaml; yaml.safe_load(open('declarations/margine-atomic.yaml'))" && echo "YAML parse OK"

Output format:

Start with findings, ordered by severity:

- Critical: design or script issues that could break boot, rollback, Secure Boot,
  TPM2 unlock, rpm-ostree deployments, or user data.
- High: Fedora Atomic model violations, hidden Arch/CachyOS assumptions,
  dangerous update behavior, or wrong channel decisions.
- Medium: missing validation, ambiguous docs, incomplete package mappings,
  unclear bootc/Topgrade/gaming boundaries.
- Low: wording, organization, minor consistency issues.

For each finding include:

- file path and line number when possible
- why it matters
- concrete recommended fix

Then include:

- what looks sound
- open questions
- tests run
- tests not run
- recommended next steps before real hardware

Do not produce a generic review. Ground the audit in the actual repository
contents and the Fedora Atomic model.
```
