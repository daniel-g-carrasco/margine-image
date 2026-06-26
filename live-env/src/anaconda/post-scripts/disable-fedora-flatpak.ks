# Margine: stop Fedora's flatpak-add-fedora-repos.service from
# (re-)initializing /var/lib/flatpak on the installed target — both Bluefin
# and Bazzite ship this. On a fresh install it can half-initialize the
# system Flatpak repo and race the Margine bake, a plausible trigger for the
# "opendir(refs/remotes)" corruption (forum 12247). The Bluefin-DX base
# already masks it, so `mask` here is belt-and-braces and idempotent; keep
# it tolerant (no --erroronfail) so an already-masked unit can't fail the
# install. Runs in the target chroot (no --nochroot).
%post
systemctl mask flatpak-add-fedora-repos.service 2>/dev/null || true
%end
