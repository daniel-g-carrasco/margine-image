# Keyboard Bindings

This document defines the Margine keyboard layout for GNOME, ported from the
Hyprland config of `margine-os-personal`
(`files/home/.config/hypr/conf.d/60-binds.conf`). The goal is to keep the
muscle memory across the two systems while using GNOME-native mechanisms
wherever possible.

The model is fully declarative — every binding lives in
`gnome.keybindings` in `declarations/margine-atomic.yaml` and is applied by
`scripts/configure-gnome-keybindings --apply`. There is no per-machine
manual configuration in GNOME Settings → Keyboard.

## Mechanism

GNOME distinguishes five surfaces, each with its own gsettings schema:

| Surface | Schema | Used for |
| --- | --- | --- |
| Window manager | `org.gnome.desktop.wm.keybindings` | workspace navigation, window close/fullscreen/always-on-top |
| Shell | `org.gnome.shell.keybindings` | overview, application view, screenshot UI, message tray |
| Media keys | `org.gnome.settings-daemon.plugins.media-keys` | lock screen, audio/brightness hardware keys |
| Custom slots | `...media-keys.custom-keybinding:/path/` | arbitrary `command + binding` pairs (app launchers) |
| Extension | `org.gnome.shell.extensions.o-tiling` | o-tiling tiling actions (keys live directly under the schema, not a `.keybindings` sub-path) |

A 6th surface — `org.gnome.mutter` + `org.gnome.desktop.wm.preferences` —
controls the workspace model (`dynamic-workspaces=true`) and workspace names.
The numeric top-bar workspace indicator is provided by Fedora's packaged
`workspace-indicator@gnome-shell-extensions.gcampax.github.com` extension.

## Workspace model

| Setting | Value | Why |
| --- | --- | --- |
| `dynamic-workspaces` | `true` | Avoids pre-creating ten empty workspaces; GNOME creates/removes them as windows move |
| `workspace-names` | `1` ... `10` | Gives GNOME/extension UIs numeric labels where they expose workspace names |
| `count` | `10` | Declarative static fallback; only written to `num-workspaces` if `dynamic=false` |

GNOME's native `switch-to-workspace-N` bindings only activate existing
workspaces. They do not create workspace 4 if only workspaces 1 and 2 exist.
That is a GNOME workspace-model difference from Hyprland. Margine keeps the
native bindings instead of replacing them with a custom extension.

## Hyprland → GNOME mapping

The full set, grouped by purpose. Source: `60-binds.conf`. Destination
schema in the legend column (W = WM, S = Shell, M = media-keys, C = custom,
T = o-tiling).

### Launcher / overview

| Hyprland | GNOME key | Schema |
| --- | --- | --- |
| `SUPER+SPACE` (Walker) | `toggle-application-view` | S |
| `SUPER SHIFT+SPACE` (Fuzzel fallback) | `toggle-overview` | S |
| `SUPER+R` (primary launcher) | `toggle-application-view` (alias) | S |

### Application launchers (custom slots — run a command)

