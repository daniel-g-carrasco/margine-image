# Margine ujust recipes.
# Loaded by /usr/bin/ujust (Universal Blue's just wrapper) via
# /usr/share/ublue-os/just/00-entry.just `import?` of 60-custom.just
# (the only optional extension point in Bluefin's entry file).

# Apply the full Margine user-state in one shot (home layout, GNOME extensions, keybindings, appearance, default apps, app folders). Pass MODE=unattended to skip the prompt.
[group('Margine')]
margine-bootstrap MODE="interactive":
    #!/usr/bin/bash
    set -uo pipefail
    UNATTENDED=0
    case "{{ MODE }}" in
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


# Install the Margine gaming layer (Steam Flatpak + Lutris/Heroic/Bottles + gamescope/mangohud/vkBasalt/gamemode layered via rpm-ostree)
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
      - Every `bootc upgrade` re-applies the layer on top of the new
        base, which is slower (~30-60s extra per upgrade) and can
        occasionally fail on file conflicts when upstream relocates a
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
    echo "== Installing gaming Flatpaks =="
    flatpak install --system -y --or-update flathub \
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
    sudo rpm-ostree install \
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

    flatpak uninstall --system -y \
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
# at the cost of +30-60s per `bootc upgrade` and occasional file-
# conflict risk. Use it if you game daily, run anti-cheat titles
# (EAC/BattlEye), use VR/Steam Link, or mix NVIDIA proprietary with
# Mesa-git. For occasional gaming the Flatpak default (margine-gaming)
# is enough.
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
                                `bootc upgrade` to re-apply the layer.

    Pick this variant if: anti-cheat titles, VR, daily play, or NVIDIA
    proprietary + Mesa-git side-by-side.

    To roll this back: ujust margine-gaming-native-remove
    To switch from the Flatpak variant first: ujust margine-gaming-remove

    EOF
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    echo
    echo "== Layering native gaming RPMs (rpm-ostree) =="
    sudo rpm-ostree install \
        steam \
        lutris \
        retroarch \
        gamescope \
        vkBasalt

    echo
    echo "== Installing the rest as Flatpaks =="
    flatpak install --system -y --or-update flathub \
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

# Roll back the NATIVE Margine gaming layer (undo margine-gaming-native)
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

    sudo rpm-ostree uninstall \
        steam \
        lutris \
        retroarch \
        gamescope \
        vkBasalt || true

    flatpak uninstall --system -y \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        com.vysp3r.ProtonPlus || true

    echo "Reboot to deactivate the layer: systemctl reboot"

    echo
    echo "Done. Reboot to release the rpm-ostree layer."


