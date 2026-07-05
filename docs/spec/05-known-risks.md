# Known Risks

This project should make risk visible. The first phase is a lab because the
combination of Fedora Atomic Desktop and a third-party kernel needs evidence,
not assumptions.

## COPR

COPR is Fedora's lightweight build system for third-party repositories. COPR
packages are not part of the Fedora Silverblue base. A COPR repository can
change, disappear, publish incompatible builds, or lag behind a Fedora release.

Mitigations:

- use COPR only in a VM during phase 1;
- pin the Fedora deployment before testing;
- take a hypervisor snapshot;
- record the exact repo file and package state;
- do not move to primary hardware until rollback has been tested.

## CachyOS Kernel

The CachyOS kernel replaces a critical part of the host. On Silverblue this is
done through rpm-ostree overrides and creates a deployment that diverges from
the Fedora base.

Mitigations:

- keep a Fedora kernel deployment available;
- do not install a script that permanently forces CachyOS as the default;
- test `rpm-ostree rollback --reboot`;
- record `uname -a`, package state, failed units, and journal warnings.

## Secure Boot

Secure Boot may block unsigned kernels or modules that are not trusted by the
firmware and shim/MOK chain.

Current decision:

- Secure Boot is required for the real target.
- The first compliant baseline is stock Fedora Silverblue with Fedora's signed
  boot path.
- Disabling Secure Boot is allowed only as a temporary VM exception for isolating
  the CachyOS kernel experiment.

Risks:

- a third-party kernel may not boot under the Fedora trust chain;
- a custom signing or MOK flow can become fragile across updates;
- out-of-tree modules increase signing and support complexity.

Mitigations:

- validate stock Fedora Secure Boot before third-party repositories;
- keep the Fedora kernel deployment pinned before kernel replacement;
- treat CachyOS-without-Secure-Boot as non-compliant lab data, not as the target;
- do not introduce custom keys, UKIs, or bootloader changes until there is a
  dedicated design.

## TPM2 Auto-Unlock

TPM2 auto-unlock improves boot ergonomics, but it can also make recovery harder
if the PCR policy, initramfs contents, Secure Boot state, or bootloader state
changes unexpectedly.

Current decision:

- TPM2 auto-unlock is required for the real target.
- The encrypted system must keep a manual passphrase or recovery key.
- The lab must use LUKS2 and `systemd-cryptenroll`.
- The final initramfs procedure must be rpm-ostree-aware.

Risks:

- sealing to the wrong PCR set can break unlock on routine updates;
- using a mutable Fedora Workstation `dracut -f` procedure on Silverblue can
  produce misleading results;
- disabling Secure Boot after enrollment can invalidate or weaken the TPM2
  policy;
- recovery is poor if the only valid unlock path is TPM2.

Mitigations:

- test on the stock Fedora kernel before testing the CachyOS kernel;
- do not wipe the original passphrase slot in phase 1;
- record `/etc/crypttab`, initramfs policy, `mokutil --sb-state`, and
  `rpm-ostree status`;
- test update and rollback after enrollment;
- choose PCR binding only after observing the Fedora 44 boot path in the lab.

## NVIDIA and Out-of-Tree Modules

NVIDIA, akmods, VirtualBox host modules, ZFS, and other out-of-tree modules add
extra compatibility risk with custom kernels and atomic deployments.

Initial decision:

- no NVIDIA or out-of-tree module support in the phase 1 baseline.

Future work:

- test each module family separately;
- verify matching headers or devel packages;
- prove rollback before routine updates.

## Hardware Media Stack

Graphics, media acceleration, audio, and GPU compute can look healthy at one
layer while failing at another. A working GNOME session does not prove that
VA-API, Vulkan, OpenCL, ROCm, Rusticl, or application compute paths work.

Risks:

- the VM may expose only software rendering or limited virtual GPU features;
- `glxinfo`, `vulkaninfo`, and `vainfo` can pass while OpenCL is missing;
- Rusticl may require runtime or driver opt-in before devices are exposed;
- ROCm OpenCL can be installed but unsupported for the exact AMD GPU or
  workload;
- Intel media acceleration depends on the correct VA-API driver generation;
- Flatpak applications may not see a host driver path the same way host tools
  do;
- a CachyOS kernel can change driver behavior independently from Fedora
  userspace;
- codec replacement through third-party repositories can create rpm-ostree
  dependency and update risk.

Mitigations:

