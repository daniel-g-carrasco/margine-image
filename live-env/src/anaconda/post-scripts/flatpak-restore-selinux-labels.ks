# Margine: restore SELinux labels on the baked /var/lib/flatpak (Bazzite
# pattern). install-flatpaks.ks rsyncs the repo into the target, but ostree
# relabels /var only ONCE at deploy-finalize (before %post), so the rsynced
# objects would otherwise keep whatever context they landed with and
# confined flatpak would be denied access to the repo (forum 12247).
# Runs in the target chroot (no --nochroot) so /var/lib/flatpak is the real
# runtime var and the target's policy applies. restorecon is the correct
# tool; chcon var_lib_t is the fallback Bazzite uses. Tolerant: a labeling
# hiccup must not brick an otherwise-good install.
%post
restorecon -RF /var/lib/flatpak 2>/dev/null \
  || chcon -R -t var_lib_t /var/lib/flatpak 2>/dev/null \
  || true
%end
