# Declarative Model

Margine Fedora Atomic should become a declarative desktop distribution, but the
word declarative has to fit Fedora Atomic rather than replace it with a different
operating-system model.

The target is:

- one reviewed desired-state source of truth;
- separate execution adapters for Fedora's real channels;
- read-only drift detection before any automatic remediation;
- a later path to bootc or another native image workflow.

## What Declarative Means Here

A declaration says what the system should be:

- Fedora Atomic Desktop variant and release;
- storage and boot requirements;
- Secure Boot and TPM2 policy;
- host packages and overrides;
- Flatpak applications;
- hardware/media host capabilities;
- gaming runtime profile;
- toolbox/distrobox environments;
- GNOME preferences;
- home layout;
- enabled services;
- validation commands and pass criteria.
- update orchestration policy.

It does not mean that every change is applied through one universal package
manager. Fedora Atomic has distinct state channels and the project should keep
that separation.

## Non-Goals

Do not build these in phase 1:

- a NixOS clone;
- a custom DSL;
- a magic converge-everything daemon;
- a script that mutates rpm-ostree, Flatpak, GNOME, home state, and boot state
  without showing a plan first;
- a bootc image before the manual Silverblue lab is understood.

Do not store these in declarations:

- user passwords;
- LUKS passphrases;
- TPM2 sealed secrets;
- recovery keys;
- private registry tokens;
- SSH private keys;
- browser profile data.

## Repository Shape

Initial structure:

```text
declarations/
  README.md
  margine-atomic.yaml
```

Future structure, if the single file becomes too large:

```text
declarations/
  base.yaml
  security.yaml
  storage.yaml
  host-packages.yaml
  hardware-media.yaml
  gaming-runtime.yaml
  flatpaks.yaml
  toolboxes.yaml
  gnome.yaml
  home.yaml
  services.yaml
  validation.yaml
  updates.yaml
```

Keep the first implementation boring. YAML or TOML plus schema validation is
enough until there is evidence that a custom format is needed.

## Channel Boundaries

| Desired state | Notional adapter |
| --- | --- |
| Fedora Silverblue release | `rpm-ostree status`, upgrade, deploy |
| host packages | `rpm-ostree install` or image build |
| kernel replacement | `rpm-ostree override` in lab, image build later |
| hardware/media host stack | `rpm-ostree install`, image build, and read-only validators |
| gaming host helpers | `rpm-ostree install`, image build, and read-only validators |
| Flatpaks | `flatpak install` and `flatpak list` |
| toolbox dev environment | `toolbox create`, container package manifest |
| GNOME preferences | `gsettings` or dconf load |
| home layout | user-home provisioner |
| folder icons | GIO metadata updater |
| systemd services | `systemctl enable`, presets, or image policy |
| boot security | validation plus manual enrollment steps |
| TPM2 unlock | `systemd-cryptenroll`, `/etc/crypttab`, rpm-ostree initramfs |
| routine updates | Bluefin `uupd.timer` (inherited from base image) |

Adapters should support at least two modes:

- `plan`: show what would change;
- `apply`: make changes only after review.

The first implemented mode should be `validate`, because it is easier to trust
than automatic remediation.

## Phase Plan

### Phase 1: Manual Lab Plus Declarations

The lab remains manual. After each validated decision, update
`declarations/margine-atomic.yaml`.

The declaration file is allowed to lag behind the lab while a question is still
open. Do not encode guesses as policy.

### Phase 2: Read-Only Drift Detection

Add a validator that compares the running system with the declaration:

```sh
scripts/validate-declared-state
```

Expected data sources:

- `rpm-ostree status --json`;
- `rpm -qa`;
- `lspci -k`, `lsmod`, `glxinfo`, `vulkaninfo`, `vainfo`, `clinfo`, `rocminfo`;
- `flatpak list`;
- `gamescope`, `mangohud`, `vkbasalt`, `gamemoded`, Vulkan layer files, and
  split-lock sysctl state;
- `toolbox list`;
- `gsettings`;
- `/etc/crypttab`;
- `findmnt`;
- `lsblk -f`;
- `systemctl is-enabled`;
- `uupd --version` and `systemctl status uupd.timer` for update orchestration health;
- GIO metadata for managed folders.

This validator should not install or remove anything.

### Phase 3: Plan-First Apply Adapters

Only after drift detection is accurate, add adapters that produce an execution
plan.

Examples:

- `rpm-ostree install` plan for host packages;
- hardware/media host package plan, separated from creative and gaming apps;
- gaming runtime plan, separated into Flatpak apps, host helpers, and future
  gaming session/image work;
- `flatpak install` plan for GUI apps;
- `gsettings set` plan for GNOME preferences;
- home layout provisioner plan;
- systemd enablement plan.
- update orchestration plan.

Every host-level apply must respect rpm-ostree deployment semantics and the
required reboot.

### Phase 4: Native Image or bootc

After the profile is stable, move host state into a native image workflow.

bootc is a strong candidate because Fedora/CentOS bootc uses bootable OCI
container images for transactional operating-system updates, and those images
include the OS content needed to boot, including kernel and bootloader-adjacent
components. A derived image can be built with normal container tooling and later
installed through Anaconda, bootc-image-builder, or `bootc install`.

Do not skip the earlier phases. A bootc image built from bad assumptions is just
a faster way to distribute those assumptions.

## Open Design Decisions

- Whether declarations stay as one profile file or split into smaller files.
- Whether validation uses shell plus `jq`, Python, or another small tool.
- Whether host packages remain client-side rpm-ostree layers or move into an
  image build first.
- Whether Flatpak defaults are applied at system level or user level.
- How to represent toolbox contents without turning toolboxes into host state.
- Whether stable gaming host helpers move into a native image before Steam
  Gaming Mode work starts.
- Whether the channel-specific apply adapters should integrate with `uupd`
  hooks or remain purely on-demand.
- How to model Secure Boot and TPM2 as locally verified requirements rather
  than portable secrets.
- Whether bootc should replace Silverblue rebasing later or remain a separate
  experimental track.

## Success Criteria

The declarative model is useful only when:

- a fresh VM can be compared against `declarations/margine-atomic.yaml`;
- differences are reported clearly by channel;
- host changes are separated from user changes;
- the Fedora kernel fallback remains visible in the declaration;
- Secure Boot and TPM2 policy are represented without storing secrets;
- a future image build can consume the same policy without rewriting the project.

## References

- Fedora/CentOS bootc docs: https://fedora.gitlab.io/bootc/docs/bootc/
- bootc install docs: https://bootc.dev/bootc/bootc-install.html
- Fedora/CentOS bootc storage docs: https://fedora.gitlab.io/bootc/docs/bootc/storage/
- Fedora/CentOS bootc bare-metal docs: https://fedora.gitlab.io/bootc/docs/bootc/bare-metal/
- rpm-ostree administrator handbook: https://coreos.github.io/rpm-ostree/administrator-handbook/
