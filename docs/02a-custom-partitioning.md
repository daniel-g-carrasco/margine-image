# Custom Partitioning Guide

This document covers how to install Fedora Silverblue with a custom Btrfs
subvolume layout and LUKS2 encryption using the Anaconda graphical installer.

Use this instead of the automatic partitioning described in
[02-install-lab.md](02-install-lab.md) when you want:

- explicit LUKS2 encryption confirmed at install time;
- a dedicated `@data` Btrfs subvolume for `~/data` (personal data, photos,
  media), separate from the rest of the home directory;
- nested Btrfs subvolumes for `~/.cache`, `~/dev`, and `~/scratch` so that
  snapshots of `home` capture only the high-value dotfile area and exclude
  regenerable, git-backed, or disposable content automatically.

## Why this layout

The home directory contains content with very different snapshot value:

| Sub-area | Typical size | Snapshot value | Reason |
|---|---|---|---|
| `.config`, `.local`, `.ssh`, `.gnupg`, browser profiles | ~20 GiB | **high** | small, evolves slowly, no remote copy |
| `~/data` | hundreds of GiB to TiB | own policy | already covered by external backup (e.g. Koofr) |
| `~/dev` | tens to hundreds of GiB | **none** | git remote is the source of truth |
| `~/scratch` | small but churn | **none** | disposable by contract |
| `~/.cache` | 10s of GiB | **none** | fully regenerable, constant churn |

A flat `home` snapshot would gulp the regenerable, git-backed, and disposable
areas together with the dotfiles. The design below makes the dotfile region a
clean snapshot target by isolating everything else into its own subvolume.

In Btrfs, a subvolume nested inside another subvolume is **automatically
excluded from snapshots of the parent**. That is the property used here:
nested subvolumes for `.cache`, `dev`, and `scratch` keep the user-visible
paths identical while removing them from `home` snapshot scope at zero cost.

### Subvolume table

Anaconda on Fedora names the top-level subvolumes `root`, `home`, `var`
(no `@` prefix — Fedora style; the `@` prefix is an Arch/openSUSE convention).
For consistency with the Fedora-created subvolumes, the only subvolume we
add at the top level keeps the `@` prefix only to make it visually distinct
in `btrfs subvolume list` as "ours, not Anaconda's". Nested subvolumes have
no separate name — they are identified by their path inside the parent.

| Subvolume (as in `btrfs subvolume list`) | Mount point | Snapshot intent |
|---|---|---|
| `root` (Anaconda) | `/` (ostree-managed) | OS rollback handled by rpm-ostree, not Btrfs |
| `home` (Anaconda) | `/var/home` | snapshot target — dotfiles and user state only |
| `var` (Anaconda) | `/var` | system writable state |
| `home/<user>/.cache` (nested in `home`) | `/var/home/<user>/.cache` | excluded from `home` snapshots (regenerable) |
| `home/<user>/dev` (nested in `home`) | `/var/home/<user>/dev` | excluded from `home` snapshots (git-backed) |
| `home/<user>/scratch` (nested in `home`) | `/var/home/<user>/scratch` | excluded from `home` snapshots (disposable) |
| `@data` (top-level, our addition) | `/var/home/<user>/data` | independent subvolume, own backup policy |

`root` is managed by rpm-ostree. OS rollback happens through rpm-ostree
deployments, not Btrfs snapshots. Btrfs subvolumes here are used for data
separation and snapshot scope control, not for OS rollback.

Nested subvolumes appear in `btrfs subvolume list /sysroot` with `top level`
equal to the parent subvolume's ID (e.g. `top level 257` when `home` has ID
257). That `top level` relation is what makes Btrfs automatically exclude
them from snapshots of the parent.

## Target partition layout

For a 64 GiB VM disk:

| Partition | Size | Filesystem | Mount |
|---|---|---|---|
| `vda1` | 2 GiB | vfat (EFI) | `/boot/efi` |
| `vda2` | 1 GiB | ext4 | `/boot` |
| `vda3` | remainder | LUKS2 → Btrfs | see subvolumes |

The EFI partition is sized at 2 GiB to avoid running out of space over time.
On systems with multiple kernels, Secure Boot shim copies, and UKI experiments,
512 MiB fills up quickly. 2 GiB is comfortable; 4 GiB is future-proof if the
disk is large enough.

## Step-by-step: Anaconda custom partitioning

### 1. Start the installer

Boot the VM from the Fedora Silverblue ISO. When the GRUB menu appears, select
"Start Fedora-Silverblue-ostree-x86_64-44" and wait for the live desktop to
load. Then launch the installer ("Install to Hard Drive").

