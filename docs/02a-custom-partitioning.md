# Custom Partitioning Guide

This document covers how to install Fedora Silverblue with a custom Btrfs
subvolume layout and LUKS2 encryption using the Anaconda graphical installer.

Use this instead of the automatic partitioning described in
[02-install-lab.md](02-install-lab.md) when you want:

- explicit LUKS2 encryption confirmed at install time;
- a dedicated `@data` Btrfs subvolume for `~/data` (personal data, photos,
  media), separate from the rest of the home directory;
- `~/dev` and `~/scratch` as ordinary directories inside `@home`, not separate
  subvolumes (they are reproducible from git or temporary by nature).

## Why this layout

| Subvolume | Mount point | Purpose |
|---|---|---|
| `@root` | `/` (ostree-managed) | OS deployments — do not snapshot manually |
| `@home` | `/var/home` | Home directory — user config, caches, dotfiles |
| `@data` | `/var/home/<user>/data` | Personal data — independent snapshot target |

`@root` is managed by rpm-ostree. OS rollback happens through rpm-ostree
deployments, not Btrfs snapshots. Btrfs subvolumes are used here for data
separation and snapshot independence, not OS rollback.

`~/dev` (code, already in git) and `~/scratch` (temporary work) remain ordinary
directories inside `@home`. They do not need snapshots.

## Target partition layout

For a 64 GiB VM disk:

| Partition | Size | Filesystem | Mount |
|---|---|---|---|
| `vda1` | 600 MiB | vfat (EFI) | `/boot/efi` |
| `vda2` | 1 GiB | ext4 | `/boot` |
| `vda3` | remainder | LUKS2 → Btrfs | see subvolumes |

Btrfs subvolumes inside the LUKS2 container:

| Subvolume | Mount point |
|---|---|
| `@root` | `/` |
| `@home` | `/var/home` |
| `@data` | `/var/home/<user>/data` |

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
- Desired capacity: `600 MiB`

Anaconda will create a vfat EFI System Partition automatically.

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

Anaconda will add a `@home` subvolume. This is where Silverblue places home
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

## Post-install: add the @data subvolume

Anaconda does not support adding a subvolume for `~/data` during the graphical
install. Add it after first boot.

### Find the Btrfs device

```sh
lsblk -f
findmnt /var
```

The Btrfs device is the mapped device under the LUKS container (e.g.,
`/dev/mapper/luks-<uuid>`). Note the UUID of the Btrfs volume:

```sh
sudo btrfs filesystem show
```

### Create the @data subvolume

The Btrfs root (where subvolumes live) is mounted at `/sysroot` or accessible
via the volume device. Mount the Btrfs volume root to create the subvolume:

```sh
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/mapper/luks-<uuid> /mnt/btrfs-root
sudo btrfs subvolume create /mnt/btrfs-root/@data
sudo umount /mnt/btrfs-root
```

Replace `luks-<uuid>` with your actual device name from `lsblk`.

### Mount @data at ~/data via /etc/fstab

Get the Btrfs volume UUID:

```sh
sudo blkid /dev/mapper/luks-<uuid>
```

Add a line to `/etc/fstab`. Because `/etc` is writable on Silverblue but
managed by ostree, edit it carefully:

```sh
sudoedit /etc/fstab
```

Add:

```
UUID=<btrfs-uuid>  /var/home/<user>/data  btrfs  subvol=@data,compress=zstd:1,seclabel,relatime  0 0
```

Replace `<btrfs-uuid>` with the Btrfs volume UUID (not the LUKS UUID) and
`<user>` with your username.

### Create the mount point and test

```sh
mkdir -p ~/data
sudo systemctl daemon-reload
sudo mount ~/data
findmnt ~/data
```

Expected: `~/data` mounted as a separate Btrfs subvolume from `@home`.

### Make it permanent

Reboot and confirm `~/data` mounts automatically:

```sh
findmnt ~/data
btrfs subvolume list /
```

The `@data` subvolume should appear in the list alongside `@home` and `@root`.

## XDG user directories

After the `@data` subvolume is mounted, set the XDG directories to point into
it. Run `xdg-user-dirs-update` with a custom configuration, or set the
variables directly in `~/.config/user-dirs.dirs`:

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
mkdir -p ~/dev
mkdir -p ~/scratch
```

## Snapshot policy (future)

With `@data` as a separate subvolume, you can snapshot it independently:

```sh
sudo btrfs subvolume snapshot ~/data ~/data-snapshots/$(date +%Y%m%d)
```

This does not replace rpm-ostree deployment rollback. It is a separate mechanism
for protecting personal data files independently of OS state.

A Snapper or manual snapshot policy for `@data` is out of scope for phase 1
but can be added in phase 2 alongside the drift detection work.

## Notes

- Do not snapshot `@root` manually. rpm-ostree manages OS rollback through
  deployment pinning, not Btrfs snapshots.
- `/etc` is writable on Silverblue but owned by ostree. The `@data` fstab entry
  persists across deployments because `/etc` changes are carried forward by
  ostree, but verify after a major OS update.
- If Anaconda's graphical custom partitioning behaves unexpectedly for Silverblue,
  the fallback is: use automatic partitioning with encryption enabled, then add
  `@data` post-install as described above. The result is the same.
