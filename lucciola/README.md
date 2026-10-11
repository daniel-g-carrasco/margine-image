# Lucciola

Lucciola is niri with the Noctalia shell, built as a thin layer on top of the
Margine OS image. Experimental.

Everything below the desktop comes from Margine unchanged: the CachyOS kernel
signed with the Margine key, Secure Boot, TPM2 disk unlock, image signatures
verified by the device, rollback, and every Margine fix. This layer adds:

- `niri` and `xwayland-satellite` from Fedora, and `noctalia` from Fedora at a
  pinned version (`NOCTALIA_EVR` in the Containerfile: bump it only together
  with a test boot, since upstream supports only its latest release);
- the niri defaults in `/usr/share/lucciola/niri/config.kdl`, loaded through
  `/etc/niri/config.kdl`, with Margine's keybindings; personal settings go in
  `~/.config/niri/lucciola.kdl`;
- Noctalia defaults in `/usr/share/lucciola/noctalia/`, seeded once per user
  by `/usr/libexec/lucciola/session-start`: idle lock on, polkit agent on, and
  the look of the first Margine (dark floating bar, monospace, windows rounded
  like libadwaita; palette `palettes/Margine.json`, linked into the user's
  `palettes/` folder at login);
- niri's border colours follow the Noctalia palette through Lucciola's own
  Noctalia template (`noctalia/25-niri-colors.toml`, rendered to
  `~/.config/niri/lucciola-colors.kdl`, which the system niri config
  includes): the same colours as Noctalia's built-in "Niri" template (beige
  focused border, unfocused ones in the bar background), without touching
  any user niri file;
- `/usr/libexec/lucciola/bar-widths`: the bar keeps a fixed width on large
  monitors, and secondary screens get a single workspace, as in GNOME;
- `/usr/libexec/lucciola/color-calibration`: niri has no colour management
  yet, so this loads the calibration curves (vcgt) of the screens' ICC
  profiles in `~/.local/share/icc`, as GNOME does. Per-screen choices go in
  `~/.config/lucciola/color-profiles`; `color-calibration --list` shows what
  each screen gets, and Super+Shift+C (`color-calibration --toggle`) switches
  the calibration off and on to compare. The curves and Noctalia's night light use the same
  mechanism, so the night light cannot change a calibrated screen;
- `~/.config/niri/config.kdl`, created at login when missing, starting with
  `include "/etc/niri/config.kdl"`: niri reads the user file *instead of* the
  system one, and Noctalia's niri template (Templates > Built-in > Niri)
  would otherwise create it with nothing but its colours, dropping every
  Lucciola default. A file holding only Noctalia's include is repaired;
- one scroll speed for every application: toolkits turn a unit of touchpad
  scrolling into 2.5 (GTK 4), 4 (Firefox, Zen, Thunderbird) or 5.3
  (Chromium, Electron) logical pixels, so window rules scale the second
  and third families down to the first; the touchpad `scroll-factor`
  (0.15) is the one value to change, in `~/.config/niri/lucciola.kdl`
  (repeat the whole `touchpad` block: niri replaces it, it does not merge);
- the "Lucciola" session on the login screen, the one a new user gets
  (AccountsService user templates; whoever picks GNOME once keeps it), and
  the public name in os-release;
- GNOME as a stock fallback session: the image drops every GNOME Shell
  extension (Margine's and the base's), the Shell, window-manager and
  settings-daemon defaults that go with them and the GNOME first-login
  bootstrap. The defaults that also serve GTK applications under niri
  (fonts, accent colour, file chooser, Ptyxis, Nautilus) stay.

Images: `ghcr.io/daniel-g-carrasco/margine:lucciola` (and `:lucciola.DATE`),
rebuilt by `.github/workflows/build-lucciola.yml` after every green smoke-boot
on main, signed like every Margine tag. Pull requests that touch Lucciola push
`:lucciola-test`.

Switch a Margine install to it (and back with the previous boot entry, or by
rebasing to `:stable`):

```
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:lucciola
systemctl reboot
```

## Logo

`assets/lucciola-logo.svg` (the firefly) and `assets/lucciola-wordmark.svg`
("Lucciola" set in Aladin by Sudtipos, converted to outlines; the font is
under the SIL Open Font License 1.1, copy in `assets/Aladin-OFL.txt`). Colors:
lavender `#6b64a0` / `#b3addf`, firefly yellow `#f2c94c`. Not wired into the
image yet: boot splash, login screen and the About page still show Margine's.
