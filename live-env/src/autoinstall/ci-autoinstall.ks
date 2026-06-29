# Margine CI install-gate kickstart (forum 12247). NOT shipped behaviour —
# only runs when the live boot carries `margine.autoinstall` (CI only, via
# margine-autoinstall.service). It reproduces the REAL bake: ostreecontainer
# pulls margine:stable and the SAME %include post-scripts the interactive
# install uses run — including install-flatpaks.ks, the thing under test.
cmdline
firstboot --disable
lang en_US.UTF-8
keyboard us
timezone UTC --utc
network --bootproto=dhcp --activate
rootpw --plaintext margineci

# Storage: BTRFS autopart. NOTE this does NOT reproduce margine.conf's
# dedicated `/var (btrfs)` subvol (a known gate gap), but install-flatpaks.ks
# now bakes into the per-deployment stateroot checkout ($deployment.0/var/lib),
# which is the booted runtime var under BOTH layouts — so the bake under test
# is exercised either way. (No anaconda-webui on the --cmdline path, so the
# webui-68 `part`-crash does not apply.)
zerombr
clearpart --all --initlabel
autopart --type=btrfs --noswap

# Same install source as interactive-defaults.ks (needs network).
ostreecontainer --url=ghcr.io/daniel-g-carrasco/margine:stable --transport=registry --no-signature-verification

# Auto-reboot when done so QEMU -no-reboot halts the VM for offline verify.
reboot

# The REAL post-install path under test — identical %includes to
# interactive-defaults.ks (minus secureboot-enroll-key.ks: a no-op MOK stage
# with Secure Boot off in the headless CI VM).
%include /usr/share/anaconda/post-scripts/bootc-switch.ks
%include /usr/share/anaconda/post-scripts/zstd-compress.ks
%include /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
%include /usr/share/anaconda/post-scripts/flatpak-restore-selinux-labels.ks
