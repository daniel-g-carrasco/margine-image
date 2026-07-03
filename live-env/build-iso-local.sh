#!/usr/bin/env bash
# Build the Margine live ISO LOCALLY — a DEVELOPER tool, NOT shipped in the
# distro. It exists so install-time / ISO bugs (the flatpak bake, console
# kargs, livesys UX, …) can be iterated in minutes instead of waiting on a
# ~40 min CI build + an 8.5 GB artifact download.
#
# It mirrors the CI job `build_iso_titanoboa` in
# .github/workflows/build-disk.yml: same live-env/Containerfile, same build
# flags, and — critically — the SAME pinned Titanoboa ref. Everything runs in
# podman (rootful); nothing is installed on the host. Output: ./output/*.iso.
#
# Usage:
#   live-env/build-iso-local.sh [BASE_TAG] [ZSTD_LEVEL]
#     BASE_TAG    published margine image tag to build the live env FROM
#                 (default: stable — what the shipped ISO uses).
#     ZSTD_LEVEL  squashfs zstd compression level (default: 19 = CI-identical).
#                 Pass 1 for a fast throwaway TEST ISO (much quicker squashfs;
#                 bigger ISO, slower first boot — fine for VM testing).
#
# No MOK secrets are needed: the live image is built FROM the already-signed
# published base, so the kernel/modules are already signed (unlike `just build`).
#
# !!! KEEP TITANOBOA_REF BELOW IN SYNC with the `uses:` pin in build-disk.yml's
#     build_iso_titanoboa job, or a locally-built ISO will diverge from CI. !!!
set -euo pipefail

# --- config (mirror of build-disk.yml build_iso_titanoboa) -------------------
TITANOBOA_REPO="${TITANOBOA_REPO:-https://github.com/daniel-g-carrasco/titanoboa}"
TITANOBOA_REF="${TITANOBOA_REF:-cce73fc476e97fed626283afb6c518e0882a12d7}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-ghcr.io/daniel-g-carrasco}"

BASE_TAG="${1:-stable}"
ZSTD_LEVEL="${2:-19}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BASE_IMAGE="${IMAGE_REGISTRY}/margine:${BASE_TAG}"
LIVE_TAG="localhost/margine-live:local"
CACHE="${REPO_ROOT}/.cache/titanoboa-${TITANOBOA_REF}"
OUT="${REPO_ROOT}/output"

