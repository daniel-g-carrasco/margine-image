#!/usr/bin/env bash
# Margine image build — section: 40-spec-scripts
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# 3. Bundle the configure-gnome-* helpers from margine-fedora-atomic
# ---------------------------------------------------------------------------
# These are user-state helpers. We don't run them at image build time
# (no user yet); we install them so the user can run e.g.
#   margine-configure-keybindings --apply
# from any terminal post-install.
#
# The scripts live in the margine-fedora-atomic repo, fetched at build
# time. Pin a specific commit in CI so the image is reproducible.
log "Fetching Margine configure-* scripts"

# (var defined in 00-common.sh)
# (var defined in 00-common.sh)

# Preflight: confirm we can reach the spec repo before fetching anything.
# Without this, individual silent-skip fallbacks (the previous pattern)
# masked real connectivity / repo-visibility bugs and shipped incomplete
# images. Fail loud + fail early.
log "Preflight: probing spec repo at ${MARGINE_REPO}/${MARGINE_REF}/"
if ! curl --fail --silent --show-error --head -L \
     "${MARGINE_REPO}/${MARGINE_REF}/README.md" >/dev/null; then
  err() { printf '[margine-build] ERROR: %s\n' "$*" >&2; }
  err "cannot reach the Margine spec repo (${MARGINE_REPO}/${MARGINE_REF}/)."
  err "Check that the repo is PUBLIC on GitHub and that the runner has network access."
  exit 1
fi
log "Preflight OK"

for s in \
    configure-default-applications \
    configure-gnome-app-folders \
    configure-gnome-appearance \
    configure-gnome-extensions \
    configure-gnome-keybindings \
    configure-home-layout \
    configure-zen-browser \
    install-user-extensions \
    validate-atomic-layout \
    validate-cachyos-kernel \
    validate-hardware-media-stack \
    validate-gaming-runtime \
    validate-margine-system \
    validate-declared-state \
    collect-diagnostics ; do
  retry_curl "${MARGINE_REPO}/${MARGINE_REF}/scripts/${s}" \
             "/usr/bin/margine-${s}"
  chmod 0755 "/usr/bin/margine-${s}"
  log "Installed: /usr/bin/margine-${s}"
done

# Also pull the declarations YAML the scripts read.
mkdir -p /usr/share/margine
retry_curl "${MARGINE_REPO}/${MARGINE_REF}/declarations/margine-atomic.yaml" /usr/share/margine/declarations.yaml
log "Installed: /usr/share/margine/declarations.yaml"

# Compat symlink: 6 of the 7 configure-* scripts compute
#   YAML = Path(__file__).parent.parent / "declarations" / "margine-atomic.yaml"
# Since the scripts live at /usr/bin/, that resolves to
# /usr/declarations/margine-atomic.yaml. Without this symlink they
# silently can't find the file and bootstrap is broken end-to-end.
# Only configure-home-layout honors MARGINE_DECLARATIONS env var.
# Symlink is cheaper than patching 6 scripts. Keep until the scripts
# are unified to use a canonical lookup (FHS /usr/share/margine/).
mkdir -p /usr/declarations
ln -sf ../share/margine/declarations.yaml /usr/declarations/margine-atomic.yaml
log "Symlink: /usr/declarations/margine-atomic.yaml -> ../share/margine/declarations.yaml"

# Set MARGINE_DECLARATIONS env for the scripts to pick up the system copy.
cat > /etc/profile.d/margine.sh <<'EOF'
export MARGINE_DECLARATIONS=/usr/share/margine/declarations.yaml
EOF
chmod 0644 /etc/profile.d/margine.sh

# ---------------------------------------------------------------------------
