# Lab VM Setup (libvirt + virt-manager)

Step-by-step operational guide for spinning up a Margine smoke-test
VM on libvirt with UEFI + Secure Boot + vTPM 2.0. This is what
[docs/02-install-lab.md](02-install-lab.md) refers to as the "VM lab".

The setup is intentionally close to a Framework 13 AMD profile so the
lab catches problems that would also bite on real hardware:

- UEFI firmware with Secure Boot enabled
- Virtual TPM 2.0 (`tpm-crb` model)
- LUKS2 full-disk encryption during install
- 8 GiB RAM, 4 vCPU, 64 GiB qcow2 disk

## GUI or CLI?

Every operation below can be done either from **virt-manager** (GUI)
or from `virsh` / `virt-install` (CLI). The guide shows **both**, with
the GUI as the preferred path for day-to-day operations (snapshots,
start/stop, console viewer) and the CLI for complex or repeatable ones
(creating a VM with vTPM + Secure Boot, automation scripts).

Open virt-manager by running its namesake command. If needed, add the
system connection: `File → Add Connection... → QEMU/KVM`, local host,
system-level (`qemu:///system`).

## Prerequisites (Arch host)

Margine's spec runs on Bluefin DX, but the lab host can be any
distro. These notes are for Arch — on Fedora/openSUSE most of this
is already configured.

```sh
# Install libvirt stack + viewers
sudo pacman -S --needed libvirt qemu-base qemu-system-x86 \
    qemu-img edk2-ovmf swtpm virt-manager virt-viewer

# Modular libvirt on Arch: enable every socket the toolkit may need
sudo systemctl enable --now \
    virtqemud.socket \
    virtnetworkd.socket \
    virtstoraged.socket \
    virtnodedevd.socket \
    virtinterfaced.socket

# Add yourself to the libvirt group (avoids needing sudo everywhere)
sudo usermod -aG libvirt $USER
# Then logout/login (or `newgrp libvirt`) for the group to take effect.
```

### Default network (only needed once)

Arch's libvirt does not auto-define the `default` NAT network. Without
it, `virt-install --network network=default` fails with
`Network not found`. Define it once:

```sh
cat <<'EOF' | sudo tee /tmp/libvirt-default-network.xml
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh --connect qemu:///system net-define /tmp/libvirt-default-network.xml
sudo virsh --connect qemu:///system net-autostart default
sudo virsh --connect qemu:///system net-start default

# Verify
sudo virsh --connect qemu:///system net-list --all
# Expected: default | attivo | sì | sì
```

### Default URI (optional, makes life easier)

By default `virsh` connects to `qemu:///session` (per-user). Our network
and most VMs live in `qemu:///system`. Either always pass `--connect
qemu:///system`, or set it as the default in your shell:

```sh
# Add to ~/.bashrc
export LIBVIRT_DEFAULT_URI=qemu:///system
```

## Get the Bluefin ISO

