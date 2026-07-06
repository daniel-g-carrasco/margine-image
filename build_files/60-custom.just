# Margine ujust recipes.
# Loaded by /usr/bin/ujust (Universal Blue's just wrapper) via
# /usr/share/ublue-os/just/00-entry.just `import?` of 60-custom.just
# (the only optional extension point in Bluefin's entry file).

# Apply the full Margine user-state (home, GNOME, keybinds, apps) in one shot.
[group('Margine')]
margine-bootstrap $MODE="interactive":
    #!/usr/bin/bash
    set -uo pipefail
    UNATTENDED=0
    case "$MODE" in
      unattended|--unattended|noninteractive|silent) UNATTENDED=1 ;;
    esac

    if [[ "$UNATTENDED" -ne 1 ]]; then
      cat <<'EOF'
    == Margine user-state bootstrap ==

    Applies the full Margine user-state declaration. Idempotent — safe
    to re-run after upgrades; each step reports [no change] for keys
    that already match the spec.

    Steps:
      1. margine-configure-home-layout         (~/data + ~/dev + ~/scratch + XDG remap + bookmarks)
      2. margine-configure-gnome-keybindings   (Hyprland-style SUPER+1..0, SUPER+E, tiling binds)
      3. margine-configure-gnome-appearance    (accent, theme, dconf for extensions)
      4. margine-configure-default-applications (Zen as browser, Ptyxis terminal, etc.)
      5. margine-configure-gnome-app-folders   (Activities grid grouped by category)

    As of 2026-06-03 PR A, GNOME extensions are no longer installed
    or enabled per-user: o-tiling and hide-cursor live in /usr/share/
    gnome-shell/extensions/ (baked by margine-image build), enablement
    is in /usr/share/glib-2.0/schemas/zz1-margine.gschema.override.
    Bootstrap no longer touches them.

    No package install. No layer staged. Pure user-state under $HOME
    and user-dconf. Reversible by hand.

    Run `ujust margine-bootstrap unattended` to skip the prompt
    (this is what /etc/xdg/autostart/margine-first-boot.desktop does
    the first time you log in).

    EOF
      read -rp "Continue? [Y/n] " ans
      case "$ans" in ""|[yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac
    fi

    FAILED=()
    # Extension install + enable used to be in this chain (steps 2/3)
    # but lived per-user under ~/.local/share/gnome-shell/extensions/
    # and shadowed Bluefin's own copies (search-light), or never ran
    # at all due to first-login race with flatpak-preinstall.service.
    # Replaced 2026-06-03 by system-wide install in margine-image's
    # build-margine-extensions.sh + zz1-margine.gschema.override
    # enabled-extensions list. Nothing left here for extensions.
    for step in \
        margine-configure-home-layout \
        margine-configure-gnome-keybindings \
        margine-configure-gnome-appearance \
        margine-configure-default-applications \
        margine-configure-gnome-app-folders \
        margine-configure-zen-browser ; do
      echo
      echo "==> $step --apply"
      if ! $step --apply; then
        echo "  ⚠ $step failed (continuing)"
        FAILED+=("$step")
      fi
    done

    echo
    if [[ ${#FAILED[@]} -eq 0 ]]; then
      echo "== Bootstrap complete (all steps succeeded). =="
    else
      echo "== Bootstrap complete with ${#FAILED[@]} failed step(s): =="
      printf '   - %s\n' "${FAILED[@]}"
    fi
    echo "Log out and back in (or restart GNOME Shell with Alt+F2 → 'r')"
    echo "to refresh the dock, extensions, keybindings, and bookmarks."

    # Drop a marker so the autostart entry doesn't re-trigger every
    # session. Re-run `ujust margine-bootstrap` to refresh manually.
    mkdir -p "$HOME/.config/margine"
    date -uIs > "$HOME/.config/margine/bootstrapped"

    [[ ${#FAILED[@]} -eq 0 ]]


# Install the gaming layer: Steam/Lutris/Heroic Flatpaks + RPM helpers.
[group('Gaming')]
margine-gaming:
    #!/usr/bin/bash
    set -euo pipefail

    cat <<'EOF'
    == Margine gaming layer ==

    This installs:

      Flatpaks (from Flathub, system-wide):
        - com.valvesoftware.Steam
        - net.lutris.Lutris
        - com.heroicgameslauncher.hgl
        - com.usebottles.bottles
        - com.github.Matoking.protontricks
        - com.vysp3r.ProtonPlus
        - org.libretro.RetroArch   (multi-emulator: PS1/N64/GBA/SNES/…)

      Host RPMs (layered via rpm-ostree — requires reboot to take effect):
        - gamescope       (HDR / per-game compositor / scaling)
        - mangohud        (FPS / GPU / CPU overlay)
        - vkBasalt        (post-processing Vulkan layer)
        - gamemode        (CPU governor + niceness during gameplay)
        - goverlay        (GUI configurator for MangoHud + vkBasalt)
        - steam-devices   (controller udev rules)
        - input-remapper  (remap keyboard/mouse/gamepad without per-device drivers)
        - tuned, tuned-ppd (CPU governor switching balanced↔performance)
        - rom-properties  (Nautilus column extension for ROM metadata)

    Notes:
      - GameMode auto-engages when Steam launches a game. No setup.
      - For host MangoHud inside Flatpak Steam, after install run:
          flatpak override --user --filesystem=xdg-config/MangoHud:ro \
            com.valvesoftware.Steam
        Then add MANGOHUD=1 %command% in the game's Steam launch options.
      - For host gamescope inside Flatpak Steam:
          gamescope -- %command%   in Steam launch options.
      - To roll this back: ujust margine-gaming-remove

    Trade-off — host RPMs are layered via rpm-ostree, which means:
      - Your booted deployment becomes "branched" from the base OCI
        image: `rpm-ostree status` will show LayeredPackages: …
      - You MUST update with `ujust margine-update` (NOT `bootc
        upgrade`, which REFUSES a client-layered deployment). It
        re-applies the layer on top of the new base — slower (~30-60s
        extra per update) and can occasionally fail on file conflicts
        when upstream relocates a
        file in a layered RPM.
    This recipe is THE supported way to get the gaming layer on
    Margine — the separate Margine Gaming image + ISO were retired
    2026-06-06 to cut maintenance. The Flatpak clients above
    (Steam/Lutris/Heroic/Bottles/Protontricks/ProtonPlus/RetroArch)
    DO NOT layer — they're proper Flatpaks.

    EOF
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    echo
    echo "== Ensuring full (unfiltered) Flathub at system level =="
    # Rebased systems can have Flathub missing at --system scope, or the
    # Fedora-FILTERED Flathub (which hides proprietary apps like Steam, the
    # exact failure a tester hit 2026-06-24). Make it present + unfiltered.
    sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak remote-modify --system flathub --no-filter || true
    echo "== Installing gaming Flatpaks =="
    sudo flatpak install --system -y --or-update flathub \
        com.valvesoftware.Steam \
        net.lutris.Lutris \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        com.vysp3r.ProtonPlus \
        org.libretro.RetroArch

    echo
    echo "== Layering gaming-only host helpers (rpm-ostree) =="
    # gamescope + vkBasalt are the only RPMs strictly gaming-only.
    # Everything else (mangohud, goverlay, steam-devices, gamemode,
    # input-remapper, tuned, tuned-ppd, scx-scheds) is already in
    # base Margine — see custom-kernel/install.sh + build_files/build.sh.
    # rom-properties-gtk was dropped in 2026-05 (no F44 build available).
    # --idempotent: a re-run (common: "did it install?") must not abort
    # under set -e when the package is already layered.
    sudo rpm-ostree install --idempotent \
        gamescope \
        vkBasalt

    echo
    cat <<'EOF'
    == Done ==
    Reboot to activate the rpm-ostree layer:
        systemctl reboot
    The Flatpak apps are already available (without reboot) from the
    Activities grid.
    EOF

# Roll back the Margine gaming layer (undo margine-gaming)
[group('Gaming')]
margine-gaming-remove:
    #!/usr/bin/bash
    set -euo pipefail

    echo "This will:"
    echo "  - rpm-ostree uninstall gamescope + vkBasalt (the only gaming-only RPMs)"
    echo "  - flatpak uninstall the 7 gaming Flatpaks (Steam, Lutris, Heroic,"
    echo "    Bottles, Protontricks, ProtonPlus, RetroArch)"
    echo
    echo "  NOT touched (kept — useful for non-gaming workflows too):"
    echo "    mangohud, goverlay, steam-devices, gamemode, input-remapper,"
    echo "    tuned, tuned-ppd, scx-scheds. All in base Margine."
    echo
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    sudo rpm-ostree uninstall \
        gamescope \
        vkBasalt || true

    sudo flatpak uninstall --system -y \
        com.valvesoftware.Steam \
        net.lutris.Lutris \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        com.vysp3r.ProtonPlus \
        org.libretro.RetroArch || true

# Install the NATIVE Margine gaming layer (Steam + Lutris + RetroArch
# as rpm-ostree layered RPMs, the launchers without an RPM stay Flatpak).
# Native gives maximum Proton/Wine compatibility (no Flatpak sandbox
# restrictions on controllers, kernel namespaces, Mesa version, etc.)
# at the cost of +30-60s per `ujust margine-update` and occasional file-
# conflict risk. Use it if you game daily, run anti-cheat titles
# (EAC/BattlEye), use VR/Steam Link, or mix NVIDIA proprietary with
# Mesa-git. For occasional gaming the Flatpak default (margine-gaming)
# is enough.

# Install the gaming layer NATIVELY (rpm-ostree RPMs, max Proton compat).
[group('Gaming')]
margine-gaming-native:
    #!/usr/bin/bash
    set -euo pipefail

    cat <<'EOF'
    == Margine gaming layer (NATIVE variant) ==

    This installs:

      Native RPMs (layered via rpm-ostree — requires reboot):
        - steam              (Valve Steam client, RPM Fusion non-free)
        - lutris             (open-source game manager)
        - retroarch          (multi-emulator front-end)
        - gamescope          (HDR / per-game compositor / scaling)
        - vkBasalt           (post-processing Vulkan layer)

      Flatpaks (for launchers without an official RPM):
        - com.heroicgameslauncher.hgl   (Epic + GOG)
        - com.usebottles.bottles        (Wine prefix manager)
        - com.github.Matoking.protontricks
        - com.vysp3r.ProtonPlus         (Proton-GE manager)

    Native vs Flatpak — when to pick which:
      - margine-gaming         (DEFAULT, Flatpak): sandboxed, zero
                                upgrade overhead. Fine for the
                                occasional gamer.
      - margine-gaming-native  (THIS, RPM-layered): maximum Proton/
                                Wine compatibility — anti-cheat (EAC/
                                BattlEye) works, VR/Steam Link/USB
                                controllers integrate without sandbox
                                quirks, Mesa version always matches
                                the system. The cost is +30-60s per
                                `ujust margine-update` to re-apply the layer.

    Pick this variant if: anti-cheat titles, VR, daily play, or NVIDIA
    proprietary + Mesa-git side-by-side.

    To roll this back: ujust margine-gaming-native-remove
    To switch from the Flatpak variant first: ujust margine-gaming-remove

    EOF
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    echo
    echo "== Layering native gaming RPMs (rpm-ostree) =="
    # Package set lives in a single source-of-truth file shared with the
    # smoke-boot dry-run check (see /usr/share/margine/).
    PKGLIST=/usr/share/margine/gaming-native-packages.txt
    [ -r "$PKGLIST" ] || { echo "Missing $PKGLIST — bad image?" >&2; exit 1; }
    mapfile -t GAMING_PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$PKGLIST")
    # --idempotent: safe to re-run without aborting on already-layered pkgs.
    sudo rpm-ostree install --idempotent "${GAMING_PKGS[@]}"

    echo
    echo "== Ensuring full (unfiltered) Flathub at system level =="
    sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak remote-modify --system flathub --no-filter || true
    echo "== Installing the rest as Flatpaks =="
    sudo flatpak install --system -y --or-update flathub \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        com.vysp3r.ProtonPlus

    echo
    cat <<'EOF'
    == Done ==
    Reboot to activate the native RPM layer:
        systemctl reboot
    The Flatpak apps are already in Activities (no reboot needed for them).
    EOF

# Roll back the native gaming layer (undo margine-gaming-native).
[group('Gaming')]
margine-gaming-native-remove:
    #!/usr/bin/bash
    set -euo pipefail

    echo "This will:"
    echo "  - rpm-ostree uninstall steam, lutris, retroarch, gamescope, vkBasalt"
    echo "  - flatpak uninstall Heroic, Bottles, Protontricks, ProtonPlus"
    echo
    echo "  NOT touched (kept — useful for non-gaming workflows too):"
    echo "    mangohud, goverlay, steam-devices, gamemode, input-remapper,"
    echo "    tuned, tuned-ppd, scx-scheds. All in base Margine."
    echo
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    PKGLIST=/usr/share/margine/gaming-native-packages.txt
    [ -r "$PKGLIST" ] || { echo "Missing $PKGLIST — bad image?" >&2; exit 1; }
    mapfile -t GAMING_PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$PKGLIST")
    sudo rpm-ostree uninstall "${GAMING_PKGS[@]}" || true

    sudo flatpak uninstall --system -y \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        com.vysp3r.ProtonPlus || true

    echo
    echo "Done. Reboot to release the rpm-ostree layer: systemctl reboot"


# Switch the CPU scheduler at runtime (sched_ext / BPF schedulers).
# Available on every Margine flavour. scx-scheds ships in the base
# image, scx_loader stays disabled by default, and users opt in here
# or through Activities -> "Margine CPU Scheduler".
#
#   ujust margine-scheduler          # show current state
#   ujust margine-scheduler lavd     # start/switch to a shipped scheduler
#   ujust margine-scheduler off      # stop scx_loader, return to BORE
# Switch the CPU scheduler (sched_ext/BPF): status, off, or a scxctl name.
[group('Performance')]
margine-scheduler $MODE="status":
    #!/usr/bin/bash
    set -uo pipefail

    # MODE arrives as an exported env var ($ on the param), not raw just
    # text substitution, so a hostile argument stays inert data.
    SERVICE="scx_loader.service"

    require_scxctl() {
      if ! command -v scxctl >/dev/null 2>&1; then
        echo "scxctl is not installed. The scx-scheds package is required."
        exit 1
      fi
    }

    list_schedulers() {
      scxctl list 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"' || true
    }

    scheduler_supported() {
      local wanted="$1"
      local scheduler
      while IFS= read -r scheduler; do
        [[ "$scheduler" == "$wanted" ]] && return 0
      done < <(list_schedulers)
      return 1
    }

    scheduler_running() {
      local state
      state="$(scxctl get 2>/dev/null || true)"
      [[ -n "$state" ]] && ! grep -qi 'no scx scheduler running' <<<"$state"
    }

    # scx_loader is a SYSTEM service — enable/disable need sudo.
    # ("systemctl --user-or-sudo" is not a real flag: it failed silently
    # here for weeks because this recipe runs without -e. Found by the
    # 2026-06-12 code-quality review, finding A3.)
    # All privileged work (write the scx_loader boot config + toggle the service
    # + apply live) is done by the shared helper, so this recipe and the GTK
    # picker behave identically and the config format lives in one place.
    ensure_loader() {
      sudo /usr/libexec/margine/scheduler-apply "$MODE" Auto auto \
        || { echo "FAILED to apply scx_$MODE."; exit 1; }
    }

    stop_loader() {
      sudo /usr/libexec/margine/scheduler-apply off \
        || { echo "FAILED to disable $SERVICE."; exit 1; }
    }

    require_scxctl

    case "$MODE" in
      status|"")
        echo "=== scx_loader ==="
        systemctl is-enabled "$SERVICE" 2>/dev/null || true
        systemctl is-active "$SERVICE" 2>/dev/null || true
        echo
        echo "=== Current scheduler ==="
        scxctl get || true
        echo
        echo "Available scx schedulers:"
        list_schedulers | sed 's/^/  - /'
        ;;

      default|stop|off)
        echo "Stopping scx_loader.service; kernel default (BORE on Margine) takes over."
        stop_loader
        echo "ok - scx_loader.service is stopped and disabled."
        ;;

      *)
        if ! scheduler_supported "$MODE"; then
          echo "Unknown or unsupported scheduler: $MODE"
          echo
          echo "Available scx schedulers:"
          list_schedulers | sed 's/^/  - /'
          echo
          echo "Usage: ujust margine-scheduler [status|off|<scheduler>]"
          exit 1
        fi

        echo "Applying scx_$MODE and saving it as the boot default (opt-in)."
        ensure_loader
        echo
        scxctl get || true
        ;;
    esac


# Install Alpaca (Flatpak GUI for local LLMs; bundles Ollama backend
# in the Flatpak runtime). No host install needed; first launch downloads
# the chosen model.
# GPU note: Alpaca is sandboxed, so it does NOT use the host ROCm that the
# Bluefin base already ships — GPU acceleration in the Flatpak comes either
# from the com.jeffser.Alpaca.Plugins.AMD extension (ROCm inside the sandbox,
# offered below when an AMD GPU is detected) or from Ollama's Vulkan backend
# (no plugin; great for integrated GPUs/APUs). CPU is the fallback.
# RamaLama (Red Hat's CLI runner) is NOT installed by this recipe;
# instructions printed below for power users who want it in distrobox — that
# path CAN use the host ROCm directly.

# Install Alpaca: a local-LLM GUI (Ollama backend) in a Flatpak sandbox.
[group('Margine')]
margine-ai:
    #!/usr/bin/bash
    set -euo pipefail
    cat <<'EOF'
    == Margine AI workflow ==

    This installs:
      - com.jeffser.Alpaca (Flatpak) — GUI chat with local LLMs.
        Alpaca bundles its own Ollama backend in the Flatpak, so no
        host install or daemon-running is needed. First launch
        downloads the chosen model (a few GB depending on choice —
        llama3.1:8b is ~5 GB).

    NOT installed by this recipe (do separately if you want):
      - RamaLama (CLI, Red Hat's local-LLM container runner).
        For that: open Ptyxis, then:
          distrobox create --image fedora:42 --name ai
          distrobox enter ai
          sudo dnf install -y ramalama
        Now `ramalama run llama3.1:8b` from inside `ai` works as
        a CLI ChatGPT-like.
      - Continue.dev / aichat / sgpt for VS Code or terminal-level
        completion. Install in your dev distrobox.

    Recommended starter models (downloadable from Alpaca's UI):
      - llama3.1:8b      — general purpose, ~5 GB, fits 8 GB GPU
      - qwen2.5-coder:7b — coding-focused, ~4 GB
      - mistral:7b       — fast general, ~4 GB
      - phi3.5:3.8b      — small footprint, ~2 GB (CPU-friendly)

    GPU acceleration:
      - The Flatpak is sandboxed and does NOT use the host ROCm. This
        recipe offers the AMD ROCm plugin (com.jeffser.Alpaca.Plugins.AMD)
        when it detects an AMD GPU. Vulkan is the no-plugin alternative
        and is often best on integrated GPUs/APUs.
      - NVIDIA: Flatpak auto-pulls the matching GL driver; Ollama uses CUDA
        through it. Intel: Vulkan. No GPU: runs on CPU (fine, just slower —
        consider phi3.5:3.8b on a 16 GB-RAM machine).

    Hardware note:
      - 8 GB VRAM is the comfort floor for ~7B-parameter models.

    To uninstall: ujust margine-ai-remove

    EOF
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac
    sudo flatpak install --system -y --or-update flathub com.jeffser.Alpaca

    # GPU acceleration for the sandbox. The host ROCm (shipped by the Bluefin
    # base) does not reach into the Flatpak; AMD accel needs the ROCm plugin
    # extension inside the sandbox, or Ollama's Vulkan backend (no plugin).
    gpu="$(lspci 2>/dev/null | grep -iE 'vga|3d controller|display controller' || true)"
    if echo "$gpu" | grep -qiE 'amd|ati|radeon'; then
      echo
      echo "AMD GPU detected. The ROCm plugin (com.jeffser.Alpaca.Plugins.AMD)"
      echo "enables GPU acceleration inside Alpaca's sandbox (a sizeable download)."
      read -rp "Install the AMD ROCm plugin now? [Y/n] " amd
      case "$amd" in
        [nN]|[nN][oO]) echo "Skipped — Alpaca will use Vulkan if available, else CPU." ;;
        *) sudo flatpak install --system -y --or-update flathub com.jeffser.Alpaca.Plugins.AMD \
             && echo "AMD ROCm plugin installed." \
             || echo "Plugin install failed — Alpaca still works on Vulkan/CPU." ;;
      esac
      cat <<'EOF'
    Integrated AMD GPU (APU, e.g. Radeon 7xxM / gfx110x)? ROCm may not detect
    it until you set, in Alpaca → Preferences → environment:
        HSA_OVERRIDE_GFX_VERSION=11.0.0
    Or skip ROCm entirely and use Ollama's Vulkan backend, which usually works
    on APUs out of the box. Check Alpaca's hardware list to see which the GPU
    shows up under.
    EOF
    elif echo "$gpu" | grep -qiE 'nvidia'; then
      echo
      echo "NVIDIA GPU detected. Flatpak auto-pulls the matching GL driver and"
      echo "Ollama uses CUDA through it. If the GPU isn't used, make sure the"
      echo "proprietary driver is active and restart Alpaca."
    else
      echo
      echo "No discrete AMD/NVIDIA GPU detected — Alpaca runs on CPU (or Intel"
      echo "Vulkan if present). phi3.5:3.8b is the comfortable CPU-only pick."
    fi

    cat <<'EOF'

    == Done ==
    Launch Alpaca from Activities → "Alpaca". The first run will ask
    you to pick a model to download.
    EOF

# Roll back the Margine AI workflow (undo margine-ai)
[group('Margine')]
margine-ai-remove:
    #!/usr/bin/bash
    set -euo pipefail
    echo "This will:"
    echo "  - flatpak uninstall com.jeffser.Alpaca"
    echo "  - flatpak uninstall com.jeffser.Alpaca.Plugins.AMD (if present)"
    echo
    echo "  NOT touched: model files cached under"
    echo "    ~/.var/app/com.jeffser.Alpaca/data/  — delete by hand"
    echo "    if you want to free that disk space."
    echo
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac
    sudo flatpak uninstall --system -y com.jeffser.Alpaca.Plugins.AMD || true
    sudo flatpak uninstall --system -y com.jeffser.Alpaca || true
    echo "Done."

# Toggle the wayland-scroll-factor gnome-shell preload (on by default).
[group('Margine')]
wsf-preload STATE="status":
    #!/usr/bin/bash
    set -euo pipefail
    OVERRIDE=/etc/systemd/user/org.gnome.Shell@.service.d/99-margine-wsf-off.conf
    case "{{ STATE }}" in
      off)
        printf '[Service]\nUnsetEnvironment=LD_PRELOAD\n' | sudo install -Dm0644 /dev/stdin "$OVERRIDE"
        echo "WSF preload disabled. Log out and back in to unload it."
        ;;
      on)
        sudo rm -f "$OVERRIDE"
        echo "WSF preload re-enabled. Log out and back in to load it."
        ;;
      *)
        if [[ -f "$OVERRIDE" ]]; then echo "WSF preload: disabled via $OVERRIDE"; else echo "WSF preload: enabled (image default)"; fi
        command -v wsf >/dev/null && wsf status || true
        ;;
    esac

# Deprecated alias for margine-tpm-unlock (use that).
[group('Margine')]
margine-tpm2-enroll ACTION="enroll":
    #!/usr/bin/bash
    set -euo pipefail
    # Superseded by margine-tpm-unlock, which is lockout-proof by construction
    # (refuses to enroll unless a passphrase/recovery keyslot survives — the
    # old recipe had no such guard, plus the A7 crypttab-sed finding). Kept as
    # a thin forwarder so muscle memory / older docs don't hit "recipe not
    # found"; enroll→enable, remove→disable.
    echo "NOTE: 'margine-tpm2-enroll' was renamed to 'margine-tpm-unlock' (safer)."
    case "{{ ACTION }}" in
      enroll) exec sudo /usr/bin/margine-tpm-unlock enable ;;
      remove) exec sudo /usr/bin/margine-tpm-unlock disable ;;
      status) exec /usr/bin/margine-tpm-unlock status ;;
      *) echo "Usage: ujust margine-tpm-unlock [status|enable|disable]"; exit 1 ;;
    esac

