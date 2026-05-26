# Margine ujust recipes.
# Loaded by /usr/bin/ujust (Universal Blue's just wrapper) from
# /usr/share/ublue-os/just/. The 99- prefix loads after everything
# Bluefin ships so we can override if needed.

# Apply the full Margine user-state in one shot (home layout, GNOME extensions, keybindings, appearance, default apps, app folders)
[group('Margine')]
margine-bootstrap:
    #!/usr/bin/bash
    set -euo pipefail

    cat <<'EOF'
    == Margine user-state bootstrap ==

    Applies the full Margine user-state declaration. Idempotent — safe
    to re-run after upgrades; each step reports [no change] for keys that
    already match the spec.

    Steps:
      1. margine-configure-home-layout         (~/data + ~/dev + ~/scratch + XDG remap + bookmarks)
      2. margine-install-user-extensions       (Tiling Shell + Search Light into ~/.local)
      3. margine-configure-gnome-extensions    (enable/disable per Margine policy)
      4. margine-configure-gnome-keybindings   (Hyprland-style SUPER+1..0, SUPER+E, tiling binds)
      5. margine-configure-gnome-appearance    (accent, theme, dconf for extensions)
      6. margine-configure-default-applications (Zen as browser, Ptyxis terminal, etc.)
      7. margine-configure-gnome-app-folders   (Activities grid grouped by category)

    No package install. No layer staged. Pure user-state under $HOME and
    user-dconf. Reversible by hand.

    EOF
    read -rp "Continue? [Y/n] " ans
    case "$ans" in ""|[yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    set -x
    margine-configure-home-layout --apply
    margine-install-user-extensions --apply
    margine-configure-gnome-extensions --apply
    margine-configure-gnome-keybindings --apply
    margine-configure-gnome-appearance --apply
    margine-configure-default-applications --apply
    margine-configure-gnome-app-folders --apply
    set +x

    echo
    echo "== Done =="
    echo "Log out and back in (or restart GNOME Shell with Alt+F2 → 'r')"
    echo "to refresh the dock, extensions, keybindings, and bookmarks."


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

      Host RPMs (layered via rpm-ostree — requires reboot to take effect):
        - gamescope       (HDR / per-game compositor / scaling)
        - mangohud        (FPS / GPU / CPU overlay)
        - vkBasalt        (post-processing Vulkan layer)
        - gamemode        (CPU governor + niceness during gameplay)
        - goverlay        (GUI configurator for MangoHud + vkBasalt)
        - steam-devices   (controller udev rules)

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
        net.davidotek.pupgui2

    echo
    echo "== Layering gaming host helpers (rpm-ostree) =="
    sudo rpm-ostree install \
        gamescope \
        mangohud \
        vkBasalt \
        gamemode \
        goverlay \
        steam-devices

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
    echo "  - rpm-ostree uninstall gamescope mangohud vkBasalt gamemode goverlay steam-devices"
    echo "  - flatpak uninstall the 6 gaming Flatpaks (Steam, Lutris, Heroic, Bottles, Protontricks, ProtonUp-Qt)"
    echo
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 0 ;; esac

    sudo rpm-ostree uninstall \
        gamescope \
        mangohud \
        vkBasalt \
        gamemode \
        goverlay \
        steam-devices || true

    flatpak uninstall --system -y \
        com.valvesoftware.Steam \
        net.lutris.Lutris \
        com.heroicgameslauncher.hgl \
        com.usebottles.bottles \
        com.github.Matoking.protontricks \
        net.davidotek.pupgui2 || true

    echo
    echo "Done. Reboot to release the rpm-ostree layer."
