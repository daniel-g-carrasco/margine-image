# Adapted from the ublue image-template Justfile. Template defaults
# ("image-template", floating BIB tag, secret-less build) sat here
# unchanged until the 2026-06-12 review — half the recipes could not
# build THIS image at all.
export image_name := env("IMAGE_NAME", "margine")
export default_tag := env("DEFAULT_TAG", "latest")
# Same digest build-disk.yml and smoke-boot.yml pin.
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder@sha256:7ae88b8d6f2cabfa971d7836b96d6cac19cd1384e658031bd154f9687e929905")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $image_name).
#   $tag - The tag for the image (default: $default_tag).
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    # The kernel layer signs vmlinuz with the MOK key — without the
    # secret mounts custom-kernel/install.sh aborts immediately. Use
    # the production keys if present, otherwise tell the developer how
    # to mint local throwaway ones.
    if [[ ! -f secrets/MOK.key || ! -f secrets/MOK.pem ]]; then
        echo "ERROR: secrets/MOK.key + secrets/MOK.pem are required (kernel signing)." >&2
        echo "For a local dev build, generate throwaway keys:" >&2
        echo "  openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \\" >&2
        echo "    -subj '/CN=Margine local dev MOK/' \\" >&2
        echo "    -keyout secrets/MOK.key -out secrets/MOK.pem" >&2
        exit 1
    fi

    podman build \
        --pull=newer \
        --secret id=mok-key,src=secrets/MOK.key \
        --secret id=mok-cert,src=secrets/MOK.pem \
        --tag "${target_image}:${tag}" \
        .

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            # If the image ID is not found or different from user, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"

    mkdir -p output
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/disk.toml")

# Local Margine live-ISO build (DEV ONLY — not shipped in the distro).
# Mirrors the CI job build_iso_titanoboa: same live-env + the SAME pinned
# Titanoboa ref (kept in sync inside live-env/build-iso-local.sh). Runs in
# rootful podman; output lands in ./output/. Lets install-time / ISO bugs
# (the Flatpak bake, console kargs, livesys UX) be iterated locally instead
# of waiting on the ~40 min CI build + an 8.5 GB artifact download. The old
# BIB anaconda-iso path was retired 2026-06-12; these use Titanoboa locally.

# Build the live ISO from the published base, zstd-19 (CI-identical).
[group('Build Live ISO (local dev)')]
build-iso tag="stable":
    live-env/build-iso-local.sh {{tag}} 19

# Fast throwaway TEST ISO: zstd-1 squashfs (quick) for iterating on ISO bugs.
[group('Build Live ISO (local dev)')]
build-iso-fast tag="stable":
    live-env/build-iso-local.sh {{tag}} 1

# Delegates to the shipped `ujust margine-test-vm` (SPICE so host<->guest
# CLIPBOARD works, + Secure Boot + enrolled MS keys + emulated TPM 2.0) — the
# proven full-featured path, not a bare qemu window.
# Boot the newest locally-built ISO in a full virt-manager test VM.
[group('Build Live ISO (local dev)')]
test-install-vm:
    #!/usr/bin/env bash
    set -euo pipefail
    ISO="$(ls -t output/*.iso 2>/dev/null | head -1)"
    [[ -n "$ISO" ]] || { echo "No ISO in output/ — run 'just build-iso-fast' first." >&2; exit 1; }
    command -v ujust >/dev/null \
      || { echo "ujust not found (run on a Margine host)." >&2; exit 1; }
    ISO_ABS="$(realpath "$ISO")"
    echo "Launching a virt-manager test VM (SPICE/clipboard + Secure Boot + TPM2) from:"
    echo "  $ISO_ABS"
    echo "Install with the DEFAULT partitioning; the INSTALLED system's first boot"
    echo "prompts MokManager for Secure Boot (passphrase: margine-os)."
    # Recycle here too, so a re-run never dead-ends on "a VM named X already
    # exists". The shipped `ujust margine-test-vm` only learns to recycle after a
    # base update (PR #239); this dev recipe (what `iso-test-vm` / the GUI button
    # call) must self-heal NOW. Derive the same name the base recipe does and tear
    # down any stale same-named session VM (domain + disk + nvram) first.
    NAME="margine-test-$(basename "$ISO_ABS" .iso)"
    NAME="$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9._-' '-')"
    CONN="qemu:///session"
    if virsh -c "$CONN" dominfo "$NAME" >/dev/null 2>&1; then
      echo "Recreating throwaway VM '$NAME' (removing the previous domain + disk)…"
      virsh -c "$CONN" destroy "$NAME" >/dev/null 2>&1 || true
      virsh -c "$CONN" undefine "$NAME" --nvram --remove-all-storage >/dev/null 2>&1 \
        || virsh -c "$CONN" undefine "$NAME" --nvram >/dev/null 2>&1 \
        || virsh -c "$CONN" undefine "$NAME" >/dev/null 2>&1 || true
    fi
    exec ujust margine-test-vm "$ISO_ABS"

# Launch the GTK4 GUI that drives the local ISO builds (dev tool, not shipped).
[group('Build Live ISO (local dev)')]
iso-gui:
    # system python3 has pygobject/GTK4/Adw (a venv/brew python on PATH may not)
    /usr/bin/python3 tools/iso-builder/margine-iso-builder.py

# Install a GNOME launcher for the GUI into ~/.local/share/applications.
[group('Build Live ISO (local dev)')]
install-desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    apps="$HOME/.local/share/applications"
    mkdir -p "$apps"
    dst="$apps/place.empty.margine.IsoBuilder.desktop"
    sed "s|@GUI@|{{justfile_directory()}}/tools/iso-builder/margine-iso-builder.py|" \
      "{{justfile_directory()}}/tools/iso-builder/place.empty.margine.IsoBuilder.desktop.in" > "$dst"
    chmod 0644 "$dst"
    update-desktop-database "$apps" 2>/dev/null || true
    echo "Installed launcher: $dst"
    echo "Search 'Margine ISO Builder' in Activities (icon: margine-logo)."

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    # (plain `[ ... ] &&` under set -e exits 1 whenever rebuild=0 — the
    # template shipped that bug; use an if.)
    if [ "{{ rebuild }}" -eq 1 ]; then
        echo "Rebuilding the image"
        just "build-{{ type }}"
    fi

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}


# Shellcheck every OUR bash script: tracked *.sh plus the extensionless
# bash shipped under build_files/system_files (shebang-discovered).
# Excludes live-env/references/ (vendored third-party). Mirrors what CI
# runs in lint.yml — keep the two in sync.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    mapfile -t SH < <(git ls-files '*.sh' | grep -v '^live-env/references/')
    mapfile -t BIN < <(git grep -lE '^#!.*\b(ba)?sh\b' -- build_files/system_files | grep -v '\.sh$' || true)
    printf 'linting %d scripts\n' "$(( ${#SH[@]} + ${#BIN[@]} ))"
    shellcheck -S warning "${SH[@]}" "${BIN[@]}"

# Runs shfmt on our Bash scripts (same discovery as lint)
format:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    mapfile -t SH < <(git ls-files '*.sh' | grep -v '^live-env/references/')
    shfmt --write "${SH[@]}"