# Run all Margine validators (the "is my system as shipped?" check).
[group('Margine')]
margine-doctor:
    #!/usr/bin/bash
    set -uo pipefail
    # Private log dir per run: fixed /tmp/<name>.out paths were
    # predictable (symlink hazard) and collided across users (A8).
    outdir="$(mktemp -d /tmp/margine-doctor.XXXXXX)"
    overall=0
    ran=0
    for v in /usr/bin/margine-validate-*; do
      [[ -x "$v" ]] || continue
      ran=$((ran + 1))
      name="$(basename "$v")"
      echo "── $name"
      if "$v" >"$outdir/$name.out" 2>&1; then
        echo "   PASS"
      else
        echo "   FAIL — details: $outdir/$name.out"
        overall=1
      fi
    done
    # Zero validators executed = the fetch step regressed — exactly the
    # failure class this recipe exists to catch. Never report healthy
    # on an empty loop (review finding A8).
    if [[ "$ran" -eq 0 ]]; then
      echo "margine-doctor: NO validators found under /usr/bin/margine-validate-* — image regression."
      exit 1
    fi
    if [[ "$overall" -eq 0 ]]; then
      echo "margine-doctor: all $ran validators passed ✅ (logs: $outdir)"
    else
      echo "margine-doctor: something is off — see the FAIL logs in $outdir"
    fi
    exit $overall