| Hyprland | Command | Override note |
| --- | --- | --- |
| `SUPER+RETURN` | `ptyxis` | terminal default is **Ptyxis** (Bluefin's default; previous design used kitty, dropped 2026-05-26) |
| `SUPER SHIFT+RETURN` | `flatpak run app.zen_browser.zen` | |
| **`SUPER+E`** | `nautilus` | **override of `SUPER SHIFT+F`** — `E` is the recurring desktop convention for "Explorer/Files" |
| `SUPER CTRL+T` | `ptyxis -- btop` | btop lives in the toolbox; runs inside Ptyxis |
| `SUPER+ESCAPE` | `gnome-session-quit --logout` | replaces the `open-session-actions-menu` helper |
| `SHIFT+Print` | `gnome-screenshot -ac` | takes a region screenshot to clipboard (GNOME shell handles SUPER+Print and bare Print as full UIs) |
| `SUPER+PERIOD` | `flatpak run it.mijorus.smile` | Smile emoji picker. **IBus's emoji panel also defaults to `<Super>period`** and grabs it at the input-method layer (you get emoji-input "special characters" instead of Smile), so Margine clears `org.freedesktop.ibus.panel.emoji hotkey` in `07-margine-custom-keybindings` |

### Workspace navigation (W)

| Hyprland | GNOME key |
| --- | --- |
| `SUPER+TAB` | `switch-to-workspace-right` |
| `SUPER SHIFT+TAB` | `switch-to-workspace-left` |
| `SUPER CTRL+TAB` | `switch-to-workspace-last` |
| `SUPER+1..5` | `switch-to-workspace-1` ... `switch-to-workspace-5` |
| `SUPER SHIFT+1..5` | `move-to-workspace-1` ... `move-to-workspace-5` |

Margine ships **5 fixed workspaces** (`dynamic-workspaces=false`,
`num-workspaces=5`). The `SUPER+6..0` / `SUPER SHIFT+6..0` bindings from the
Hyprland chain still exist but are **inert** (there is no workspace 6–10).

### Window actions (W)

| Hyprland | GNOME key |
| --- | --- |
| `SUPER+W` | `close` |
| `SUPER+F` | `toggle-fullscreen` |
| `SUPER+O` | `always-on-top` |
| `SUPER+M` | `minimize` |

> `minimize` lives on `SUPER+M` because GNOME's default `<Super>h` is claimed
> by o-tiling `focus-left` (Hyprland parity) and `<Super>Down` is `unmaximize`,
> not minimize — there is no "auto-minimize" action in GNOME or o-tiling.

### Tiling actions (T — require o-tiling extension)

We use **o-tiling** (`o-tiling@oliwebd.github.com`), an active fork of
System76's pop-shell with native GNOME 48-50 support. Earlier Margine
baselines (pre-2026-06-02) shipped Tiling Shell as the default tiler;
its ghost-border bug at v18 was unpleasant and o-tiling's binary-tree
auto-split is closer to Hyprland muscle memory. Forge is *not* used —
upstream-marked "Needs a new maintainer" and its gsettings schema is
unstable across releases.

o-tiling is **not** in Fedora 44 repos nor on extensions.gnome.org. It
is installed user-level from a pinned upstream release zip by
`scripts/install-user-extensions --apply`, which unzips it into
`~/.local/share/gnome-shell/extensions/`. Enable afterwards with
`scripts/configure-gnome-extensions --apply`.

Mental model:

- **Auto-split**: opening a window splits the focused tile in half
  (binary-tree), driven by `tile-by-default=true`.
- **Focus / move** are directional and follow the tree, not screen
  geometry.
- **Float** lifts the active window out of the tiling tree (Hyprland's
  pseudofloat).

> **Keybinding conflict resolution.** o-tiling's *upstream* keybinding
> defaults collide with several GNOME-native and Margine custom shortcuts
> (`SUPER+RETURN`, `SUPER+T`, `SUPER+F`, `SUPER+S`, `SUPER+ALT+arrows`).
> Because the binding state of an **installed** system is exactly whatever
> the shipped dconf defaults set, those collisions reach every user. Margine
> resolves them in `margine-image`'s
> `build_files/30-gnome-defaults/dconf/03-margine-o-tiling` and mirrors the
> identical values in the `o_tiling` block of `margine-atomic.yaml` (applied
> to user dconf at `ujust margine-bootstrap`) — **the two must stay in
> sync** or bootstrap silently re-breaks them. GNOME/Margine shortcuts win;
> o-tiling keeps every action on a collision-free chord:

| Action | o-tiling key | Margine chord | Was (upstream default) |
| --- | --- | --- | --- |
| Focus neighbour | `focus-{left,down,up,right}` | `SUPER+{h,j,k,l}` | also had `SUPER+ALT+arrows` — **dropped** (shadowed workspace-switch / overview-shift) |
| Swap with neighbour | `tile-swap-*` | `SUPER+CTRL+arrows` | unchanged (no conflict) |
| Adjustment mode | `tile-enter` | `SUPER+CTRL+RETURN` | `SUPER+RETURN` — collided with the terminal launcher |
| Toggle auto-tiling | `toggle-tiling` | `SUPER+SHIFT+T` | `SUPER+T` — accidental whole-session toggle |
| Float window | `toggle-floating` | `SUPER+SHIFT+F` | `SUPER+F` — collided with `toggle-fullscreen` |
| Stacking | `toggle-stacking-global` | `SUPER+SHIFT+S` | `SUPER+S` — collided with quick-settings |
| Resize | n/a — mouse | drag the gutter | o-tiling resizes via mouse drag |

Preferences live in the GNOME Extensions Manager UI for
`o-tiling@oliwebd.github.com`. Tiling Shell is still installable from
Extensions Manager (EGO ID 7065) for users who want to A/B compare,
but Margine no longer ships it by default.

### Shell + screenshot (S)

| Hyprland | GNOME key |
| --- | --- |
| `SUPER+N` (toggle notifications) | `toggle-message-tray` (GNOME 48 name) |
| `Print` (screenshot menu) | `show-screenshot-ui` |
| `CTRL+Print` (screenshot active window) | `screenshot-window` |
| `SUPER+Print` (recording menu) | `show-screen-recording-ui` |

### Media + lock (M, native — no extra config beyond what the WM already sets)

| Hyprland | GNOME key |
| --- | --- |
| `XF86AudioRaiseVolume` / `LowerVolume` / `Mute` / `MicMute` | `volume-up`/`down`/`mute`/`mic-mute` (GNOME defaults) |
| `XF86MonBrightnessUp`/`Down` | handled by kernel + GNOME automatically |
| `XF86Audio{Next,Prev,Play,Pause}` | `next`/`previous`/`play`/`pause` (GNOME defaults) |
| `SUPER CTRL+L` (lock) | `screensaver` |

## Skipped on purpose

These Hyprland bindings have no clean GNOME equivalent and are intentionally
not mapped:

| Hyprland | Reason |
| --- | --- |
| `SUPER+K` (show Hyprland binds) | GNOME Settings → Keyboard has the canonical list |
| `SUPER SHIFT+P` (restart waybar) | no waybar in GNOME |
| `SUPER+P` (pseudotile) | Hyprland-specific layout concept; closest o-tiling has is per-window float, on `SUPER+SHIFT+F` |
| `SUPER+S` / `SUPER ALT+S` (scratchpad) | o-tiling has no built-in scratchpad workspace, and `SUPER+S` is reserved for GNOME quick-settings; a workaround would be a dedicated workspace + custom keybinding, but it's out of scope here |

## How to apply

```sh
# Dry-run: print every gsettings command
scripts/configure-gnome-keybindings

# Apply
scripts/configure-gnome-keybindings --apply

# o-tiling is installed system-wide by margine-image and enabled by default
# via the zz1 gschema override, so its keybinding section applies on first
# login with no manual enable step. (If you disabled it, re-enable with
# `scripts/configure-gnome-extensions --apply`, then re-run this script.)

# Log out / log back in for some shell-side shortcuts (toggle-overview, etc.)
# to refresh.
```

Reset just the custom slots (native shortcuts stay applied; useful if you
want to wipe the app-launcher bindings without resetting workspace/window
shortcuts):

```sh
scripts/configure-gnome-keybindings --reset --apply
```

## Verifying after apply

```sh
gsettings get org.gnome.desktop.wm.keybindings switch-to-workspace-1   # ['<Super>1']
gsettings get org.gnome.desktop.wm.keybindings close                   # ['<Super>w']
gsettings get org.gnome.shell.keybindings toggle-application-view      # ['<Super>space', '<Super>r']
gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings
gsettings get org.gnome.shell.extensions.o-tiling toggle-floating
gsettings get org.gnome.mutter dynamic-workspaces                      # true
gsettings get org.gnome.desktop.wm.preferences workspace-names          # ['1', ...]
gsettings get org.gnome.desktop.wm.keybindings switch-to-workspace-4    # ['<Super>4']
gnome-extensions list --enabled | grep workspace-indicator
```

GNOME Settings → Keyboard → View and Customize Shortcuts shows the same
information in GUI form. Custom slots appear under "Custom Shortcuts" at
the bottom.

## Editing the layout

Edit `gnome.keybindings` in `declarations/margine-atomic.yaml`, then re-run
`scripts/configure-gnome-keybindings --apply`. The script is idempotent —
running it again writes the same values.

To add a new app launcher, append an entry to `gnome.keybindings.custom`:

```yaml
- name: my_launcher
  binding: '<Super>m'
  command: 'my-command --with-args'
```

To swap a tiling key, change the value in `gnome.keybindings.o_tiling` (keep
it in sync with margine-image's dconf `03-margine-o-tiling`, which sets the
same keys as system defaults) — o-tiling's schema accepts any GNOME-format
accelerator.

## o-tiling: enabling and notes

o-tiling is installed **system-wide** by margine-image
(`build_files/build-margine-extensions.sh` bakes a pinned, checksummed
release into `/usr/share/gnome-shell/extensions/`) and is enabled by default
through the `enabled-extensions` list in the zz1 gschema override. It is
active on first GDM login — no per-user install, no manual enable step.

If you ever disable it and want it back:

```sh
scripts/configure-gnome-extensions --apply
gnome-extensions list --enabled | grep -E 'o-tiling|workspace-indicator'
```

o-tiling has its own preferences window (`gnome-extensions prefs
o-tiling@oliwebd.github.com`) for things outside the keybinding scope: gaps,
the active-window hint, auto-split behaviour. Margine pre-seeds a few of
these via the dconf `03-margine-o-tiling` keyfile; anything you change in the
GUI persists in your user dconf.

## Source preserved

The original Hyprland configuration this maps from is preserved in
`margine-os-personal/files/home/.config/hypr/conf.d/60-binds.conf`. Treat
that file as the upstream when adding new bindings: change the Hyprland
config first, then mirror to the YAML here.
