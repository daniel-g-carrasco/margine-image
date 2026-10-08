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
- Noctalia defaults in `/usr/share/lucciola/noctalia/` (idle lock on), seeded
  once per user by `/usr/libexec/lucciola/session-start`;
- the "Lucciola" session on the login screen (GNOME stays as the fallback)
  and the public name in os-release.

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
