# Repoint the freshly installed system at the public registry so future
# `bootc upgrade` calls follow margine:stable (Titanoboa / ADR-0008,
# ported verbatim from disk_config/iso-gnome.toml:72-78).
#
# With registry-transport ostreecontainer (see interactive-defaults.ks)
# the origin is already the registry, so this is effectively idempotent —
# but it is the ADR §4 "keep the bootc install origin stable" invariant
# and stays explicit. --erroronfail: a wrong upgrade origin is a real
# defect, unlike the QoL Flatpak bake.
%post --erroronfail
bootc switch --mutate-in-place --transport registry ghcr.io/daniel-g-carrasco/margine:stable
%end