# Show Margine deployment vs latest :stable + lineage + kernel (read-only).
[group('Margine')]
margine-status:
    @/usr/bin/margine-status

# Pull the latest Margine :stable and stage it for the next reboot.
[group('Margine')]
margine-update:
    #!/usr/bin/bash
    set -euo pipefail
    /usr/bin/margine-status || true
    echo
    # bootc upgrade REFUSES a client-layered deployment ("Deployment contains
    # local rpm-ostree modifications; cannot upgrade via bootc"). So the choice
    # is NOT "is bootc installed" (it always is on a bootc image) — it's "are
    # there layered/local packages". If so, use rpm-ostree upgrade, which pulls
    # the new base image AND re-applies the layers. Otherwise prefer bootc.
    if rpm-ostree status 2>/dev/null | grep -qE '^[[:space:]]*(Layered|Local)Packages:'; then
      echo "Layered packages detected (e.g. gaming-native) — using rpm-ostree upgrade"
      echo "(bootc upgrade refuses client-layered deployments; rpm-ostree re-applies your layers)."
      sudo rpm-ostree upgrade
    elif command -v bootc >/dev/null 2>&1; then
      echo "No local layers — using bootc upgrade…"
      sudo bootc upgrade
    else
      echo "Staging the latest Margine :stable (rpm-ostree upgrade)…"
      sudo rpm-ostree upgrade
    fi
    echo
    echo "Staged. Reboot to switch into it:  systemctl reboot"

