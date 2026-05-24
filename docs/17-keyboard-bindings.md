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
| Extension | `org.gnome.shell.extensions.forge.keybindings` | Forge tiling actions |

A 6th surface — `org.gnome.mutter` + `org.gnome.desktop.wm.preferences` —
controls the workspace model (`dynamic-workspaces=true`) and workspace names.

## Workspace model

| Setting | Value | Why |
| --- | --- | --- |
| `dynamic-workspaces` | `true` | Avoids pre-creating ten empty workspaces; GNOME creates/removes them as windows move |
| `workspace-names` | `1` ... `10` | Gives GNOME/extension UIs numeric labels where they expose workspace names |
| `count` | `10` | Declarative static fallback; only written to `num-workspaces` if `dynamic=false` |

The `SUPER+1..0` bindings are still declared. In dynamic mode they jump to
existing workspaces; GNOME will not keep ten empty workspaces visible from
login.

## Hyprland → GNOME mapping

The full set, grouped by purpose. Source: `60-binds.conf`. Destination
schema in the legend column (W = WM, S = Shell, M = media-keys, C = custom,
F = Forge).

### Launcher / overview

| Hyprland | GNOME key | Schema |
| --- | --- | --- |
| `SUPER+SPACE` (Walker) | `toggle-application-view` | S |
| `SUPER SHIFT+SPACE` (Fuzzel fallback) | `toggle-overview` | S |
| `SUPER+R` (primary launcher) | `toggle-application-view` (alias) | S |

### Application launchers (custom slots — run a command)

| Hyprland | Command | Override note |
| --- | --- | --- |
| `SUPER+RETURN` | `kitty` | terminal default is **kitty**, not the GNOME-stock ptyxis |
| `SUPER SHIFT+RETURN` | `flatpak run app.zen_browser.zen` | |
| **`SUPER+E`** | `nautilus` | **override of `SUPER SHIFT+F`** — `E` is the recurring desktop convention for "Explorer/Files" |
| `SUPER CTRL+T` | `kitty -e btop` | btop lives in the toolbox; runs inside kitty |
| `SUPER+ESCAPE` | `gnome-session-quit --logout` | replaces the `open-session-actions-menu` helper |
| `SHIFT+Print` | `gnome-screenshot -ac` | takes a region screenshot to clipboard (GNOME shell handles SUPER+Print and bare Print as full UIs) |

### Workspace navigation (W)

| Hyprland | GNOME key |
| --- | --- |
| `SUPER+TAB` | `switch-to-workspace-right` |
| `SUPER SHIFT+TAB` | `switch-to-workspace-left` |
| `SUPER CTRL+TAB` | `switch-to-workspace-last` |
| `SUPER+1..0` | `switch-to-workspace-1` ... `switch-to-workspace-10` |
| `SUPER SHIFT+1..0` | `move-to-workspace-1` ... `move-to-workspace-10` |

### Window actions (W)

| Hyprland | GNOME key |
| --- | --- |
| `SUPER+W` | `close` |
| `SUPER+F` | `toggle-fullscreen` |
| `SUPER+O` | `always-on-top` |

### Tiling actions (F — require Forge extension)

Key names below match the **Forge 89** gsettings schema (verified live
with `gsettings list-keys org.gnome.shell.extensions.forge.keybindings`).
The schema changed significantly across Forge versions; if you upgrade
the extension and bindings stop working, list the keys again and
compare with this table.

| Hyprland | Forge 89 key | Notes |
| --- | --- | --- |
| `SUPER+T` (toggle floating) | `window-toggle-float` | |
| `SUPER+J` (toggle split) | `con-split-layout-toggle` | renamed from `window-rotate-split` |
| `SUPER+arrows` (focus direction) | `window-focus-{left,right,up,down}` | |
| `SUPER SHIFT+arrows` (swap window) | `window-swap-{left,right,up,down}` | |
| `SUPER+equal` / `SUPER+minus` (width) | `window-resize-right-{increase,decrease}` | Forge 89 is per-edge, not per-dim |
| `SUPER SHIFT+equal` / `SUPER SHIFT+minus` (height) | `window-resize-bottom-{increase,decrease}` | per-edge, see above |
| `SUPER+G` (toggle stacked layout) | `con-stacked-layout-toggle` | |
| `SUPER SHIFT+G` (toggle tabbed layout) | `con-tabbed-layout-toggle` | extra, not in Hyprland source |
| `SUPER ALT+TAB` (swap last active) | `window-swap-last-active` | Forge 89 has no list-cycle focus; this swaps with the previously-focused window |

Skipped (no Forge 89 equivalent): list-cycle focus within a stacked
container (`focus-next-window` / `focus-previous-window` from older Forge
versions). Forge 89 only has directional focus inside containers.

### Shell + screenshot (S)

| Hyprland | GNOME key |
| --- | --- |
| `SUPER+N` (toggle notifications) | `open-message-tray` |
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
| `SUPER+P` (pseudotile) | Hyprland-specific layout concept; closest Forge has is per-window float, already on `SUPER+T` |
| `SUPER+S` / `SUPER ALT+S` (scratchpad) | Forge has no built-in scratchpad workspace; workaround would be a dedicated workspace + custom keybinding, but it's out of scope here |

## How to apply

```sh
# Dry-run: print every gsettings command
scripts/configure-gnome-keybindings

# Apply
scripts/configure-gnome-keybindings --apply

# After --apply, enable Forge so its schema becomes available, then re-run
# so the Forge keybinding section actually takes effect:
gnome-extensions enable forge@jmmaranan.com
scripts/configure-gnome-keybindings --apply

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
gsettings get org.gnome.shell.extensions.forge.keybindings window-toggle-float
gsettings get org.gnome.mutter dynamic-workspaces                      # true
gsettings get org.gnome.desktop.wm.preferences workspace-names          # ['1', ...]
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

To swap a Forge tiling key, change the value in `gnome.keybindings.forge` —
Forge's gsettings schema accepts any GNOME-format accelerator.

## Forge: enabling and notes

Forge is shipped as `gnome-shell-extension-forge` in the host baseline
(installed by `scripts/apply-host-layer --apply`). It is **not enabled
automatically** — GNOME extensions are user-state, not host-state.

After first boot:

```sh
gnome-extensions enable forge@jmmaranan.com
gnome-extensions list --enabled | grep forge
```

Then re-run `configure-gnome-keybindings --apply` (the Forge schema becomes
available only after the extension is enabled).

Forge has its own preferences window (`gnome-extensions prefs
forge@jmmaranan.com`) for things outside the keybinding scope: window
gaps, tiling mode (tabbed / stacked / split), drag-to-tile behaviour. The
Margine declarations don't pre-configure those — pick what you like from
the Forge GUI and they persist in user dconf.

## Source preserved

The original Hyprland configuration this maps from is preserved in
`margine-os-personal/files/home/.config/hypr/conf.d/60-binds.conf`. Treat
that file as the upstream when adding new bindings: change the Hyprland
config first, then mirror to the YAML here.
