# GNOME Personal Layer

This document covers the personal layer that can be carried over from
`/home/daniel/dev/margine-os-personal`: fonts, GNOME theme choices, icon policy,
folder metadata, XDG user directories, and home organization.

The rule is the same as the rest of this project: carry the intent, not the Arch
implementation.

## Sources Reviewed

Local inputs:

- `manifests/packages/fonts.txt`
- `manifests/packages/aur-baseline.txt`
- `manifests/packages/toolkit-gtk-qt.txt`
- `docs/adr/0043-home-organization-baseline.md`
- `docs/runbooks/home-organization-post-install.md`
- `docs/audits/2026-04-24-audit-fix-tranche-2.md`
- `docs/audits/2026-04-29-session-handoff.md`
- `files/home/.config/margine/theme.env`
- `files/home/.config/gtk-3.0/settings.ini`
- `files/home/.config/gtk-4.0/settings.ini`
- `files/home/.local/bin/margine-home-*`
- `files/home/.local/share/icons/Margine-Adwaita/index.theme`

Fedora 44 package availability was checked with `dnf repoquery` in a clean
`fedora:44` container.

## Decision Summary

Carry over:

- the `~/data`, `~/dev`, `~/scratch` home model;
- XDG user directory mappings;
- compact GTK/Nautilus bookmarks;
- managed folder readmes;
- backup exclusion example;
- GIO folder icon metadata as a user-session feature;
- GNOME/Adwaita-first icon direction;
- a curated font policy;
- dark mode and GNOME accent preferences;
- GTK3 compatibility through Fedora packages if needed.

Do not carry over as phase 1 defaults:

- AUR font packages;
- `yay`;
- `ttf-ioskeley-mono`;
- `ttf-ms-fonts`;
- `adwaita-colors-icon-theme`;
- `morewaita-icon-theme`;
- Hyprland theme files;
- Waybar, Walker, Fuzzel, SwayNC, SwayOSD theme generation;
- `hyprqt6engine`, `qt5ct`, or `qt6ct` as baseline session policy;
- generated GTK4/Rewaita CSS as a first-pass GNOME default.

## Home Layout

Use the existing Margine home model under Silverblue's normal `/var/home`
surface:

| Root | Purpose |
| --- | --- |
| `~/data` | durable personal, work, media, library, technology, shared, and archive data |
| `~/dev` | source repositories and development sandboxes |
| `~/scratch` | disposable work, temporary downloads, mobile staging, media caches |

The top-level rule still fits Fedora Atomic because it writes only to user home.
No mutable root filesystem is required.

On the Margine Fedora Atomic install, `~/.cache`, `~/dev`, `~/scratch`, and
`~/data` are realized as separate Btrfs subvolumes so that snapshots of
`@home` capture only the dotfile area. The user-visible paths are identical;
the snapshot scope is what changes. See
[02a-custom-partitioning.md](02a-custom-partitioning.md) for the design and
post-install steps.

Initial XDG mapping:

| XDG directory | Target |
| --- | --- |
| Desktop | `$HOME/` |
| Downloads | `$HOME/data/inbox/10-downloads` |
| Documents | `$HOME/data/personal` |
| Pictures | `$HOME/data/media/photos` |
| Music | `$HOME/data/media/audio` |
| Videos | `$HOME/data/media/video` |
| Templates | `$HOME/data/templates` |
| Public | `$HOME/data/shared` |
| Projects | `$HOME/data/projects` |

Initial GTK/Nautilus bookmarks:

```text
~/data/personal              Documents
~/data/inbox/10-downloads    Downloads
~/data/media/photos          Pictures
~/data/media/audio           Music
~/data/media/video           Videos
~/data/shared                Shared
~/data/projects              Projects
~/dev                        Development
~/scratch                    Scratch
```

Migration rule:

- create the new layout;
- write XDG mappings and bookmarks;
- remove only empty legacy folders such as `~/Documents`, `~/Downloads`,
  `~/Pictures`, `~/Documenti`, `~/Scaricati`, and `~/Immagini`;
- preserve non-empty legacy folders for manual migration.

## Folder Icons

Carry over the concept, but make it tolerant of Fedora's available icon themes.

The old policy preferred `Adwaita-yellow` scalable SVG folder icons, then used
MoreWaita and Adwaita fallbacks. Fedora 44 repositories provide
`adwaita-icon-theme`, `adwaita-icon-theme-legacy`, `papirus-icon-theme`, and
related themes, but the old Arch/AUR `adwaita-colors-icon-theme` and
`morewaita-icon-theme` names are not Fedora baseline packages.

Phase 1 policy:

- keep the session icon theme GNOME/Adwaita-first;
- keep app icons on Fedora/GNOME defaults;
- use a small `Margine-Adwaita` user icon overlay only for Margine-specific
  launchers if needed;
- write folder icons through GIO `metadata::custom-icon` only when the selected
  icon file exists;