# Enable/disable/inspect GDM autologin (default: status, read-only).
[group('Margine')]
margine-autologin ACTION="status" USER="":
    @/usr/bin/margine-autologin "{{ ACTION }}" "{{ USER }}"

# TPM2 LUKS auto-unlock for the encrypted root (status/enable/disable).
[group('Margine')]
margine-tpm-unlock ACTION="status" PCRS="7":
    sudo /usr/bin/margine-tpm-unlock "{{ ACTION }}" "{{ PCRS }}"

# Re-apply the HiDPI GRUB font + grub.cfg now (safe, idempotent).
[group('Margine')]
margine-grub-hidpi:
    @sudo /usr/libexec/margine/grub-hidpi-apply

# Inspect/fix the GNOME login keyring password (status/blank/restore).
[group('Margine')]
margine-keyring ACTION="status":
    @/usr/bin/margine-keyring "{{ ACTION }}"

# Spin up a throwaway VM to test a Margine ISO on the REAL secure path: UEFI
# Secure Boot with Microsoft's keys pre-enrolled (so you also walk the MOK
# enrollment flow Margine relies on) + an emulated TPM 2.0 (so you can test
# LUKS TPM2 auto-unlock). Runs rootless on qemu:///session, so it reads ISOs
# straight from your home — no sudo, no copying multi-GB files.
#
#   ujust margine-test-vm ~/Downloads/margine-20260618.iso     # create + boot a VM from that ISO (recommended)
#   ujust margine-test-vm ~/Downloads/x.iso mytest 100         # custom name + 100 GiB disk
#   ujust margine-test-vm                                       # no ISO: define a TEMPLATE to clone in virt-manager
#
# Tear a test VM down with `ujust margine-test-vm-remove [name]`.