- validate the stock Fedora stack before adding host layers;
- keep Intel, AMD, audio, codec, gaming, NVIDIA, and Resolve decisions separate;
- use `scripts/validate-hardware-media-stack` after any driver, codec, media,
  or kernel change;
- record both host diagnostics and application-level tests such as
  `darktable-cltest`;
- treat RPM Fusion codec replacement as a separate documented decision, not a
  hidden default;
- keep NVIDIA and other out-of-tree modules out of phase 1.

## Commercial Media Applications

DaVinci Resolve and similar commercial media applications are not validated by
normal desktop acceleration checks.

Risks:

- Resolve may require a vendor-specific compute backend, not just OpenGL;
- AMD, Intel, and NVIDIA have different practical support profiles;
- runtime libraries and codecs can become a compatibility stack of their own;
- Fedora Atomic host layering may not be the best channel for application
  compatibility experiments.

Mitigations:

- do not advertise Resolve support in the baseline;
- document Resolve as a future vendor-aware exception layer;
- require GPU vendor detection, compute validation, runtime dependency
  validation, and actual application startup before claiming support.

## Gaming Runtime

Gaming stacks often mix applications, host runtime helpers, Vulkan injection
layers, controller rules, kernel tuning, and desktop-session changes. That is
useful when engineered into a dedicated image, but risky when added as
unreviewed rpm-ostree layers.

Risks:

- layered host gaming packages can block rpm-ostree upgrades or rebases;
- Steam Flatpak, host Vulkan layers, and Flatpak runtime extensions may not see
  the same MangoHud/vkBasalt state;
- Gamescope as a per-game wrapper and Gamescope as a full Steam Gaming Mode
  session are different integration problems;
- GameMode can overlap with other process-priority systems;
- controller and input helper services can add broad udev or daemon behavior;
- `kernel.split_lock_mitigate=0` weakens a kernel mitigation if enabled
  silently;
- Bazzite-specific services, kernel patches, and handheld assumptions may not
  match a stock GNOME Silverblue target;
- NVIDIA gaming support compounds Secure Boot, akmods, and rollback risk.

Mitigations:

- validate hardware/media before gaming runtime;
- use `scripts/validate-gaming-runtime` after any gaming package or launcher
  change;
- prefer Flatpak for launchers in phase 1;
- keep Gamescope session work separate from desktop runtime work;
- keep `kernel.split_lock_mitigate=0` as an explicit operator override only;
- treat Bazzite as a reference and comparison target, not as implicit base
  policy;
- move stable host gaming helpers into a future image or bootc path instead of
  accumulating permanent client-side layers.

## Btrfs

Btrfs is Fedora's default desktop filesystem, but it is not a drop-in replacement
for prior root-on-ZFS assumptions.

Initial decision:

- use Fedora's installer layout;
- do not create a custom snapshot policy;
- validate with `findmnt`, `lsblk -f`, and `btrfs` commands when available.

## rpm-ostree Overrides

Overrides can make the deployment diverge from Fedora. That is acceptable for a
kernel experiment, but it must not become the default way to build the system.

Mitigations:

- keep layering rare;
- document the reason for each host layer;
- prefer Flatpak for GUI apps;
- prefer toolbox or distrobox for development tools;
- inspect `rpm-ostree status -v` after host changes.

## Fedora Release Cadence

Fedora moves quickly. The current release changes, and third-party repositories
may not track every release at the same pace.

Mitigations:

- record test date and Fedora release;
- do not skip major releases in the lab;
- refresh documentation when Fedora's stable release changes.

## bootc

bootc is promising, but it shifts the workflow toward bootable OCI container
images. Starting with bootc before understanding Silverblue manually would hide
basic system behavior behind another build layer.

Initial decision:

- bootc is future work, not phase 1 implementation.

## Declarative Drift

A declarative repository can create false confidence if the declarations are not
checked against the running system or if one file tries to control unrelated
state channels.

Risks:

- declarations drift away from the VM result;
- host state, Flatpak state, GNOME settings, and user home state get mixed
  together;
- apply scripts mutate the system without producing a reviewable plan;
- secrets or recovery material are accidentally committed;
- a future image build bakes in untested assumptions.

Mitigations:

- keep `declarations/` as a draft until the manual lab validates it;
- build read-only drift detection before apply tooling;
- split host, user, application, security, and container state by channel;
- never store private keys, tokens, passphrases, TPM2 secrets, or recovery keys
  in declarations;
- require validation output before moving declarations into a bootc/image path.