- prefer scalable SVG folder icons;
- do not write raster 16x16 PNG folder icons into folder metadata;
- treat colored folder icons as optional until a Fedora-native source is chosen.

Semantic folder mappings remain useful:

| Folder | Preferred semantic icon |
| --- | --- |
| `~/data` | `folder-earth` |
| `~/data/library` | `folder-books` |
| `~/data/work` | `folder-work` |
| `~/data/media` | `folder-camera` |
| `~/data/library/software` | `folder-appimage` |
| `~/dev` | `folder-code` |
| `~/scratch` | `folder-temp` |

If Fedora's installed icon themes do not provide those exact names, the first
implementation should fall back to a generic scalable folder icon instead of
installing a non-Fedora icon stack immediately.

## Fonts

Do not translate the Arch font manifest literally.

Old Arch choices with Fedora-specific handling:

| Old item | Fedora Atomic decision |
| --- | --- |
| `noto-fonts*` | use Fedora `google-noto-*` packages only where missing from Silverblue |
| Source Sans/Serif/Code | available as Fedora packages |
| Atkinson Hyperlegible | available as Fedora packages |
| IBM Plex | available as Fedora packages |
| Carlito/Caladea/Liberation | good Office-compatible defaults in Fedora |
| Iosevka / Ioskeley / Nerd variants | not a clean Fedora 44 baseline; use user fonts or a later custom package if required |
| Microsoft core fonts | not a default; prefer Carlito, Caladea, and Liberation |

Candidate host-layer packages after baseline validation:

```text
adobe-source-code-pro-fonts
adobe-source-sans-pro-fonts
adobe-source-serif-pro-fonts
atkinson-hyperlegible-next-fonts
atkinson-hyperlegible-mono-fonts
ibm-plex-sans-fonts
ibm-plex-mono-fonts
ibm-plex-serif-fonts
google-carlito-fonts
google-crosextra-caladea-fonts
liberation-sans-fonts
liberation-serif-fonts
liberation-mono-fonts
google-noto-color-emoji-fonts
google-noto-sans-cjk-fonts
jetbrains-mono-fonts
```

Phase 1 GNOME default:

- keep Fedora/GNOME defaults until the lab records what Silverblue ships;
- if a Margine override is desired, prefer `IBM Plex Sans 10` or
  `Atkinson Hyperlegible Next 10` for UI;
- prefer `JetBrains Mono 11`, `IBM Plex Mono 11`, or `Source Code Pro 11` for
  terminal/code until an Ioskeley/Iosevka packaging decision exists.

User-installed fonts belong under:

```text
~/.local/share/fonts/margine
```

Use that path only for fonts with reviewed licenses and reproducible source
archives.

## GNOME Theme Policy

GNOME is the desktop environment in phase 1. That changes the theme policy.

Carry over:

- `org.gnome.desktop.interface color-scheme` set to `prefer-dark`;
- GNOME/libadwaita accent color, starting with `yellow` if supported by the
  target GNOME release;
- GTK3 compatibility through Fedora's `adw-gtk3-theme`;
- Bluefin-inspired GNOME polish: hot corners off, subpixel `rgba` font
  antialiasing, dash-to-dock (fixed + dynamic transparency), Blur My
  Shell on top bar + overview, Just Perfection trims (no app-menu, no
  weather/world-clock noise);
- Zen Browser and Thunderbird as the default browser and mail client.

Do not carry over initially:

- generated GTK4 CSS;
- Rewaita as a global GTK4 override;
- Waybar/Walker/Fuzzel/SwayNC theme artifacts;
- forced Qt platform themes from the Hyprland session.

GTK4/libadwaita applications should stay close to upstream GNOME behavior in
phase 1. The only shell-extension styling we apply is through Forge's own
gsettings schema, not through a custom GNOME Shell theme.

Apply the appearance baseline:

```sh
scripts/configure-gnome-appearance         # dry-run: print plan
scripts/configure-gnome-appearance --apply # write via gsettings
```

The script is user-state only. It does not install extensions, enable
extensions, or modify the rpm-ostree deployment.

## GNOME Extensions

The phase 1 GNOME extension set:

| Extension | Source | Role |
| --- | --- | --- |
| `appindicatorsupport@rgcjonas.gmail.com` | Fedora (`gnome-shell-extension-appindicator`) | legacy tray icons (Bitwarden, Steam, etc.) |
| `blur-my-shell@aunetx` | Fedora (`gnome-shell-extension-blur-my-shell`) | transparent/blurred top bar + overview (Bluefin-style) |
| `dash-to-dock@micxgx.gmail.com` | Fedora (`gnome-shell-extension-dash-to-dock`) | fixed semi-transparent dock with running-app dots |
| `just-perfection-desktop@just-perfection` | Fedora (`gnome-shell-extension-just-perfection`) | trims shell elements (hot corner, app-menu, weather, etc.) |
| `workspace-indicator@gnome-shell-extensions.gcampax.github.com` | Fedora (`gnome-shell-extension-workspace-indicator`) | numeric top-bar workspace indicator |
| `tilingshell@ferrarodomenico.com` | user-install from extensions.gnome.org | tiling window manager (replaces Forge, which is unmaintained) |