# Collect a diagnostic bundle and open the GitHub bug-report page.
# One command to give testers: it gathers what every bug report needs
# (image version, deployment state, Secure Boot, flatpak health, recent
# errors) into ~/margine-report.txt, then opens the issue template. Keeps
# reports in ONE searchable place instead of forum threads and comments.
[group('Margine')]
margine-report:
    #!/usr/bin/bash
    set -uo pipefail
    OUT="$HOME/margine-report.txt"
    {
      echo "=== Margine report ($(date -u +%FT%TZ)) ==="
      echo
      echo "--- image ---"
      grep -E '^(PRETTY_NAME|VARIANT_ID|VERSION)=' /etc/os-release
      rpm-ostree status -b 2>/dev/null | head -8
      echo
      echo "--- hardware ---"
      echo "cpu: $(lscpu 2>/dev/null | grep 'Model name' | sed 's/.*: *//')"
      echo "gpu: $(lspci 2>/dev/null | grep -iE 'vga|3d' | sed 's/.*: //' | head -2)"
      echo "ram: $(free -h | awk '/Mem:/{print $2}')"
      echo
      echo "--- secure boot ---"
      mokutil --sb-state 2>/dev/null || echo "mokutil unavailable"
      echo
      echo "--- flatpak ---"
      echo "system apps: $(flatpak --system list --app 2>/dev/null | wc -l)"
      systemctl is-active flatpak-preinstall.service 2>/dev/null | sed 's/^/preinstall: /'
      echo
      echo "--- recent errors (this boot) ---"
      journalctl -b -p err --no-pager 2>/dev/null | tail -30
    } > "$OUT" 2>&1
    echo "Report written to: $OUT"
    echo
    sed -n '1,12p' "$OUT"
    echo "  [...]"
    echo
    echo "Opening the bug-report page. Attach or paste $OUT into the Logs field."
    xdg-open "https://github.com/daniel-g-carrasco/margine-image/issues/new/choose" >/dev/null 2>&1 ||       echo "Open manually: https://github.com/daniel-g-carrasco/margine-image/issues/new/choose"

# Create + boot a throwaway Margine test VM from an ISO (libvirt).
[group('Margine')]
margine-test-vm ISO="" NAME="" DISK="80":
    #!/usr/bin/bash
    set -uo pipefail

    CONN="qemu:///session"
    ISO="{{ ISO }}"
    NAME="{{ NAME }}"
    DISK="{{ DISK }}"
    POOL="default"
    MEM=8192
    VCPUS=4
    TEMPLATE="margine-test-template"

    for b in virt-install virsh; do
      command -v "$b" >/dev/null 2>&1 || { echo "Missing '$b' — the Bluefin DX virt stack should provide it."; exit 1; }
    done
    virsh -c "$CONN" version >/dev/null 2>&1 || { echo "Cannot reach libvirt at $CONN."; exit 1; }

    # Ensure the rootless default storage pool exists and is running.
    if ! virsh -c "$CONN" pool-info "$POOL" >/dev/null 2>&1; then
      target="$HOME/.local/share/libvirt/images"
      mkdir -p "$target"
      virsh -c "$CONN" pool-define-as "$POOL" dir --target "$target" >/dev/null 2>&1 || true
      virsh -c "$CONN" pool-build "$POOL" >/dev/null 2>&1 || true
    fi
    virsh -c "$CONN" pool-start "$POOL" >/dev/null 2>&1 || true
    virsh -c "$CONN" pool-autostart "$POOL" >/dev/null 2>&1 || true

    print_walkthrough() {
      echo
      echo "  === Testing the secure path in this VM ==="
      echo "  1. Boot the ISO and install Margine."
      echo "  2. First boot after install: Secure Boot is ON with Microsoft's keys,"
      echo "     so shim runs, but Margine signs its kernel/modules with its own MOK."
      echo "     A blue MOK Manager screen appears:"
      echo "         Enroll MOK -> Continue -> Yes -> enter the password"
      echo "     (Margine's MOK password is 'margine-os', public by design), reboot."
      echo "  3. Confirm Secure Boot:    mokutil --sb-state     # -> SecureBoot enabled"
      echo "  4. TPM2 LUKS auto-unlock:  ujust margine-tpm-unlock enable"
      echo "     then reboot — the disk should unlock from the emulated TPM with no"
      echo "     passphrase prompt ('ujust margine-tpm-unlock status' to inspect)."
    }

    # Shared firmware: Secure Boot + enrolled MS keys, q35+SMM (required for SB),
    # boot order hd,cdrom. A blank disk is unbootable, so UEFI falls through to the
    # CD and runs the installer; after install the disk wins, so the ISO can stay
    # inserted — no eject, no install loop.
    FW="firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes,hd,cdrom,bootmenu.enable=on"

    if [[ -z "$ISO" ]]; then
      # ---------- TEMPLATE mode (define a shut-off VM to clone) ----------
      if virsh -c "$CONN" dominfo "$TEMPLATE" >/dev/null 2>&1; then
        echo "Template '$TEMPLATE' already exists."
        echo "Clone it in virt-manager (right-click -> Clone), attach your ISO to the"
        echo "clone's CD-ROM, then boot. To rebuild it:"
        echo "  ujust margine-test-vm-remove $TEMPLATE   (then re-run this)"
        exit 0
      fi
      echo "Defining test template '$TEMPLATE' (${DISK} GiB, Secure Boot + enrolled MS keys + TPM 2.0)..."
      virsh -c "$CONN" vol-create-as "$POOL" "${TEMPLATE}.qcow2" "${DISK}G" --format qcow2 >/dev/null \
        || { echo "Failed to create the template disk volume."; exit 1; }
      xml="$(mktemp /tmp/margine-test-template.XXXXXX.xml)"
      if ! virt-install --connect "$CONN" --name "$TEMPLATE" \
            --memory "$MEM" --vcpus "$VCPUS" --cpu host-passthrough --machine q35 \
            --boot "$FW" --features smm.state=on \
            --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
            --disk vol="$POOL/${TEMPLATE}.qcow2",bus=virtio --disk device=cdrom,bus=sata \
            --network user,model=virtio --graphics spice --video virtio \
            --osinfo detect=on,require=off,name=fedora-rawhide \
            --install no_install=yes --print-xml --dry-run > "$xml"; then
        echo "virt-install could not generate the domain XML."; rm -f "$xml"; exit 1
      fi
      virsh -c "$CONN" define "$xml" >/dev/null || { echo "virsh define failed (kept $xml)."; exit 1; }
      rm -f "$xml"
      echo
      echo "Template '$TEMPLATE' defined (shut off). To use it:"
      echo "  1. Open virt-manager. If it isn't listed: File -> Add Connection ->"
      echo "     'QEMU/KVM user session' -> Connect."
      echo "  2. Right-click '$TEMPLATE' -> Clone... (one clone per test)."
      echo "  3. On the clone, point the CD-ROM at your ISO (~/Downloads/*.iso), boot."
      echo "  Or skip the clicking:  ujust margine-test-vm ~/Downloads/<your>.iso"
      print_walkthrough
      exit 0
    fi

    # ---------- ISO mode (create + boot a ready VM) ----------
    real_iso="$(realpath -e "$ISO" 2>/dev/null)" || { echo "ISO not found: $ISO"; exit 1; }
    case "$real_iso" in *.iso) : ;; *) echo "Note: '$real_iso' doesn't end in .iso — continuing anyway." ;; esac
    if [[ -z "$NAME" ]]; then NAME="margine-test-$(basename "$real_iso" .iso)"; fi
    NAME="$(printf '%s' "$NAME" | tr -c 'a-zA-Z0-9._-' '-')"
    # Recycle, don't pile up. These VMs are throwaway by definition, and ISOs now
    # share a stable basename (Margine-Live.iso -> margine-test-Margine-Live), so a
    # re-run should REFRESH the single test VM rather than erroring out — and, more
    # importantly, never leave a graveyard of multi-GB qcow2s behind (the exact
    # "terabytes of artifacts" we're avoiding). Tear the old one down first;
    # '--remove-all-storage --nvram' reclaims its disk + UEFI vars. Manual VMs you
    # made in virt-manager are untouched (different names, and on qemu:///system).
    if virsh -c "$CONN" dominfo "$NAME" >/dev/null 2>&1; then
      echo "Recreating throwaway VM '$NAME' (removing the previous domain + disk)…"
      virsh -c "$CONN" destroy "$NAME" >/dev/null 2>&1 || true
      if   virsh -c "$CONN" undefine "$NAME" --nvram --remove-all-storage >/dev/null 2>&1; then :
      elif virsh -c "$CONN" undefine "$NAME" --nvram >/dev/null 2>&1; then :
      else virsh -c "$CONN" undefine "$NAME" >/dev/null 2>&1 || true; fi
    fi
    echo "Creating '$NAME' (${DISK} GiB, Secure Boot + enrolled MS keys + TPM 2.0) from:"
    echo "  $real_iso"
    if ! virt-install --connect "$CONN" --name "$NAME" --import \
          --memory "$MEM" --vcpus "$VCPUS" --cpu host-passthrough --machine q35 \
          --boot "$FW" --features smm.state=on \
          --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
          --disk size="$DISK",format=qcow2,bus=virtio \
          --disk path="$real_iso",device=cdrom,bus=sata,readonly=on \
          --network user,model=virtio --graphics spice --video virtio \
          --osinfo detect=on,require=off,name=fedora-rawhide \
          --noautoconsole; then
      echo "virt-install failed to create the VM."; exit 1
    fi
    echo "VM '$NAME' created and booting the installer."
    if command -v virt-viewer >/dev/null 2>&1; then
      ( setsid virt-viewer --connect "$CONN" --wait "$NAME" >/dev/null 2>&1 & ) || true
      echo "Opening the console (virt-viewer)."
    else
      echo "Open the console in virt-manager (QEMU/KVM user session) -> '$NAME'."
    fi
    print_walkthrough