Margine ships as a bootc image, not as an ISO. We install Bluefin
first, then rebase. There is no "Bluefin DX ISO" — DX is a post-install
toggle that Margine doesn't need (see
[ADR 0005](adr/0005-base-on-bluefin-dx.md#terminology-clarification)).

```sh
mkdir -p ~/data/inbox/10-downloads
curl -L -o ~/data/inbox/10-downloads/bluefin-stable-x86_64.iso \
    https://download.projectbluefin.io/bluefin-stable-x86_64.iso

# Optional checksum verify
curl -sL https://download.projectbluefin.io/bluefin-stable-x86_64.iso-CHECKSUM \
    | sha256sum -c - --ignore-missing 2>&1 | grep -E "OK|FAILED"
```

## Create the VM

Two paths: the `virt-install` CLI (recommended the first time — the
command line documents every feature explicitly and can be reused or
automated) or the virt-manager GUI (quicker afterwards).

### CLI (`virt-install`)

```sh
virt-install \
    --connect qemu:///system \
    --name margine-smoketest \
    --memory 8192 \
    --vcpus 4 \
    --disk size=64,format=qcow2 \
    --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,loader.secure=yes \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
    --cdrom ~/data/inbox/10-downloads/bluefin-stable-x86_64.iso \
    --os-variant silverblue-rawhide \
    --graphics spice \
    --network network=default \
    --noautoconsole
```

Notes:
- `--os-variant silverblue-rawhide` — on Arch the latest known
  `silverblue-XX` osinfo entry is rawhide. It's just metadata; doesn't
  affect actual install.
- `--noautoconsole` returns immediately. Open the console separately:

```sh
virt-viewer --connect qemu:///system margine-smoketest
```

### GUI (virt-manager)

`File → New Virtual Machine`. Wizard:

1. **Local install media (ISO image or CDROM)** → `Forward`.
2. Browse the Bluefin ISO downloaded above. Leave OS auto-detection
   on — if it doesn't find `Silverblue`, pick `Fedora Silverblue`
   manually (or `Fedora Linux 41` as a fallback).
3. Memory: `8192 MiB`. CPU: `4`. `Forward`.
4. Storage: `Create a disk image`, `64 GiB`. `Forward`.
5. Name: `margine-smoketest`. Network: `Virtual network 'default'`.
   **Tick "Customize configuration before install"**. `Finish`.
6. In the customization window that opens:
   - **Overview → Firmware**: change from `BIOS` to `UEFI x86_64:
     /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd` (or the equivalent
     on your distro). Tick `Secure Boot`.
   - Click `Add Hardware` (bottom left) → `TPM` → Model `CRB`,
     Backend `Emulated`, Version `2.0`. `Finish`.
   - Verify `Boot Options`: tick `SDA Hard Disk` as primary boot,
     leave CDROM secondary. `Apply`.
7. Click `Begin Installation` (top left).

## Install Bluefin

Anaconda walks you through it. Recommended choices:

| Screen | Choose |
| --- | --- |
| Localization | Italian (or your preference) |
| Installation Destination | the 64 GB virtual disk → **enable "Encrypt my data"** (LUKS2) → set passphrase (a simple test value like `margine123` is fine for VM) |
| User Creation | create user with admin privileges |
| Root Password | can be disabled / set same as user |

Click "Begin Installation". 20–30 min. **Reboot** when prompted.

After first boot: LUKS passphrase → desktop Bluefin.

## Rebase to Margine

From the Bluefin desktop, terminal:

```sh
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

First reboot → CachyOS kernel boot. Plymouth (Margine theme) → LUKS
prompt → desktop.

Second reboot:

```sh
systemctl reboot
```

→ MOK Manager screen → Enroll MOK → password (the `MOK_PASSWORD` GH
Actions secret; archived in Bitwarden under "Margine MOK"). Reboot.

Third boot → Margine is now booted under Secure Boot with the
CachyOS kernel.

```sh
mokutil --sb-state          # SecureBoot enabled
mokutil --list-enrolled     # Margine MOK present
uname -r                    # 7.0.x-cachyos*.fc44.x86_64
cat /etc/os-release | head  # NAME=Margine
```

## Apply user-state in one shot

```sh
ujust margine-bootstrap
```

Creates `~/data ~/dev ~/scratch`, XDG remap, Nautilus bookmarks,
o-tiling + Search Light + Hide Cursor + Caffeine extension install,
GNOME extensions enable/disable, keybindings, default apps,
app folders. Logout + login.

## Snapshots and rollback (daily operation)

**Take a snapshot at every "known good" state of the VM.** A fresh
Bluefin install takes 20-30 minutes; a snapshot rollback takes 5
seconds. Internal qcow2 snapshots are copy-on-write: the disk file
grows only with blocks changed FROM that point onwards, so they cost
almost nothing in space.

### From virt-manager (recommended)

1. Open virt-manager, double-click the VM.
2. In the window that opens, click the "View" eye icon or
   `View → Snapshots`. The snapshots panel appears on the left.
3. Power off the VM before taking a snapshot (Power off, not
   Suspend) — that guarantees atomic, consistent snapshots.
4. Click the **`+`** at the bottom of the snapshots panel.
5. Fill in:
   - **Name**: `bluefin-fresh`, `margine-rebased-OK-20260530`, etc.
   - **Description**: one line on why.
6. `Finish`. The snapshot is created in seconds.

To roll back: select the snapshot from the list, click the **`▶`**
button (Run selected snapshot). The VM is stopped and restored to the
saved state in seconds. The current state is lost — take another
snapshot first if you want to keep it.

To delete an old snapshot: select it and click the **`-`** (trash)
button.

### From CLI (alternative, useful for automation)

```sh
# Create a snapshot (VM powered off)
virsh snapshot-create-as margine-smoketest bluefin-fresh \
    "Fresh Bluefin DX install, never rebased" --atomic

# List snapshots
virsh snapshot-list margine-smoketest --tree

# Roll back (the VM is stopped and reverted to the saved state)
virsh snapshot-revert margine-smoketest bluefin-fresh
virsh start margine-smoketest

# Delete a snapshot
virsh snapshot-delete margine-smoketest <name>
```

### When to take snapshots

These two, always:

| Suggested snapshot | When | Why |
| --- | --- | --- |
| `bluefin-fresh` | Right after Bluefin install + first boot verified | Starting point for any future Margine rebase test |
| `margine-stable-<date>` | After rebasing to Margine, MOK enrolled, boot to multi-user verified | A working Margine — if the next build regresses, roll back here instead of redoing everything |

Additional ad-hoc snapshots: before any risky test (custom kernel,
aggressive upgrades), before running a `ujust` recipe you're unsure
of, before enabling the TPM2 PCR policy.

## Recovery (when something breaks)

### First thing to try: roll back to a previous snapshot

If you have snapshots (see the section above), rollback is almost
always the fastest way to recover. It returns the VM to its state
from an hour or a day ago without needing to diagnose what broke.

### Force-off + restart

From virt-manager: right-click the VM → `Force Off`, then `Run`.

From CLI:

```sh
virsh destroy margine-smoketest
virsh start margine-smoketest
virt-viewer margine-smoketest   # opens the graphical console
```

### At GRUB: pick a different deployment

If Margine fails to boot, at the GRUB menu (timeout ~5 s — press
arrow key to interrupt) you can pick the previous deployment (usually
Bluefin) and boot back into a working state.

### Reset to Bluefin from rpm-ostree

```sh
# From within Bluefin (after GRUB-selecting Bluefin entry):
sudo rpm-ostree rollback             # swap default to Bluefin
sudo rpm-ostree cleanup -rmpb        # nuke pending + rollback + metadata + base
# Now you have a clean Bluefin baseline; try `rebase` again or stop here.
```

### Nuke the VM and start fresh

**Last resort.** If you have snapshots, try a rollback first (see
the "Snapshots and rollback" section). A full Bluefin reinstall is
the 20-30 minute cost the snapshots are meant to save you from.

When the VM is genuinely unrecoverable:

From virt-manager: right-click the VM → `Delete...` → tick "Delete
associated storage files" → `Delete`. Then create a new VM with
`File → New Virtual Machine`.

From CLI:

```sh
virsh destroy margine-smoketest 2>/dev/null
virsh undefine margine-smoketest --nvram --remove-all-storage

# Recreate (same virt-install command as "Create the VM" above)
```

## When the VM lab catches its limit

vTPM 2.0 in QEMU is software-emulated (`swtpm`). It works for testing
LUKS auto-unlock end-to-end **without** Secure Boot enrollment in the
PCR policy (use `--tpm2-pcrs=0`). For full PCR `0+7` policy testing
you need real hardware with the Margine MOK enrolled — see
[docs/07-secure-boot-tpm2.md](07-secure-boot-tpm2.md).

## Cross-references

- [docs/02-install-lab.md](02-install-lab.md) — install procedure
  description (links here for VM setup operational details)
- [docs/07-secure-boot-tpm2.md](07-secure-boot-tpm2.md) — TPM2 PCR
  policy details
- [docs/adr/0005-base-on-bluefin-dx.md](adr/0005-base-on-bluefin-dx.md) —
  why Margine ships as Bluefin DX bootc image (and why there is no
  "Bluefin DX ISO")
- [margine-image README install steps](https://github.com/daniel-g-carrasco/margine-image#install)
  — user-facing rebase guide
