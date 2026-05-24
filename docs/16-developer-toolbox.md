# Developer Toolbox and User-Layer Tools

This document is the practical companion to [15-host-layer.md](15-host-layer.md).
The host layer covers what gets installed on the immutable Silverblue base;
this one covers what lives **off** the host: the toolbox container with the
developer tool set, the user-layer additions (Homebrew on Linux, starship),
distrobox for non-Fedora environments, and the GNOME app-grid folders.

The split is intentional. Dev tools change faster than the host can. Putting
them on the host means a reboot for every minor update; putting them in a
toolbox container or under `~/.linuxbrew` decouples them from the OS lifecycle.

## Toolbox: what it is and why we use it

A toolbox is a mutable Fedora container that runs on top of the immutable
Silverblue host. Unlike a regular OCI container:

- it shares your **home directory** — `~/dev`, `~/data`, `~/.config` are the
  same paths inside and outside;
- it shares **network and display** — GUI apps launched from inside work;
- it runs **as your user**, not root, with the same UID/GID;
- it has `dnf` and a full Fedora repo set, so installing tools is normal;
- it survives host upgrades; updating Fedora doesn't reset the container.

Use it as a "dev shell that doesn't pollute the host".

### Lifecycle commands

```sh
toolbox list                              # show containers and images
toolbox enter                             # open a shell in the default container
toolbox run <command>                     # run one command without opening a shell
toolbox enter --container <name>          # use a non-default container
toolbox rm <name>                         # delete a container
toolbox rmi --all                         # delete all toolbox images
```

The prompt inside is decorated with a `⬢` glyph so you always know you're in
the container.

### Tools available out of the box

`scripts/configure-toolbox` (when added) reads the package list from
`toolbox.default.packages` in `declarations/margine-atomic.yaml` and installs
them inside the default container. Until that script lands, install them
manually after `toolbox create`:

```sh
toolbox run sudo dnf install -y \
  git git-credential-libsecret gh tmux ripgrep fd-find jq bat eza btop \
  neovim fastfetch just glow gum \
  gcc gcc-c++ make pkgconf python3-pip nodejs npm \
  podman-compose podman-tui distrobox \
  fish zsh
```

### What each tool does (the non-obvious ones)

| Tool | What it does | Quick example |
| --- | --- | --- |
| `just` | A modern `make` for project task running | `echo 'test:\n\tcargo test' > justfile && just test` |
| `glow` | Render Markdown in the terminal | `glow README.md` |
| `gum` | Build interactive shell scripts | `name=$(gum input --placeholder name)` |
| `fastfetch` | System info banner (alternative to neofetch) | `fastfetch` |
| `eza` | Modern `ls` with git status and tree | `eza -lah --git` |
| `bat` | `cat` with syntax highlight and git diff gutter | `bat src/main.rs` |
| `fd` (binary `fd-find`) | Modern `find` with sane defaults | `fd '\.tsx?$'` |
| `ripgrep` (`rg`) | Faster `grep` that respects .gitignore | `rg 'TODO'` |
| `btop` | Real-time top with charts | `btop` |
| `gh` | GitHub CLI | `gh pr create`, `gh repo clone` |
| `podman-compose` | `docker-compose` syntax against the podman backend | `podman-compose up -d` |
| `podman-tui` | Terminal UI for podman | `podman-tui` |
| `distrobox` | Container with **any** distro (Arch, Ubuntu, Debian, …) | `distrobox create --image archlinux:latest --name arch` |

### Just: a task runner you'll use every day

A `justfile` lives at the root of a project. It's like `make` but the syntax
is friendlier and there's no implicit rules.

Example:

```just
default:
    just --list

fmt:
    cargo fmt --all

test:
    cargo test --workspace

build:
    cargo build --release

ci: fmt test build
```

Then:

```sh
just              # shows the recipes
just test
just ci
```

Margine itself can grow a `justfile` for orchestrating common ops (apply
host layer, run validators, take a baseline diagnostics bundle, etc.).

### Gum: interactive helpers in shell scripts

`gum` gives your bash scripts UI primitives without depending on dialog/whiptail.

```sh
# choose
target=$(gum choose "vm" "hardware" "abort")

# input with placeholder
name=$(gum input --placeholder "Your name")

# confirm
gum confirm "Proceed?" && echo yes || echo no

# styled output
gum style --border double --margin "1" --padding "1 2" "Done."

# spinner
gum spin --spinner dot --title "Working…" -- sleep 3
```

