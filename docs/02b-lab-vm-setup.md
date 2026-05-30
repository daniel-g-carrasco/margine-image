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

## Operare da GUI o da CLI

Tutte le operazioni sotto possono essere fatte sia da **virt-manager**
(GUI grafica) sia da `virsh` / `virt-install` (CLI). La guida mostra
**entrambe**, con la GUI come metodo preferito per le operazioni
quotidiane (snapshot, start/stop, console viewer) e la CLI per le
operazioni complesse o ripetibili (creazione VM con vTPM + Secure Boot,
script di automazione).

Apri virt-manager con il comando omonimo. Connetti se necessario:
`File → Add Connection... → QEMU/KVM`, host locale, system level
(`qemu:///system`).

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

Si puo' fare in due modi: CLI con `virt-install` (consigliato la prima
volta perche' la riga di comando documenta ogni feature in modo
esplicito, e si puo' riusare/automatizzare) oppure GUI virt-manager
(piu' veloce in seguito).

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
2. Browse l'ISO Bluefin scaricato sopra. Lascia detection automatica
   OS — se non trova `Silverblue`, scegli manualmente `Fedora Silverblue`
   (o `Fedora Linux 41` come fallback).
3. Memory: `8192 MiB`. CPU: `4`. `Forward`.
4. Storage: `Create a disk image`, `64 GiB`. `Forward`.
5. Name: `margine-smoketest`. Network: `Virtual network 'default'`.
   **Tick "Customize configuration before install"**. `Finish`.
6. Nella finestra di customizzazione che si apre:
   - **Overview → Firmware**: cambia da `BIOS` a `UEFI x86_64:
     /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd` (o equivalente del
     tuo distro). Tick `Secure Boot`.
   - Click `Add Hardware` (in basso a sinistra) → `TPM` → Model
     `CRB`, Backend `Emulated`, Version `2.0`. `Finish`.
   - Verifica `Boot Options`: tick `SDA Hard Disk` come boot primario,
     lascia CDROM secondario. `Apply`.
7. Click `Begin Installation` (alto a sinistra).

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
Tiling Shell, Search Light, GNOME extensions enable/disable,
keybindings, default apps, app folders. Logout + login.

## Snapshot e rollback (operazione quotidiana)

**Fai snapshot ad ogni stato "buono" della VM.** Reinstallare Bluefin
da zero richiede 20-30 minuti; un rollback a snapshot richiede 5
secondi. Gli snapshot interni qcow2 sono copy-on-write: il file disco
cresce solo dei blocchi modificati DA quel punto in poi, quindi
costano pochissimo spazio.

### Da virt-manager (consigliato)

1. Apri virt-manager, doppio click sulla VM.
2. Nella finestra che si apre, click sul'icona "Vista" (occhio) o
   `View → Snapshots`. Si apre il pannello snapshot a sinistra.
3. Spegni la VM prima di fare lo snapshot (Power off, non
   Suspend) — questo garantisce snapshot atomici e coerenti.
4. Click sul **`+`** in basso a sinistra del pannello snapshot.
5. Compila:
   - **Name**: `bluefin-fresh`, `margine-rebased-OK-20260530`, ecc.
   - **Description**: una riga sul perche'.
6. `Finish`. Lo snapshot e' creato in pochi secondi.

Per fare rollback: seleziona lo snapshot dalla lista, click sul tasto
**`▶`** (Run selected snapshot). La VM viene fermata e ripristinata
allo stato salvato in pochi secondi. Lo stato corrente viene perso —
se vuoi salvarlo prima, crea un altro snapshot.

Per cancellare uno snapshot vecchio: selezionalo e click sul **`-`**
(cestino).

### Da CLI (alternativa, utile per automazione)

```sh
# Crea snapshot (VM spenta)
virsh snapshot-create-as margine-smoketest bluefin-fresh \
    "Bluefin DX appena installato, mai rebasato" --atomic

# Lista snapshot
virsh snapshot-list margine-smoketest --tree

# Rollback (la VM viene fermata e riportata allo stato salvato)
virsh snapshot-revert margine-smoketest bluefin-fresh
virsh start margine-smoketest

# Cancella uno snapshot
virsh snapshot-delete margine-smoketest <name>
```

### Quando fare snapshot

Almeno questi due, sempre:

| Snapshot suggerito | Quando | A cosa serve |
| --- | --- | --- |
| `bluefin-fresh` | Subito dopo install Bluefin + primo boot OK | Punto di partenza per qualsiasi test rebase Margine |
| `margine-stable-<data>` | Dopo rebase Margine, MOK enrolled, boot a multi-user verificato | Margine funzionante — se la build successiva ha regressioni, rollback qui invece di rifare tutto |

Snapshot aggiuntivi su misura: prima di test rischiosi (kernel custom,
upgrade aggressivi), prima di ujust su cui non sei sicuro, prima di
abilitare TPM2 PCR policy.

## Recovery (when something breaks)

### Prima cosa da provare: rollback a uno snapshot precedente

Se hai snapshot (vedi sezione sopra), il rollback e' quasi sempre la
strada piu' veloce per recuperare. Riporta la VM allo stato di un'ora
o un giorno prima senza dover indagare cosa si e' rotto.

### Force-off + restart

Da virt-manager: tasto destro sulla VM → `Force Off`, poi `Run`.

Da CLI:

```sh
virsh destroy margine-smoketest
virsh start margine-smoketest
virt-viewer margine-smoketest   # apre la console grafica
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

**Ultimo resort.** Se hai snapshot, prima prova un rollback (vedi
sezione "Snapshot e rollback"). Una reinstall completa di Bluefin
richiede 20-30 minuti che gli snapshot ti risparmiano.

Quando proprio la VM e' irrecuperabile:

Da virt-manager: tasto destro sulla VM → `Delete...` → spunta
"Delete associated storage files" → `Delete`. Poi crea una nuova VM
con `File → New Virtual Machine`.

Da CLI:

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
