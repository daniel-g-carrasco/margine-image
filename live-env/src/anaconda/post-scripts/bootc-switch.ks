# Repoint the freshly installed system at the public registry so future
# `bootc upgrade` calls follow margine:stable (Titanoboa / ADR-0008,
# ported verbatim from disk_config/iso-gnome.toml:72-78).
#
# With registry-transport ostreecontainer (see interactive-defaults.ks)
# the origin is already the registry, so this is effectively idempotent —
# but it is the ADR §4 "keep the bootc install origin stable" invariant
# and stays explicit. --erroronfail: a wrong upgrade origin is a real
# defect, unlike the QoL Flatpak bake.
#
# --enforce-container-sigpolicy (2026-10-06): the origin becomes
# ostree-image-signed:, so every update is checked against the Margine
# key in the installed system's /etc/containers/policy.json (scope added
# by build_files/16-image-trust). Without it ISO installs followed
# ostree-unverified-registry: and never verified a signature. Bluefin,
# Aurora and Bazzite do the same in their installers.
%post --erroronfail
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ghcr.io/daniel-g-carrasco/margine:stable
%end