# Tear down a Margine test VM (stops it, removes domain + disks + UEFI nvram).
[group('Margine')]
margine-test-vm-remove NAME="margine-test-template":
    #!/usr/bin/bash
    set -uo pipefail
    CONN="qemu:///session"
    NAME="{{ NAME }}"
    if ! virsh -c "$CONN" dominfo "$NAME" >/dev/null 2>&1; then
      echo "No such VM on $CONN: $NAME"
      echo "List test VMs:  virsh -c $CONN list --all"
      exit 1
    fi
    virsh -c "$CONN" destroy "$NAME" >/dev/null 2>&1 || true
    if   virsh -c "$CONN" undefine "$NAME" --nvram --remove-all-storage >/dev/null 2>&1; then :
    elif virsh -c "$CONN" undefine "$NAME" --nvram >/dev/null 2>&1; then :
    else virsh -c "$CONN" undefine "$NAME" >/dev/null 2>&1 || true; fi
    echo "Removed '$NAME' (domain + storage + nvram)."

# Keeps the clone TEMPLATE by default; pass ALL=true to wipe that too. Only
# touches the rootless qemu:///session VMs this tool creates — your manual
# virt-manager VMs (on qemu:///system) are never listed here.
#
# Remove ALL throwaway 'margine-test-*' VMs at once (domains + disks + nvram).
[group('Margine')]
margine-test-vm-clean $ALL="false":
    #!/usr/bin/bash
    set -uo pipefail
    CONN="qemu:///session"
    KEEP="margine-test-template"
    if ! virsh -c "$CONN" version >/dev/null 2>&1; then echo "Cannot reach libvirt at $CONN."; exit 1; fi
    mapfile -t all < <(virsh -c "$CONN" list --all --name 2>/dev/null | grep '^margine-test-' || true)
    cleaned=()
    for v in "${all[@]}"; do
      [[ -z "$v" ]] && continue
      if [[ "$ALL" != "true" && "$v" == "$KEEP" ]]; then continue; fi
      cleaned+=("$v")
    done
    if [[ ${#cleaned[@]} -eq 0 ]]; then
      echo "Nothing to remove (no throwaway test VMs$( [[ "$ALL" != "true" ]] && printf ' besides the template' ))."
      exit 0
    fi
    echo "Removing ${#cleaned[@]} test VM(s): ${cleaned[*]}"
    for v in "${cleaned[@]}"; do
      virsh -c "$CONN" destroy "$v" >/dev/null 2>&1 || true
      if   virsh -c "$CONN" undefine "$v" --nvram --remove-all-storage >/dev/null 2>&1; then :
      elif virsh -c "$CONN" undefine "$v" --nvram >/dev/null 2>&1; then :
      else virsh -c "$CONN" undefine "$v" >/dev/null 2>&1 || true; fi
      echo "  removed $v"
    done
    if [[ "$ALL" != "true" ]]; then echo "Kept the clone template '$KEEP' (pass ALL=true to remove it too)."; fi

# Enable GPU OpenCL in the darktable Flatpak (Mesa rusticl). Two switches are
# needed and both ship off: the Flatpak needs RUSTICL_ENABLE for its rusticl
# driver, and darktable keeps rusticl blocklisted until two prefs are flipped.
# Verified on AMD (Radeon 760M): after this, darktable-cltest reports
# "opencl ... is AVAILABLE and ENABLED". Works on Polaris (RX 560) too via
# rusticl, which does not need ROCm. Restart darktable to pick it up.
[group('Apps')]
margine-darktable-opencl:
    #!/usr/bin/bash
    set -uo pipefail
    DT=org.darktable.Darktable
    if ! flatpak info "$DT" >/dev/null 2>&1; then
      echo "darktable is not installed. Install it first, then re-run:"
      echo "  flatpak install --system flathub $DT"
      exit 1
    fi
    if pgrep -x darktable >/dev/null 2>&1; then
      echo "NOTE: darktable is running. Close it first, or it will overwrite these"
      echo "      settings on exit. Re-run this after closing it."
    fi
    # Pick the rusticl driver for the GPU vendor.
    if lspci 2>/dev/null | grep -qiE "VGA.*(AMD|ATI)|3D.*(AMD|ATI)|Display.*(AMD|ATI)"; then DRV=radeonsi
    elif lspci 2>/dev/null | grep -qiE "VGA.*Intel|Display.*Intel|3D.*Intel"; then DRV=iris
    else DRV=radeonsi; fi
    echo "==> rusticl driver for your GPU: $DRV"
    # 1. enable rusticl for the darktable Flatpak (per-user, persistent)
    flatpak override --user --env=RUSTICL_ENABLE="$DRV" "$DT"
    # 2. flip darktable's prefs: enable OpenCL + un-blocklist the rusticl platform
    RC="$HOME/.var/app/$DT/config/darktable/darktablerc"
    mkdir -p "$(dirname "$RC")"; touch "$RC"
    for kv in opencl=TRUE clplatform_rusticl=TRUE; do
      k="${kv%%=*}"
      if grep -qE "^${k}=" "$RC"; then sed -i "s|^${k}=.*|${kv}|" "$RC"; else echo "$kv" >> "$RC"; fi
    done
    echo "==> darktable GPU OpenCL enabled (rusticl / $DRV)."
    echo "    Start (or restart) darktable. Preferences > Processing should show your GPU."
    echo "    Verify from a terminal: flatpak run --command=darktable-cltest $DT"

# Install/reinstall Koofr Desktop (native, rootless, autostart hidden).
[group('Apps')]
install-koofr ACTION="install":
    #!/usr/bin/bash
    set -euo pipefail
    DEST="${HOME}/.koofr-dist"
    MENU="${HOME}/.local/share/applications/koofr.desktop"
    AUTOSTART="${HOME}/.config/autostart/koofr.desktop"
    CFG="${HOME}/.koofr/config.json"
    URL="https://app.koofr.net/dl/apps/linux64"

    if [ "{{ ACTION }}" = "remove" ] || [ "{{ ACTION }}" = "uninstall" ]; then
      echo "Removing Koofr Desktop…"
      pkill -f "${DEST}/storage" 2>/dev/null || true
      rm -rf "${DEST}" "${MENU}" "${AUTOSTART}"
      echo "Done."; exit 0
    fi

    echo "Downloading the latest Koofr Desktop client…"
    TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
    curl -fL --retry 3 -o "${TMP}/koofr.tar.gz" "${URL}"
    tar -xzf "${TMP}/koofr.tar.gz" -C "${TMP}"

    # Upstream installer is rootless: copies binaries to ~/.koofr-dist (it also writes .desktop
    # files, which we overwrite below to make menu vs autostart behaviour deterministic).
    ( cd "${TMP}/koofr" && printf 'n' | ./installer.sh )

    # Menu launcher: NO flag -> a manual launch opens the window normally.
    mkdir -p "$(dirname "${MENU}")"
    printf '%s\n' \
      '[Desktop Entry]' 'Name=Koofr' 'GenericName=Hybrid storage cloud' \
      "Exec=${DEST}/storagegui" 'Terminal=false' 'Type=Application' \
      "Icon=${DEST}/icon.png" 'Categories=Network;FileTransfer;Internet;' > "${MENU}"

    # Autostart: starts HIDDEN to the tray at login (binary's own -silent flag).
    mkdir -p "$(dirname "${AUTOSTART}")"
    printf '%s\n' \
      '[Desktop Entry]' 'Name=Koofr' 'GenericName=Hybrid storage cloud' \
      'Comment=Koofr cloud sync (starts minimized to tray)' \
      "Exec=${DEST}/storagegui -silent" 'Terminal=false' 'Type=Application' \
      "Icon=${DEST}/icon.png" 'Categories=Network;FileTransfer;Internet;' \
      'X-GNOME-Autostart-enabled=true' > "${AUTOSTART}"

    # Belt-and-suspenders: if a config already exists, also persist Silent start so hidden-start
    # survives the app regenerating its autostart entry. Skip while running (clobber risk) and
    # skip if no config yet (the -silent autostart flag already covers a fresh install).
    if [ -f "${CFG}" ] && ! pgrep -x storagegui >/dev/null 2>&1; then
      tmp="$(mktemp)"; jq '.silentStart = true' "${CFG}" > "${tmp}" && mv "${tmp}" "${CFG}"
    fi

    echo; echo "Koofr installed in ${DEST}. Autostart = hidden to tray; menu launch = normal window."

# alias for install-koofr
[group('Apps')]
koofr ACTION="install":
    @ujust install-koofr {{ ACTION }}

# Set up Sunshine (Moonlight game-stream host). EXPERIMENTAL, opt-in.
[group('Gaming')]
margine-sunshine:
    #!/usr/bin/bash
    set -euo pipefail

    cat <<'EOF'
    == Margine Sunshine setup (EXPERIMENTAL) ==

    Sunshine is the host side of Moonlight game streaming. This sets it up
    the atomic-friendly way (no rpm-ostree layering):

      1. installs the Flatpak  dev.lizardbyte.app.Sunshine  (Flathub)
      2. enables uinput + a udev rule, so Sunshine can create the virtual
         gamepad/keyboard/mouse for the remote client
      3. grants the Flatpak device access + runs its bundled setup helper
      4. opens the Sunshine firewall ports (47984-48010, TCP + UDP)

    Heads-up:
      - This is Margine's first cut, not yet validated end-to-end. If
        something is off, please report it.
      - It opens network ports and grants input-device access, which is
        why it is an explicit opt-in command and not a default.
      - On Wayland (GNOME) the first stream prompts you to pick what to
        share (the screen-capture portal). That is normal.

    EOF
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    echo; echo "== Ensuring full (unfiltered) Flathub at system level =="
    sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak remote-modify --system flathub --no-filter || true
    echo; echo "== Installing the Sunshine Flatpak =="
    sudo flatpak install --system -y --or-update flathub dev.lizardbyte.app.Sunshine

    echo; echo "== Enabling uinput (virtual input) =="
    echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
    sudo modprobe uinput || true
    printf '%s\n' 'KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess"' \
      | sudo tee /etc/udev/rules.d/60-sunshine.rules >/dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=misc || true

    echo; echo "== Granting Flatpak device access + running its setup helper =="
    flatpak override --user --device=all dev.lizardbyte.app.Sunshine || true
    # The Flatpak ships a helper that wires udev + a user service; best-effort.
    flatpak run --command=additional-install.sh dev.lizardbyte.app.Sunshine || true

    echo; echo "== Opening Sunshine firewall ports =="
    if command -v firewall-cmd >/dev/null 2>&1; then
      for p in 47984/tcp 47989/tcp 47990/tcp 48010/tcp 47998/udp 47999/udp 48000/udp 48002/udp 48010/udp; do
        sudo firewall-cmd --permanent --add-port="$p" >/dev/null || true
      done
      sudo firewall-cmd --reload >/dev/null || true
      echo "  firewalld: Sunshine ports opened."
    else
      echo "  firewall-cmd not found; open 47984-48010 (TCP + UDP) manually if needed."
    fi

    echo
    cat <<'EOF'
    == Done ==
    Next steps:
      1. Log out and back in once (so the uinput udev access applies).
      2. Launch Sunshine from the Activities grid.
      3. Open the web UI at  https://localhost:47990  to set a username and
         password and pair your Moonlight client.
      4. To autostart on login, enable it in the Sunshine web UI.

    Roll back with:  ujust margine-sunshine-remove
    EOF

# Undo margine-sunshine (Flatpak + uinput rule + firewall ports).
[group('Gaming')]
margine-sunshine-remove:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Removing Sunshine..."
    flatpak run --command=additional-uninstall.sh dev.lizardbyte.app.Sunshine || true
    sudo flatpak uninstall --system -y dev.lizardbyte.app.Sunshine || true
    sudo rm -f /etc/udev/rules.d/60-sunshine.rules
    sudo udevadm control --reload-rules || true
    if command -v firewall-cmd >/dev/null 2>&1; then
      for p in 47984/tcp 47989/tcp 47990/tcp 48010/tcp 47998/udp 47999/udp 48000/udp 48002/udp 48010/udp; do
        sudo firewall-cmd --permanent --remove-port="$p" >/dev/null 2>&1 || true
      done
      sudo firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    echo "Done. (uinput stays enabled, which is harmless.)"

# Netflix 1080p on Zen Browser: install the AMO-signed "Netflix 1080p UA"
# extension into the Zen (Flatpak) profile and keep DRM/Widevine on.
#
# Why a recipe and not a shipped default: Zen is a Flatpak. Its enterprise
# policy file (distribution/policies.json) lives in read-only /app and is
# wiped on every `flatpak update`, so a durable policy-based auto-install
# is not viable. Sideloading is disabled by default. Shipping a niche UA
# spoofer enabled for every user is also the wrong default. So this is
# opt-in and per-user, the same pattern as the other Margine recipes.
#
# Honesty: this does NOT bypass or provide Widevine. It only makes Netflix
# see an Opera-on-Linux user agent (the one condition Netflix uses to
# unlock 1080p on Linux). 1080p also depends on the title, your plan and
# the network. Verify with the Netflix overlay: Ctrl+Shift+Alt+D.
[group('Apps')]
margine-netflix-1080p $ACTION="status":
    #!/usr/bin/bash
    set -uo pipefail
    APP="app.zen_browser.zen"
    EXT_ID="{221ca73e-12bd-11f1-b1cd-2cf05d5d458e}"
    # Pinned to the reviewed v2.0 XPI; Zen auto-updates it from AMO afterwards.
    XPI_URL="https://addons.mozilla.org/firefox/downloads/file/4724248/netflix_1080p_ua-2.0.xpi"
    XPI_SHA="24dc19cbd2272a9a16cdeec4038385f8692b88b708b7bcc21daa724aa7925492"
    ZEN_HOME="$HOME/.var/app/$APP/.zen"
    if ! flatpak info "$APP" >/dev/null 2>&1; then
      echo "Zen Browser ($APP) is not installed."
      exit 1
    fi
    PROFILE="$(ls -1dt "$ZEN_HOME"/*.[dD]efault* 2>/dev/null | head -1)"
    if [ "$ACTION" = "status" ]; then
      echo "Zen:       installed"
      if [ -z "$PROFILE" ]; then
        echo "Profile:   none yet (launch Zen once)"
        exit 0
      fi
      echo "Profile:   $PROFILE"
      if [ -f "$PROFILE/extensions/${EXT_ID}.xpi" ]; then
        echo "Extension: installed"
      else
        echo "Extension: not installed"
      fi
      if ls -d "$PROFILE/gmp-widevinecdm"/*/ >/dev/null 2>&1; then
        echo "Widevine:  present ($(ls "$PROFILE/gmp-widevinecdm" 2>/dev/null | tail -1))"
      else
        echo "Widevine:  not downloaded yet (Zen fetches it on first DRM playback)"
      fi
      echo
      echo "Verify actual resolution during playback with Ctrl+Shift+Alt+D."
      exit 0
    fi
    if [ -z "$PROFILE" ]; then
      echo "No Zen profile under $ZEN_HOME."
      echo "Launch Zen Browser once so it creates a profile, then re-run."
      exit 1
    fi
    EXT_DIR="$PROFILE/extensions"
    USER_JS="$PROFILE/user.js"
    if [ "$ACTION" = "remove" ] || [ "$ACTION" = "uninstall" ]; then
      rm -f "$EXT_DIR/${EXT_ID}.xpi"
      if [ -f "$USER_JS" ]; then
        sed -i '/margine-netflix-1080p managed block/,/margine-netflix-1080p end managed block/d' "$USER_JS"
      fi
      echo "Removed the Netflix 1080p UA extension. Restart Zen."
      echo "(The DRM/EME setting is left as-is: harmless, shared with other streaming sites.)"
      exit 0
    fi
    if [ "$ACTION" != "install" ]; then
      echo "usage: ujust margine-netflix-1080p [status|install|remove]"
      exit 2
    fi
    # Precise: match the running Flatpak app id exactly, not any process
    # whose command line merely contains the string (an editor, a shell).
    if flatpak ps --columns=application 2>/dev/null | grep -qx "$APP"; then
      echo "Zen is running. Quit it first (it rewrites its config on exit and would drop"
      echo "these changes), then re-run."
      exit 1
    fi
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    echo "Downloading the AMO-signed extension (v2.0)..."
    curl -fL --retry 3 -o "$TMP/nf.xpi" "$XPI_URL"
    if ! echo "${XPI_SHA}  ${TMP}/nf.xpi" | sha256sum -c - >/dev/null 2>&1; then
      echo "ERROR: checksum mismatch on the downloaded XPI, refusing to install."
      echo "  expected $XPI_SHA"
      echo "  got      $(sha256sum "$TMP/nf.xpi" | cut -d' ' -f1)"
      echo "AMO may have published a newer version; update XPI_URL + XPI_SHA in this recipe."
      exit 1
    fi
    mkdir -p "$EXT_DIR"
    install -m0644 "$TMP/nf.xpi" "$EXT_DIR/${EXT_ID}.xpi"
    # Managed prefs: keep DRM/EME on (Widevine), and let a profile-dropped
    # extension enable itself. autoDisableScopes is a bitmask of scopes whose
    # sideloaded add-ons stay disabled; 14 clears the PROFILE bit (1) only, so
    # the app/user/system scopes stay locked. The profile dir is the user's
    # own, so this does not widen who can add an extension.
    if ! grep -q "margine-netflix-1080p" "$USER_JS" 2>/dev/null; then
      {
        echo '// margine-netflix-1080p managed block'
        echo 'user_pref("media.eme.enabled", true);'
        echo 'user_pref("extensions.autoDisableScopes", 14);'
        echo '// margine-netflix-1080p end managed block'
      } >> "$USER_JS"
    fi
    echo
    echo "Installed. Now:"
    echo "  1. Start Zen. If it asks to approve 'Netflix 1080p UA' in about:addons, allow it."
    echo "  2. Open Netflix, play a compatible title, press Ctrl+Shift+Alt+D."
    echo "     The overlay Playing bitrate / resolution is the real proof: look for 1920x1080."
    echo
    echo "Note: this only changes how Netflix identifies the browser. It does not"
    echo "provide Widevine (Zen downloads that itself) and cannot guarantee 1080p for"
    echo "every title, plan or network. Remove with: ujust margine-netflix-1080p remove"