Apply the full set:

```sh
scripts/install-user-extensions --apply       # downloads Tiling Shell
scripts/configure-gnome-extensions --apply    # enables all listed
scripts/configure-gnome-keybindings --apply   # workspace + tiling binds
scripts/configure-gnome-appearance --apply    # dconf settings + ext-specific tweaks
```

GNOME's native `SUPER+1..0` bindings only activate existing workspaces. They
do not create arbitrary numbered workspaces like Hyprland.

GNOME's native `SUPER+1..0` bindings only activate existing workspaces. They
do not create arbitrary numbered workspaces like Hyprland.

## Channels

| Item | Channel |
| --- | --- |
| XDG dirs, GTK bookmarks, folder readmes | user home |
| Folder icon metadata | user session via GIO |
| Margine-specific launcher icons | user icon overlay or future image layer |
| Fonts needed by host and Flatpaks | rpm-ostree layer after baseline |
| Experimental custom fonts | user font directory first |
| GTK3 compatibility theme | rpm-ostree layer if needed |
| GNOME settings | user dconf/gsettings |
| GUI apps | Flatpak |
| development font/tool experiments | toolbox or user home |

## App Grid Folders

The GNOME Activities app grid can be organised into folders that group
related applications. This makes a grid with many installed apps
scannable instead of one long alphabetical list.

The folder layout is declared in `gnome.app_folders.list` in
`declarations/margine-atomic.yaml` and applied by
`scripts/configure-gnome-app-folders --apply`. Each folder includes
applications by:

- **`apps`**: explicit `.desktop` file ids — pins specific Flatpaks
  even if their XDG categories change upstream;
- **`categories`**: XDG categories — absorbs new compatible apps
  automatically when they are installed.

The phase 1 layout:

| Folder | Pinned apps | Auto-categories |
| --- | --- | --- |
| Internet | Zen Browser | — |
| Productivity | Bitwarden, Thunderbird, LibreOffice suite | Office |
| Graphics | GIMP, Inkscape | Graphics, 2DGraphics, VectorGraphics, RasterGraphics |
| Photography | darktable | Photography |
| Multimedia | Gapless, Audacity, OBS Studio, EasyEffects, Reaper | AudioVideo, Audio, Video, Music |
| Development | VSCodium | Development, IDE |
| Utilities | — | Utility, Accessibility |
| System | — | System, Settings |

The Utilities and System folders are category-only on purpose: they
absorb whatever GNOME core apps the distribution ships (Files, Settings,
Disks, Console, etc.) without naming each one. New installations that
match those categories appear in the folder automatically.

Apply the layout:

```sh
scripts/configure-gnome-app-folders         # dry-run: print plan
scripts/configure-gnome-app-folders --apply # write via gsettings
```

After applying, restart GNOME Shell (Alt+F2 → type `r` → Enter on
Xorg, or log out / log back in on Wayland) for the grid to refresh.

Reset the folder configuration:

```sh
scripts/configure-gnome-app-folders --reset --apply
```

This removes all folder definitions; the grid returns to the flat
alphabetical default.

## Validation Commands

Run after the GNOME personal layer is applied:

```sh
gsettings get org.gnome.desktop.interface color-scheme
gsettings get org.gnome.desktop.interface accent-color
gsettings get org.gnome.desktop.interface font-name
gsettings get org.gnome.desktop.interface monospace-font-name
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.interface icon-theme
gsettings get org.gnome.mutter dynamic-workspaces
gsettings get org.gnome.desktop.wm.preferences workspace-names
gsettings get org.gnome.desktop.wm.keybindings switch-to-workspace-4
gnome-extensions list --enabled | grep workspace-indicator
gsettings get org.gnome.shell.extensions.forge focus-border-color
gsettings get org.gnome.shell.extensions.forge window-gap-hidden-on-single
cat ~/.config/user-dirs.dirs
sed -n '1,120p' ~/.config/gtk-3.0/bookmarks
sed -n '1,120p' ~/.config/gtk-4.0/bookmarks
gio info -a metadata::custom-icon ~/data ~/data/library ~/data/work ~/data/media ~/dev ~/scratch
fc-match "IBM Plex Sans"
fc-match "Atkinson Hyperlegible Next"
fc-match "JetBrains Mono"
flatpak list
```

Pass criteria:

- GNOME still uses its native shell, lock screen, portals, and settings UI;
- XDG directories point to the Margine home layout;
- Nautilus and GTK file pickers show the compact bookmarks;
- folder metadata does not point to missing files;
- fonts resolve through Fedora packages or reviewed user fonts;
- no Hyprland, Waybar, Walker, Fuzzel, or AUR dependency is required for the
  visual baseline.