Useful for our own scripts (e.g. `apply-host-layer` could ask "Reboot now?"
via `gum confirm`).

## Distrobox: containers with any distro

Toolbox is locked to Fedora. Distrobox lifts that restriction.

### Why you'd want it

- AUR packages (Arch container for some niche tool you used on Margine OS)
- Ubuntu-only ML/CUDA stacks
- testing builds on different distros
- isolating a project that wants its own system Python / Node

### Lifecycle

```sh
distrobox list
distrobox create --image archlinux:latest --name arch
distrobox enter arch
# inside:
sudo pacman -Syu base-devel git yay
exit

distrobox stop arch
distrobox rm arch
```

### Exporting apps from a distrobox to the host

If you install a GUI app inside the distrobox and want it to appear in the
GNOME app grid:

```sh
# inside the distrobox
distrobox-export --app firefox
# now Firefox appears on the host as if natively installed
```

The exported app launches inside the container but presents in the host's
desktop environment.

### Toolbox vs Distrobox: when to pick which

| Criterion | Toolbox | Distrobox |
| --- | --- | --- |
| Distro | Fedora only | Any |
| Maturity | Red Hat-supported, stable | Community, faster moving |
| Default for Margine dev | yes | for non-Fedora needs |
| Footprint | small | larger (multiple distro images) |

Default to toolbox. Reach for distrobox when toolbox's Fedora is the wrong
distro for a specific job.

## Homebrew on Linux (user-layer)

Brew gives you fast-moving CLI tools that Fedora repos don't always carry or
carry behind. It installs entirely under `~/.linuxbrew` — zero host impact,
no reboot.

### Install

```sh
# install script (idempotent)
bash <(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

# tell your shell where brew lives
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
exec bash
```

After this, `brew` is on PATH.

### What's worth installing from brew (not from Fedora)

Tools that move fast or aren't packaged for Fedora:

```sh
brew install \
  starship \
  zellij \
  lazygit \
  gitui \
  atuin \
  zoxide \
  helix \
  dust \
  duf \
  bottom \
  hyperfine \
  tokei \
  procs
```

Quick descriptions:

| Tool | What it does |
| --- | --- |
| `starship` | Cross-shell prompt with git/version info |
| `zellij` | tmux-like terminal multiplexer with sane defaults |
| `lazygit` | TUI git client (faster than `gh` for local ops) |
| `gitui` | Alternative TUI git (Rust, even faster) |
| `atuin` | Shell history with sync, search, stats |
| `zoxide` | `cd` that learns your habits (`z foo` jumps to your most-used `foo` dir) |
| `helix` | Modal editor with built-in LSP (modern competitor to vim/neovim) |
| `dust` | `du` rewritten with sane output |
| `duf` | `df` rewritten with sane output |
| `bottom` (`btm`) | Cross-platform `top` |
| `hyperfine` | Benchmarks command runs (`hyperfine 'cmd1' 'cmd2'`) |
| `tokei` | Count lines of code by language |
| `procs` | Modern `ps` |

### Brew updates

```sh
brew update                    # refresh formulae
brew upgrade                   # upgrade everything
brew cleanup                   # remove old versions
```

Brew is **not** in the `scripts/update-all` orchestration today. Either run
it manually, or add it to `config/topgrade.toml` (Topgrade has a brew step
out of the box).

## Starship prompt

`starship` is a single-binary prompt that works in bash, zsh, fish, etc. It
shows git status, language versions, command duration, errors, and adapts to
context (showing `cargo` only in Rust dirs, `npm` only in Node dirs, etc.).

### Install (one of two ways)

```sh
# Option A: via brew (recommended, auto-updates)
brew install starship

# Option B: single-binary install under ~/.local/bin
curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin"
```

### Enable in shell

```sh
# bash
echo 'eval "$(starship init bash)"' >> ~/.bashrc

# zsh
echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# fish
echo 'starship init fish | source' >> ~/.config/fish/config.fish

exec bash   # or zsh / fish
```

### Configure

Config lives at `~/.config/starship.toml`. Start from the preset library:

```sh
starship preset gruvbox-rainbow > ~/.config/starship.toml
starship preset nerd-font-symbols > ~/.config/starship.toml
```

