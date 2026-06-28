# Margine: belt-and-suspenders SELinux relabel for the Flatpak repo (Bazzite
# pattern). The PRIMARY label mechanism is upstream's: install-flatpaks.ks
# rsyncs with -X, which preserves the live env's correct contexts on the
# baked objects, and 10-margine.conf runs `restorecon -RF /var/lib/flatpak`
# on the booted runtime var at first boot. This chroot %post is an extra net.
#
# CAVEAT (do not over-trust this script): it runs in the target chroot, where
# /var/lib/flatpak may bind to the SHARED stateroot var (/ostree/deploy/$sr/
# var), which is empty at %post time — a different directory from the bake
# target ($deployment.0/var/lib/flatpak). So it can be a no-op. It is kept
# because it is harmless when it misses and useful if the chroot /var happens
# to map to the checkout. Tolerant: a labeling hiccup must not brick install.
%post
restorecon -RF /var/lib/flatpak 2>/dev/null \
  || chcon -R -t var_lib_t /var/lib/flatpak 2>/dev/null \
  || true
%end
