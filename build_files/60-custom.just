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
      2. margine-install-user-extensions       (Tiling Shell + Search Light into ~/.local)
      3. margine-configure-gnome-extensions    (enable/disable per Margine policy)
      4. margine-configure-gnome-keybindings   (Hyprland-style SUPER+1..0, SUPER+E, tiling binds)
      5. margine-configure-gnome-appearance    (accent, theme, dconf for extensions)
      6. margine-configure-default-applications (Zen as browser, Ptyxis terminal, etc.)
      7. margine-configure-gnome-app-folders   (Activities grid grouped by category)

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
    for step in \
        margine-configure-home-layout \
        margine-install-user-extensions \
        margine-configure-gnome-extensions \
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
        - net.davidotek.pupgui2
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
        net.davidotek.pupgui2 \
        org.libretro.RetroArch

    echo
    echo "== Layering gaming host helpers (rpm-ostree) =="
    # tuned + tuned-ppd (separate package since Fedora 39: ppd shim that
    # makes GNOME's power-profiles-daemon UI control tuned profiles).
    # rom-properties has a -gtk subpackage for the Nautilus column
    # extension (the bare package only ships the CLI).
    sudo rpm-ostree install \
        gamescope \
        mangohud \
        vkBasalt \
        gamemode \
        goverlay \
        steam-devices \
        input-remapper \
        tuned \
        tuned-ppd \
        rom-properties-gtk

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
    echo "  - rpm-ostree uninstall the layered host helpers (gamescope, mangohud,"
    echo "    vkBasalt, gamemode, goverlay, steam-devices, input-remapper, tuned,"
    echo "    tuned-ppd, rom-properties-gtk)"
    echo "  - flatpak uninstall the 7 gaming Flatpaks (Steam, Lutris, Heroic,"
    echo "    Bottles, Protontricks, ProtonUp-Qt, RetroArch)"
    echo
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    sudo rpm-ostree uninstall \
        gamescope \
        mangohud \
        vkBasalt \
        gamemode \
        goverlay \
        steam-devices \
        input-remapper \
        tuned \
        tuned-ppd \
        rom-properties-gtk || true

    flatpak uninstall --system -y \
        com.valvesoftware.Steam \
        net.lutris.Lutris \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        net.davidotek.pupgui2 \
        org.libretro.RetroArch || true

    echo
    echo "Done. Reboot to release the rpm-ostree layer."