# Switch the CPU scheduler at runtime (sched_ext / BPF schedulers).
# Available on every Margine flavour. scx-scheds ships in the base
# image, scx_loader stays disabled by default, and users opt in here
# or through Activities -> "Margine CPU Scheduler".
#
#   ujust margine-scheduler          # show current state
#   ujust margine-scheduler lavd     # start/switch to a shipped scheduler
#   ujust margine-scheduler off      # stop scx_loader, return to BORE
# Switch the CPU scheduler (sched_ext / BPF). Modes: status, off, or any scheduler reported by `scxctl list`. GUI launcher: Activities -> "Margine CPU Scheduler".
[group('Performance')]
margine-scheduler MODE="status":
    #!/usr/bin/bash
    set -uo pipefail

    MODE="{{ MODE }}"
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
    ensure_loader() {
      sudo systemctl enable --now "$SERVICE" \
        || { echo "FAILED to enable $SERVICE — scheduler will not persist across reboots."; exit 1; }
    }

    stop_loader() {
      if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        scxctl stop 2>/dev/null || true
      fi
      sudo systemctl disable --now "$SERVICE" \
        || { echo "FAILED to disable $SERVICE — it may restart a scheduler at next boot."; exit 1; }
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

        echo "Enabling and starting scx_loader.service (opt-in)."
        ensure_loader
        if scheduler_running; then
          echo "Switching to scx_$MODE."
          scxctl switch --sched "$MODE"
        else
          echo "Starting scx_$MODE."
          scxctl start --sched "$MODE"
        fi
        echo
        scxctl get || true
        ;;
    esac


# Install Alpaca (Flatpak GUI for local LLMs; bundles Ollama backend
# in the Flatpak runtime). No host install needed, no GPU passthrough
# to configure — first launch downloads the chosen model.
# RamaLama (Red Hat's CLI runner) is NOT installed by this recipe;
# instructions printed below for power users who want it in distrobox.
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

    Hardware note:
      - 8 GB VRAM is the comfort floor for ~7B-parameter models.
      - CPU-only inference works but is markedly slower; consider
        phi3.5:3.8b on a 16 GB-RAM laptop.

    To uninstall: ujust margine-ai-remove

    EOF
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac
    flatpak install --system -y --or-update flathub com.jeffser.Alpaca
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
    echo
    echo "  NOT touched: model files cached under"
    echo "    ~/.var/app/com.jeffser.Alpaca/data/  — delete by hand"
    echo "    if you want to free that disk space."
    echo
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac
    flatpak uninstall --system -y com.jeffser.Alpaca || true
    echo "Done."

# Toggle the wayland-scroll-factor gnome-shell preload (on by image default). `off` fully unloads after logout; to merely neutralize, run `wsf set 1.0`.
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

# Enroll the TPM2 so the encrypted root unlocks automatically at boot; the install passphrase stays valid as recovery. `remove` undoes it.
[group('Margine')]
margine-tpm2-enroll ACTION="enroll":
    #!/usr/bin/bash
    set -euo pipefail
    # Validated flow (2026-06-11, ADR-0008 Phase 6): systemd-cryptenroll
    # binds the secret to PCR 7 (Secure Boot policy state), and the
    # shipped initramfs already includes the tpm2 unlock path — no
    # dracut regeneration needed.
    if [[ ! -e /dev/tpmrm0 && ! -e /dev/tpm0 ]]; then
      echo "No TPM2 device found (/dev/tpmrm0). Nothing to do."; exit 1
    fi
    mapfile -t LUKS_DEVS < <(lsblk -prno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1}')
    if [[ ${#LUKS_DEVS[@]} -eq 0 ]]; then
      echo "No LUKS device found — is the disk encrypted?"; exit 1
    fi
    if [[ ${#LUKS_DEVS[@]} -gt 1 ]]; then
      echo "Multiple LUKS devices found (${LUKS_DEVS[*]})."
      echo "Run systemd-cryptenroll manually on the one you want."; exit 1
    fi
    DEV="${LUKS_DEVS[0]}"
    UUID="$(blkid -s UUID -o value "$DEV")"
    case "{{ ACTION }}" in
      enroll)
        echo "Enrolling TPM2 (PCR 7) on $DEV — you'll be asked for the current LUKS passphrase."
        sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$DEV"
        # Add tpm2-device=auto to the matching crypttab options so the
        # initrd tries the TPM before prompting. The sed assumes the
        # 4-field crypttab layout; a legal 3-field line (no options
        # column) matches the grep but not the sed — so VERIFY after
        # editing instead of trusting it (review finding A7).
        if sudo grep -E "UUID=${UUID}" /etc/crypttab | grep -qv 'tpm2-device='; then
          sudo sed -i -E "/UUID=${UUID}/ s/(\S+\s+\S+\s+\S+\s+)(\S+)/\1\2,tpm2-device=auto/" /etc/crypttab
        fi
        if ! sudo grep -E "UUID=${UUID}" /etc/crypttab | grep -q 'tpm2-device=auto'; then
          echo "ERROR: /etc/crypttab was NOT updated (unexpected line layout)."
          echo "The TPM2 secret IS enrolled, but the initrd will still prompt."
          echo "Add ',tpm2-device=auto' to the options column of the line for"
          echo "UUID=${UUID} in /etc/crypttab, then reboot to verify."
          exit 1
        fi
        echo
        echo "Done. Reboot to verify the disk unlocks without a passphrase."
        echo "Your passphrase REMAINS valid — keep it: it's the recovery path"
        echo "(firmware updates or Secure Boot changes can rotate PCR 7)."
        ;;
      remove)
        echo "Removing the TPM2 enrollment from $DEV…"
        sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEV"
        sudo sed -i -E "/UUID=${UUID}/ s/,?tpm2-device=auto//" /etc/crypttab
        echo "Done. The passphrase prompt is back at boot."
        ;;
      *)
        echo "Usage: ujust margine-tpm2-enroll [enroll|remove]"; exit 1
        ;;
    esac

# Run every Margine validator in sequence with a one-line verdict each — the "is my system as shipped?" health check.
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