A minimal Margine-style config (clean, readable, no emoji noise):

```toml
add_newline = false

format = """$directory$git_branch$git_status$cmd_duration$line_break$character"""

[character]
success_symbol = "[›](bold green)"
error_symbol = "[›](bold red)"

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "

[git_status]
conflicted = "="
ahead = "⇡${count}"
behind = "⇣${count}"
modified = "*"
untracked = "?"

[cmd_duration]
min_time = 2000
format = "took [$duration](bold yellow) "
```

## Container workflows: when to pick which

Margine has four overlapping container-ish surfaces. Use the right one:

| Surface | Use for |
| --- | --- |
| **Host (rpm-ostree layer)** | System services that need to see hardware (libvirt, fwupd, sensors), and codec/Mesa replacement |
| **Toolbox** | Daily CLI dev tools, language toolchains, scripts |
| **Distrobox** | Non-Fedora distro needs (Arch packages, Ubuntu-only stacks) |
| **Podman / podman-compose** | Application containers (databases, services, ephemeral runs) |
| **Flatpak** | GUI applications you use as a desktop user |
| **Brew** | Fast-moving CLI tools not in Fedora repos |

Rule of thumb: if it's a **service** the host needs, layer it. If it's a
**tool** you run yourself, prefer toolbox or brew. If it's a **GUI app**, use
Flatpak. If it's an **application stack** (web + db + redis), use podman.

## GNOME app-grid folders

Daily-use apps live in folders that group by activity, not by alphabet. The
folder layout is declared in
`gnome.app_folders.list` in `declarations/margine-atomic.yaml` and applied
by `scripts/configure-gnome-app-folders --apply`.

| Folder | Pinned apps | Auto-categories |
| --- | --- | --- |
| Internet | Zen Browser | — |
| Productivity | Bitwarden, Thunderbird, LibreOffice suite | Office |
| Graphics | GIMP, Inkscape | Graphics, 2DGraphics, VectorGraphics |
| Photography | darktable | Photography |
| Multimedia | Gapless, Audacity, OBS Studio, EasyEffects, Reaper | AudioVideo, Audio, Video, Music |
| Development | VSCodium | Development, IDE |
| Utilities | — | Utility, Accessibility |
| System | — | System, Settings |

Apply / reset:

```sh
scripts/configure-gnome-app-folders                  # dry-run
scripts/configure-gnome-app-folders --apply          # write via gsettings
scripts/configure-gnome-app-folders --reset --apply  # flat grid again
```

After `--apply` on Wayland (GNOME 44 default), log out and log back in so
GNOME Shell rereads the folder definitions.

## Suggested daily workflow

A concrete day-to-day flow that uses all the layers:

1. **Open terminal** → `toolbox enter` automatically? No: keep one shell on
   host (for `rpm-ostree`, `virsh`, `systemctl`, `flatpak`) and open another
   that auto-enters the toolbox (`exec toolbox enter` at the end of your
   `.bashrc` if interactive and not already inside).
2. **Editor**: VSCodium (Flatpak) for GUI work; neovim or helix in the
   toolbox for terminal sessions.
3. **Source control**: `git` + `gh` from the toolbox; `lazygit` from brew
   when you want a TUI.
4. **Containers / services**: `podman` (on host, comes with Silverblue) for
   one-off runs; `podman-compose` from the toolbox for multi-service stacks.
5. **VMs**: `virt-manager` from host for full-fat KVM virtualization.
6. **AI assistants** (Claude Code, Codex CLI): install in the toolbox via
   `npm install -g ...`; the CLIs run in the toolbox, the VSCodium
   extensions live in the Flatpak (call them with the `flatpak-spawn --host`
   workaround if needed).
7. **System updates**: `rpm-ostree upgrade` (host) + `flatpak --user
   update` + `toolbox run sudo dnf upgrade` + `brew upgrade`. The
   `scripts/update-all` orchestrator covers the first three; brew remains
   manual or via Topgrade.

## Cross-references

- Host baseline package set: [15-host-layer.md](15-host-layer.md)
- Update orchestration: [12-update-orchestration.md](12-update-orchestration.md)
- GNOME look and feel: [08-gnome-personal-layer.md](08-gnome-personal-layer.md)
- Hardware/media drivers: [10-hardware-media-stack.md](10-hardware-media-stack.md)