### 2. Open Installation Destination

In the Anaconda summary screen, click **Installation Destination**. Select the
target disk. Under "Storage Configuration", choose **Custom** and click **Done**.

### 3. Choose the partitioning scheme

At the top of the manual partitioning screen, set the partitioning scheme to
**Btrfs**.

### 4. Create the EFI partition

Click **+** (add mount point):

- Mount point: `/boot/efi`
- Desired capacity: `2048 MiB` (2 GiB) — or `4096 MiB` on larger disks

Anaconda will create a vfat EFI System Partition automatically. The larger size
prevents space issues as kernels, Secure Boot shim files, and future UKI entries
accumulate over time.

### 5. Create the /boot partition

Click **+**:

- Mount point: `/boot`
- Desired capacity: `1 GiB`

Set the filesystem to **ext4**. Do not encrypt `/boot`.

### 6. Create the root Btrfs volume with encryption

Click **+**:

- Mount point: `/`
- Desired capacity: leave blank (use all remaining space)

Anaconda will create a Btrfs volume. Check **Encrypt** and set a passphrase.
This creates the LUKS2 container over the remaining disk space. Anaconda will
create a Btrfs volume inside it and an initial subvolume for `/`.

Note the LUKS passphrase somewhere safe — it is the recovery fallback for TPM2
auto-unlock later.

### 7. Add the /var/home subvolume

Inside the same Btrfs volume, click **+**:

- Mount point: `/var/home`
- Desired capacity: leave blank — Btrfs subvolumes share the pool

Anaconda will add a `home` subvolume. This is where Silverblue places home
directories (`/home` is a symlink to `/var/home`).

### 8. Verify and accept

Click **Done** and review the summary:

- `/boot/efi` — vfat — unencrypted ✓
- `/boot` — ext4 — unencrypted ✓
- `/` — Btrfs — encrypted (LUKS2) ✓
- `/var/home` — Btrfs subvolume — inside the same encrypted pool ✓

Accept the changes and continue the installation. Set your timezone, keyboard,
and user account, then click **Begin Installation**.

### 9. Reboot and confirm encryption

After installation and reboot, you should be prompted for the LUKS passphrase
before the system boots. If the LUKS prompt appears, encryption is working.

Confirm with:

```sh
lsblk -f
```

Expected output: a `crypto_LUKS` device (e.g., `vda3`) with a `dm-X` mapped
device inside it that holds the Btrfs pool.

## Post-install: create the additional subvolumes

Anaconda does not support creating nested subvolumes or the `@data` subvolume
during the graphical install. Create them after first boot, before populating
the affected directories.

### Find the Btrfs device

```sh
lsblk -f
findmnt /var
sudo btrfs filesystem show
```

The Btrfs device is the mapped device under the LUKS container (e.g.,
`/dev/mapper/luks-<uuid>`). Note the Btrfs volume UUID from
`btrfs filesystem show`.

### Mount the Btrfs root and create the top-level @data subvolume

The Btrfs root (where top-level subvolumes live, `subvolid=5`) is not normally
mounted. Mount it temporarily to create `@data`:

```sh
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/mapper/luks-<uuid> /mnt/btrfs-root
sudo btrfs subvolume create /mnt/btrfs-root/@data
sudo umount /mnt/btrfs-root
```

Replace `luks-<uuid>` with your actual device name from `lsblk`.

### Create the nested subvolumes inside `home`

Nested subvolumes are created as paths *inside the parent subvolume's normal
mount point*. They use the same Btrfs pool but are tracked as independent
subvolumes and are excluded from snapshots of the parent.

Order matters: create each nested subvolume **before** any data exists at that
path, otherwise the existing directory blocks the subvolume creation.

```sh
# On a fresh install, ~/.cache and ~/dev/~/scratch do not yet exist for the
# user, or they exist as empty directories. Remove any empty directory first
# if needed, then create as subvolumes.

sudo -u <user> mkdir -p /var/home/<user>
sudo rmdir /var/home/<user>/.cache 2>/dev/null || true

sudo -u <user> btrfs subvolume create /var/home/<user>/.cache
sudo -u <user> btrfs subvolume create /var/home/<user>/dev
sudo -u <user> btrfs subvolume create /var/home/<user>/scratch
```

If `~/.cache` already contains data from first login (likely), back it up,
remove it, recreate as a subvolume, and restore:

```sh
sudo mv /var/home/<user>/.cache /var/home/<user>/.cache.old
sudo -u <user> btrfs subvolume create /var/home/<user>/.cache
sudo -u <user> rsync -a /var/home/<user>/.cache.old/ /var/home/<user>/.cache/
sudo rm -rf /var/home/<user>/.cache.old
```