# Colour only on a real terminal — the GTK GUI captures plain stdout.
if [[ -t 1 ]]; then C_B='\033[1;34m'; C_R='\033[1;31m'; C_0='\033[0m'; else C_B=''; C_R=''; C_0=''; fi
log()  { printf '\n%b==>%b [%s] %s\n' "$C_B" "$C_0" "$(date +%H:%M:%S)" "$*"; }
die()  { printf '%bERROR:%b %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

command -v podman >/dev/null || die "podman is required"
command -v git    >/dev/null || die "git is required"

# Ownership handback. The GUI runs this whole script as root via pkexec; on the
# root path an EXIT trap hands artifacts back to the user on ANY exit, so a
# mid-build failure can't leave .cache/ root-owned (which would break the next
# terminal build with git's 'dubious ownership' guard). PKEXEC_UID/SUDO_UID are
# set by pkexec/sudo; fall back to the current uid for a direct run.
REAL_UID="${PKEXEC_UID:-${SUDO_UID:-$(id -u)}}"
REAL_GID="$(getent passwd "${REAL_UID}" | cut -d: -f4)"; REAL_GID="${REAL_GID:-${REAL_UID}}"
mkdir -p "${OUT}" "${REPO_ROOT}/.cache"
if [[ "$(id -u)" -eq 0 ]]; then
  trap 'chown -R "${REAL_UID}:${REAL_GID}" "${OUT}" "${REPO_ROOT}/.cache" 2>/dev/null || true' EXIT
fi

# Titanoboa's main.sh runs `sudo podman run` and reads the image from ROOTFUL
# storage, so every podman step here must be rootful (sudo) and consistent.
log "Build plan: ${BASE_IMAGE}  ->  ${LIVE_TAG}  ->  ISO (zstd-${ZSTD_LEVEL})"

# 1. Base image into rootful storage. ALWAYS pull: `podman pull` is delta-only
#    (it fetches just the changed layers, so it's fast when :stable is
#    unchanged) and it picks up a freshly-rebuilt base. The earlier "skip if
#    already present" shortcut was REMOVED — it served a stale base for days
#    (the installer showed an old build date despite a fresh local build).
log "Pulling base image ${BASE_IMAGE} (rootful; delta-only when unchanged)"
sudo podman pull "${BASE_IMAGE}"

# 2. Build the live image (identical flags to CI: dracut needs sys_admin,
#    the Flatpak bake in build.sh needs user namespaces via label=disable).
#    LIVEENV_REV = a content hash of live-env/src. src/ is BIND-MOUNTED in the
#    Containerfile (not COPY'd), so a change to build.sh / anaconda/ / flatpaks
#    does NOT bust this layer's cache on its own. Passing the hash as a
#    build-arg forces a rebuild whenever live-env/src actually changed (and
#    keeps the cache when it didn't) — without it, local rebuilds silently reuse
#    a stale live image and your live-env edits never reach the ISO.
LIVEENV_REV="$(find live-env/src -type f -print0 | LC_ALL=C sort -z \
  | xargs -0 sha256sum | sha256sum | cut -c1-16)"
log "Building ${LIVE_TAG} from live-env/Containerfile (live-env rev ${LIVEENV_REV})"
sudo podman build \
  --cap-add sys_admin \
  --security-opt label=disable \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg "LIVEENV_REV=${LIVEENV_REV}" \
  -t "${LIVE_TAG}" \
  -f live-env/Containerfile \
  live-env/

# 3. Pinned Titanoboa checkout (cached per-ref).
if [[ ! -d "${CACHE}/.git" ]]; then
  log "Cloning Titanoboa @ ${TITANOBOA_REF}"
  rm -rf "${CACHE}"
  git clone --quiet "${TITANOBOA_REPO}" "${CACHE}"
  git -C "${CACHE}" checkout --quiet "${TITANOBOA_REF}"
else
  log "Using cached Titanoboa @ ${TITANOBOA_REF}"
  git -C "${CACHE}" checkout --quiet "${TITANOBOA_REF}"
fi

# 4. Set the squashfs compression level. main.sh bind-mounts build_iso.sh from
#    the checkout, so editing it here changes compression for this run. The
#    regex resets it each run, so re-running with a different level is safe.
log "Setting squashfs zstd compression level = ${ZSTD_LEVEL}"
grep -qE '\-Xcompression-level [0-9]+' "${CACHE}/build_iso.sh" \
  || die "build_iso.sh no longer has '-Xcompression-level N' — Titanoboa changed; re-check the ref"
sed -i -E "s/-Xcompression-level [0-9]+/-Xcompression-level ${ZSTD_LEVEL}/" \
  "${CACHE}/build_iso.sh"

# 5. Run Titanoboa. The image is read from local rootful storage via
#    --mount type=image (main.sh) — no registry push needed with this ref.
log "Building ISO with Titanoboa (the slow part — zstd-${ZSTD_LEVEL} of a ~14 GB rootfs)"
ISO_PATH="$(env \
  TITANOBOA_CTR_IMAGE="${LIVE_TAG}" \
  TITANOBOA_OUTPUT_DIR="${OUT}" \
  bash "${CACHE}/main.sh")"

[[ -n "${ISO_PATH}" && -f "${ISO_PATH}" ]] || die "Titanoboa did not produce an ISO"

# 6. On a direct (non-root) run, rootful Titanoboa left the ISO root-owned —
#    hand it back. The root/pkexec path is handled by the EXIT trap above.
if [[ "$(id -u)" -ne 0 ]]; then
  sudo chown "${REAL_UID}:${REAL_GID}" "${ISO_PATH}" 2>/dev/null || true
fi

# 7. Sidecar metadata for the ISO Builder GUI's inventory (subtitle fields +
#    the fresh/STALE badge, which compares liveenv_rev to the current
#    live-env/src content hash). Best-effort: a metadata failure must never
#    fail a finished build. Ownership handback: the pkexec path is covered by
#    the EXIT trap on output/; a direct run writes it as the user already.
{
  BASE_DIGEST="$(sudo podman image inspect --format '{{.Digest}}' "${BASE_IMAGE}" 2>/dev/null || echo unknown)"
  printf '{"built_at": "%s", "zstd_level": %s, "base_image": "%s", "base_digest": "%s", "liveenv_rev": "%s", "builder": "local"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${ZSTD_LEVEL}" "${BASE_IMAGE}" \
    "${BASE_DIGEST}" "${LIVEENV_REV}" > "${ISO_PATH}.meta.json"
} || true

log "Done in $((SECONDS / 60))m $((SECONDS % 60))s — Live ISO ready:"
ls -lh "${ISO_PATH}"
printf '\nTest it:  just test-install-vm              (quick, Secure Boot off)\n'
printf '          just test-install-vm secure=true  (Secure Boot + TPM2, the real path)\n'
