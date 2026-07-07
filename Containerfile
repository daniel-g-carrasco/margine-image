# =============================================================================
# Margine — a Bluefin DX based bootc image with CachyOS kernel
# =============================================================================
#
# This Containerfile composes the Margine image as:
#
#   FROM ghcr.io/ublue-os/bluefin-dx:stable   (Universal Blue Bluefin DX)
#   + custom kernel from CachyOS COPR (signed with our MOK)
#   + Margine deltas (o-tiling default tiler, Smile emoji picker, branding
#     extensions off, curated GNOME settings)
#
# Built by GitHub Actions on every push, pushed to:
#   ghcr.io/daniel-g-carrasco/margine:stable
#
# End-user install: rebase a vanilla Bluefin DX (or Fedora Atomic) to
# this image:
#   rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
# =============================================================================

# ----- Build context: scripts that should NOT end up in the final image -----
FROM scratch AS ctx
COPY build_files /
# Make installer/flatpaks-base reachable from build.sh at
# /ctx/installer-flatpaks-base. Single source of truth for the BAKE
# Flatpak list (audit §3.5: drop the duplicate here-doc in build.sh).
# (The old BIB installer image that also consumed it was retired in
# time via the installer/ working dir. The gaming variant was retired
# 2026-06-06 so there is no installer/flatpaks-gaming any more.
COPY installer/flatpaks-base    /installer-flatpaks-base

# ----- Base: Bluefin DX (Fedora 44 track, "stable" tag) -----
FROM ghcr.io/ublue-os/bluefin-dx:stable

# ----- Custom kernel: CachyOS via COPR + MOK signing -----
# Mounts the custom-kernel scripts from the ctx layer and the MOK signing
# keys from BuildKit secrets. After this layer, /usr/lib/modules/<KVER>/vmlinuz
# is the CachyOS kernel image signed with our MOK key — boots cleanly under
# Secure Boot once the user enrolls MOK.der via mokutil (one-time).
# Mount ONLY what the kernel layer reads (its own scripts + the shared
# helpers): with the whole ctx mounted, ANY build_files edit — a
# branding tweak, a just recipe — invalidated this 25-minute layer's
# cache (review P2.5). Narrow mounts keep the cache key tied to the
# files that actually matter here.
# NVIDIA variant toggle (ADR 0009). Default 0 = base image; the experimental
# build-nvidia.yml passes --build-arg ENABLE_NVIDIA=1. Declared here so it is in
# scope for the kernel RUN — the only layer where the MOK signing secret is
# mounted, hence the only place the nvidia kmod can be built AND MOK-signed.
ARG ENABLE_NVIDIA=0
ARG NVIDIA_KMOD=nvidia-open
RUN --mount=type=bind,from=ctx,source=/custom-kernel,target=/ctx/custom-kernel \
    --mount=type=bind,from=ctx,source=/00-common.sh,target=/ctx/00-common.sh \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok-key,target=/tmp/certs/MOK.key \
    --mount=type=secret,id=mok-cert,target=/tmp/certs/MOK.pem \
    env ENABLE_NVIDIA="${ENABLE_NVIDIA}" NVIDIA_KMOD="${NVIDIA_KMOD}" /ctx/custom-kernel/install.sh

# ----- Margine modifications (GNOME settings, branding, flatpaks, etc.) -----
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# ----- Margine GNOME extensions: bake o-tiling + hide-cursor system-wide -----
# Replaces the old per-user "install at first login via autostart"
# pattern (margine-install-user-extensions) that was racy, shadowed
# Bluefin's own search-light, and silently failed if the user logged
# in before flatpak-preinstall.service had network. Bluefin + Bazzite
# do this exact thing — extensions live in /usr/share/gnome-shell/
# extensions/<uuid>/ at build time, dconf enables them, GDM picks them
# up on first login with zero per-user state.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build-margine-extensions.sh

# ----- Build-residue sweep + lint: verify final image is a valid bootc container -----
# 99-cleanup.sh removes the /var state the build's dnf/rpm transactions
# leave behind (dead weight on installed systems — bootc only uses image
# /var as a first-boot seed). Chained into the same RUN so the lint
# always judges the cleaned tree.
RUN --mount=type=bind,from=ctx,source=/99-cleanup.sh,target=/ctx/99-cleanup.sh \
    /ctx/99-cleanup.sh && bootc container lint