Confirm the result:

```sh
sudo btrfs subvolume list /sysroot
```

Expected output includes lines like:

```
ID 257 gen ... top level 5 path home
ID 258 gen ... top level 5 path data
ID 259 gen ... top level 257 path home/<user>/.cache
ID 260 gen ... top level 257 path home/<user>/dev
ID 261 gen ... top level 257 path home/<user>/scratch
```

`top level 257` (the ID of `home`) confirms the three are nested inside
`home` and will be excluded from its snapshots automatically.

### Mount @data at ~/data via /etc/fstab

Nested subvolumes do not need fstab entries — Btrfs auto-mounts them as part of
the parent. Only `@data` needs an fstab entry because it is a top-level
subvolume that must be bind-mounted into the home tree.

Get the Btrfs volume UUID:

```sh
sudo blkid /dev/mapper/luks-<uuid>
```

Add to `/etc/fstab`:

```sh
sudoedit /etc/fstab
```

Add:

```
UUID=<btrfs-uuid>  /var/home/<user>/data  btrfs  subvol=@data,compress=zstd:1,seclabel,relatime  0 0
```

Replace `<btrfs-uuid>` with the Btrfs volume UUID (not the LUKS UUID) and
`<user>` with your username.

### Mount and verify

```sh
mkdir -p /var/home/<user>/data
sudo systemctl daemon-reload
sudo mount /var/home/<user>/data
findmnt /var/home/<user>/data
findmnt /var/home/<user>/.cache
findmnt /var/home/<user>/dev
findmnt /var/home/<user>/scratch
```

All four should appear as Btrfs mounts. Reboot once and confirm they all mount
automatically — the three nested ones via Btrfs auto-mount, `@data` via fstab.

## XDG user directories

After the subvolumes are in place, set the XDG directories to point into
`~/data`. Set the variables in `~/.config/user-dirs.dirs`:

```ini
XDG_DESKTOP_DIR="$HOME/"
XDG_DOWNLOAD_DIR="$HOME/data/inbox/10-downloads"
XDG_TEMPLATES_DIR="$HOME/data/templates"
XDG_PUBLICSHARE_DIR="$HOME/data/shared"
XDG_DOCUMENTS_DIR="$HOME/data/personal"
XDG_MUSIC_DIR="$HOME/data/media/audio"
XDG_PICTURES_DIR="$HOME/data/media/photos"
XDG_VIDEOS_DIR="$HOME/data/media/video"
```

Create the directory tree:

```sh
mkdir -p ~/data/inbox/10-downloads
mkdir -p ~/data/templates
mkdir -p ~/data/shared
mkdir -p ~/data/personal
mkdir -p ~/data/media/{audio,photos,video}
mkdir -p ~/data/projects
```

`~/dev` and `~/scratch` already exist as subvolume roots from the post-install
step; populate them as needed.

## Snapshot policy

With the nested layout in place, a snapshot of `home` automatically captures
only the dotfile area:

```sh
sudo btrfs subvolume snapshot -r /var/home /var/home/.snapshots/$(date +%Y%m%d)
```

The snapshot includes `.config`, `.local`, `.ssh`, `.gnupg`, `.var`, browser
profiles, etc., and is typically a few tens of GiB. It excludes `.cache`,
`dev`, `scratch`, and `data` automatically — they are separate subvolumes.

`@data` can be snapshotted independently when needed:

```sh
sudo btrfs subvolume snapshot -r /var/home/<user>/data /var/home/<user>/data/.snapshots/$(date +%Y%m%d)
```

A Snapper or systemd-timer policy for `home` and `@data` is out of scope for
phase 1 but can be added in phase 2 alongside the drift detection work. The
subvolume layout above is the precondition that makes such a policy useful.

## Notes

- Do not snapshot `root` manually. rpm-ostree manages OS rollback through
  deployment pinning, not Btrfs snapshots.
- `/etc` is writable on Silverblue but owned by ostree. The `@data` fstab entry
  persists across deployments because `/etc` changes are carried forward by
  ostree, but verify after a major OS update.
- SQLite databases inside `~/.config` (Firefox `places.sqlite`, etc.) can
  fragment under CoW. If write amplification becomes visible, mark the
  individual files with `chattr +C` after recreating them empty. Not a phase 1
  concern but documented for later.
- If Anaconda's graphical custom partitioning behaves unexpectedly for
  Silverblue, the fallback is: use automatic partitioning with encryption
  enabled, then add `@data` and the nested subvolumes post-install as described
  above. The end result is the same.
