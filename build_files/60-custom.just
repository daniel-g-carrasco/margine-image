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

    echo
    echo "Done. Reboot to release the rpm-ostree layer."


# Switch the CPU scheduler at runtime (sched_ext / BPF schedulers).
# Available on every Margine flavour — scx-scheds ships in the base
# image (so creators on regular Margine can use scx_central for
# pro-audio sessions), gaming variant inherits it.
#
#   ujust margine-scheduler            # show what's running
#   ujust margine-scheduler lavd       # low-latency, gaming-tuned
#   ujust margine-scheduler bpfland    # interactive + throughput balance
#   ujust margine-scheduler rusty      # general-purpose, Rust port of CFS
#   ujust margine-scheduler central    # pin all decisions to one CPU (RT audio)
#   ujust margine-scheduler simple     # didactic minimum
#   ujust margine-scheduler default    # stop scx_*, return to kernel default (BORE on Margine)
# Switch the CPU scheduler (sched_ext / BPF). Modes: status, lavd, bpfland, rusty, central, simple, default. GUI launcher: Activities → "Margine CPU Scheduler".
[group('Performance')]
margine-scheduler MODE="status":
    #!/usr/bin/bash
    set -uo pipefail

    pgrep_scx() { pgrep -a 'scx_[a-z]+' 2>/dev/null; }

    case "{{ MODE }}" in
      status|"")
        echo "=== Current scheduler ==="
        if pgrep_scx > /dev/null; then
          echo "sched_ext active:"
          pgrep_scx
        else
          echo "Kernel default scheduler in use (BORE on Margine)."
        fi
        echo
        echo "Available scx schedulers:"
        ls /usr/bin/scx_* 2>/dev/null | sed 's|^/usr/bin/||'
        ;;

      default|stop|off)
        echo "Stopping any running scx_* scheduler — kernel default takes over."
        sudo systemctl stop 'scx*.service' 2>/dev/null || true
        sudo pkill -TERM 'scx_[a-z]+' 2>/dev/null || true
        sleep 1
        if pgrep_scx > /dev/null; then
          echo "warn: scx_* still running:"
          pgrep_scx
        else
          echo "ok — kernel default (BORE) active."
        fi
        ;;

      lavd|bpfland|rusty|central|simple)
        BIN="/usr/bin/scx_{{ MODE }}"
        if [[ ! -x "$BIN" ]]; then
          echo "scx_{{ MODE }} not installed at $BIN — install the gaming layer first (ujust margine-gaming)."
          exit 1
        fi
        # Stop any other scx_* first to avoid loader conflict
        sudo pkill -TERM 'scx_[a-z]+' 2>/dev/null || true
        sleep 1
        echo "Starting $BIN (run in foreground; Ctrl-C to stop)."
        echo "Tip: detach with disown / systemd-run --user if you want it to stick around."
        sudo "$BIN"
        ;;

      *)
        echo "Unknown scheduler: {{ MODE }}"
        echo "Usage: ujust margine-scheduler [status|default|lavd|bpfland|rusty|central|simple]"
        exit 2
        ;;
    esac
