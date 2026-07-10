# Building an atomic Linux distribution — the Margine handbook

This handbook documents, end to end, how Margine is built, and doubles as a
generic guide to building a bootc-based atomic distribution. It is written
from the real code: every snippet is quoted from the repos that produce the
OS people boot, with the file path as caption.

**One repo.** Everything lives in `margine-image`: the build pipeline
(Containerfile, staged build scripts, CI workflows, installer and live-ISO
configs) and the spec it consumes (declarations, branding assets, ADRs, and
docs like this one). Snippet paths are repo-relative: `build_files/`,
`live-env/`, `installer/` and `.github/workflows/` are the pipeline;
`build_files/40-spec-scripts/` holds the vendored scripts and declarations,
`build_files/50-branding/assets/` the branding, and `docs/spec/` the
specification docs and ADRs. (An earlier split kept the spec in a separate
`margine-fedora-atomic` repo. It was merged in and archived on 2026-07-05,
so the build no longer fetches anything.)

**Conventions.** Chapters build on each other but are readable standalone.
Every chapter ends with an *Alternatives & other distros* section, the other
viable ways to solve the same problem and who uses them, because most
decisions here are trade-offs, not truths. Real production incidents appear
as **Lesson** boxes (symptom → root cause → fix); they are indexed in the
appendix. Commands shown against the running system assume a bootc host;
commands in build context run inside the image build.

## Table of contents

- [1. The atomic, image-based OS model](#1-the-atomic-image-based-os-model)
- [----- Base: Bluefin DX (Fedora 44 track, "stable" tag) -----](#------base-bluefin-dx-fedora-44-track-stable-tag------)
  - [1.1 Mutable vs image-based](#11-mutable-vs-image-based)
  - [1.2 ostree: a content-addressed object store for filesystems](#12-ostree-a-content-addressed-object-store-for-filesystems)
- [On Silverblue with composefs (Fedora 39+), /usr is embedded in the root](#on-silverblue-with-composefs-fedora-39-usr-is-embedded-in-the-root)
- [overlay and has no separate mountpoint. This is expected and correct.](#overlay-and-has-no-separate-mountpoint-this-is-expected-and-correct)
  - [1.3 Deployments, staged updates, rollback](#13-deployments-staged-updates-rollback)
- [Distinguish "staged" (bootc switch — finalized by](#distinguish-staged-bootc-switch--finalized-by)
- [ostree-finalize-staged.service at shutdown, BLS entries appear THEN)](#ostree-finalize-stagedservice-at-shutdown-bls-entries-appear-then)
- [from "pending" (rpm-ostree rebase — BLS entries written immediately).](#from-pending-rpm-ostree-rebase--bls-entries-written-immediately)
  - [1.4 The three-zone filesystem contract](#14-the-three-zone-filesystem-contract)
- [This kickstart's only job is to rsync the populated](#this-kickstarts-only-job-is-to-rsync-the-populated)
- [/var/lib/flatpak from the installer rootfs to the target's](#varlibflatpak-from-the-installer-rootfs-to-the-targets)
- [/var/lib/flatpak. ostree+bootc reset /var per-deployment when](#varlibflatpak-ostreebootc-reset-var-per-deployment-when)
- [they install, so without this rsync the Flatpaks would be lost](#they-install-so-without-this-rsync-the-flatpaks-would-be-lost)
- [at first reboot.](#at-first-reboot)
  - [1.5 bootc: the OCI image as the OS transport](#15-bootc-the-oci-image-as-the-os-transport)
- [----- Lint: verify final image is a valid bootc container -----](#------lint-verify-final-image-is-a-valid-bootc-container------)
- [Point the freshly installed system at our public registry so](#point-the-freshly-installed-system-at-our-public-registry-so)
- [subsequent `bootc upgrade` calls follow margine:stable.](#subsequent-bootc-upgrade-calls-follow-marginestable)
  - [1.6 Comparing the atomic models](#16-comparing-the-atomic-models)
  - [1.7 Why Universal Blue (and Margine) picked OCI](#17-why-universal-blue-and-margine-picked-oci)
  - [Alternatives & other distros](#alternatives--other-distros)
- [2. Anatomy of the image repo](#2-anatomy-of-the-image-repo)
  - [2.1 Lineage: ublue-os/image-template](#21-lineage-ublue-osimage-template)
  - [2.2 The Containerfile, stage by stage](#22-the-containerfile-stage-by-stage)
- [/var/home/daniel/dev/margine-image/Containerfile](#varhomedanieldevmargine-imagecontainerfile)
- [----- Build context: scripts that should NOT end up in the final image -----](#------build-context-scripts-that-should-not-end-up-in-the-final-image------)
- [Make installer/flatpaks-base reachable from build.sh at](#make-installerflatpaks-base-reachable-from-buildsh-at)
- [/ctx/installer-flatpaks-base. Single source of truth for the BAKE](#ctxinstaller-flatpaks-base-single-source-of-truth-for-the-bake)
- [Flatpak list (audit §3.5: drop the duplicate here-doc in build.sh).](#flatpak-list-audit-35-drop-the-duplicate-here-doc-in-buildsh)
- [/var/home/daniel/dev/margine-image/Containerfile](#varhomedanieldevmargine-imagecontainerfile)
- [----- Base: Bluefin DX (Fedora 44 track, "stable" tag) -----](#------base-bluefin-dx-fedora-44-track-stable-tag------)
- [/var/home/daniel/dev/margine-image/Containerfile](#varhomedanieldevmargine-imagecontainerfile)
  - [2.3 The build orchestrator and numbered stages](#23-the-build-orchestrator-and-numbered-stages)
- [/var/home/daniel/dev/margine-image/build_files/build.sh](#varhomedanieldevmargine-imagebuildfilesbuildsh)
- [Run every sub-script in lexicographic order. Globs expand](#run-every-sub-script-in-lexicographic-order-globs-expand)
- [deterministically because we name dirs <NN>-<area>.](#deterministically-because-we-name-dirs-nn-area)
- [/var/home/daniel/dev/margine-image/build_files/00-common.sh](#varhomedanieldevmargine-imagebuildfiles00-commonsh)
- [retry_curl <url> <out>        — 5 attempts, 30-150s backoff (COPR/raw.githubusercontent brownouts)](#retrycurl-url-out---------5-attempts-30-150s-backoff-coprrawgithubusercontent-brownouts)
- [retry_curl_strict <url> <out> — same, but aborts the build on missing/empty asset](#retrycurlstrict-url-out--same-but-aborts-the-build-on-missingempty-asset)
- [/var/home/daniel/dev/margine-image/build_files/60-ujust-services/install.sh](#varhomedanieldevmargine-imagebuildfiles60-ujust-servicesinstallsh)
- [Bluefin's /usr/share/ublue-os/just/00-entry.just hardcodes the list](#bluefins-usrshareublue-osjust00-entryjust-hardcodes-the-list)
- [of imported recipe files. The ONLY one declared as optional is](#of-imported-recipe-files-the-only-one-declared-as-optional-is)
- [60-custom.just (via `import?`) — that's the documented extension](#60-customjust-via-import--thats-the-documented-extension)
- [point for downstream distros. Files dropped under any other name](#point-for-downstream-distros-files-dropped-under-any-other-name)
- [(e.g. 99-margine.just) are simply ignored by `ujust --list`.](#eg-99-marginejust-are-simply-ignored-by-ujust---list)
  - [2.4 The `build_files/system_files/` overlay](#24-the-systemfiles-overlay)
- [/var/home/daniel/dev/margine-image/build_files/10-os-identity/install.sh](#varhomedanieldevmargine-imagebuildfiles10-os-identityinstallsh)
- [The whole tree gets rsync'd into the rootfs at "/" so file paths in](#the-whole-tree-gets-rsyncd-into-the-rootfs-at--so-file-paths-in)
- [the repo mirror their final installed location. Same pattern as](#the-repo-mirror-their-final-installed-location-same-pattern-as)
- [Bluefin's system_files/shared/.](#bluefins-systemfilesshared)
- [/var/home/daniel/dev/margine-image/build_files/10-os-identity/install.sh](#varhomedanieldevmargine-imagebuildfiles10-os-identityinstallsh)
  - [2.5 What may write where at build time](#25-what-may-write-where-at-build-time)
- [/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh](#varhomedanieldevmargine-imagebuildfilescustom-kernelinstallsh)
- [akmodsbuild on bootc images skips signing if /var isn't writable; patch](#akmodsbuild-on-bootc-images-skips-signing-if-var-isnt-writable-patch)
- [it out so akmods proceeds inside the container build.](#it-out-so-akmods-proceeds-inside-the-container-build)
- [/var/home/daniel/dev/margine-image/build_files/build-margine-extensions.sh](#varhomedanieldevmargine-imagebuildfilesbuild-margine-extensionssh)
- [NO transient dnf installs. Lesson learned the hard way 2026-06-04:](#no-transient-dnf-installs-lesson-learned-the-hard-way-2026-06-04)
- [  dnf5 -y remove jq    # STILL broke things: scx-tools-git declares](#dnf5--y-remove-jq-----still-broke-things-scx-tools-git-declares)
- [                       # Requires: jq → removal cascades through](#requires-jq--removal-cascades-through)
- [                       # scx-tools-git → scx-scheds → 16 packages.](#scx-tools-git--scx-scheds--16-packages)
- [Robust fix: don't add or remove dnf packages here at all. Use](#robust-fix-dont-add-or-remove-dnf-packages-here-at-all-use)
- [Python stdlib (always present) for JSON parsing + zip extraction.](#python-stdlib-always-present-for-json-parsing--zip-extraction)
  - [2.6 Commit and lint](#26-commit-and-lint)
- [/var/home/daniel/dev/margine-image/Containerfile](#varhomedanieldevmargine-imagecontainerfile)
- [----- Lint: verify final image is a valid bootc container -----](#------lint-verify-final-image-is-a-valid-bootc-container------)
  - [Alternatives & other distros](#alternatives--other-distros)
- [3. Replacing the kernel in an atomic image](#3-replacing-the-kernel-in-an-atomic-image)
  - [3.1 Why a custom kernel at all](#31-why-a-custom-kernel-at-all)
  - [3.2 The swap, step by step](#32-the-swap-step-by-step)
  - [3.3 Out-of-tree modules: the akmods pattern in a container](#33-out-of-tree-modules-the-akmods-pattern-in-a-container)
  - [3.4 Regenerating the initramfs in-container](#34-regenerating-the-initramfs-in-container)
  - [3.5 Validating the swap](#35-validating-the-swap)
  - [Alternatives & other distros](#alternatives--other-distros)
- [4. Secure Boot for a custom kernel: shim → MOK](#4-secure-boot-for-a-custom-kernel-shim--mok)
  - [4.1 The trust chain and where a custom kernel breaks it](#41-the-trust-chain-and-where-a-custom-kernel-breaks-it)
  - [4.2 Key material: what is secret and what is not](#42-key-material-what-is-secret-and-what-is-not)
- [margine-image/build_files/custom-kernel/install.sh:36-44](#margine-imagebuildfilescustom-kernelinstallsh36-44)
- [margine-image/.github/workflows/build.yml:125-136](#margine-imagegithubworkflowsbuildyml125-136)
- [margine-image/Containerfile:39-46](#margine-imagecontainerfile39-46)
  - [4.3 Signing at image build](#43-signing-at-image-build)
- [margine-image/build_files/custom-kernel/install.sh:98-108](#margine-imagebuildfilescustom-kernelinstallsh98-108)
- [margine-image/build_files/custom-kernel/install.sh:110-129 (trimmed: .gz arm omitted)](#margine-imagebuildfilescustom-kernelinstallsh110-129-trimmed-gz-arm-omitted)
  - [4.4 Shipping the cert + the first-boot fallback service](#44-shipping-the-cert--the-first-boot-fallback-service)
- [margine-image/build_files/custom-kernel/install.sh:139-162 (trimmed)](#margine-imagebuildfilescustom-kernelinstallsh139-162-trimmed)
  - [4.5 The ISO path: stage the request *before* the first installed boot](#45-the-iso-path-stage-the-request-before-the-first-installed-boot)
- [margine-image/disk_config/iso-gnome.toml:80-136 (trimmed)](#margine-imagediskconfigiso-gnometoml80-136-trimmed)
  - [4.6 Why the passphrase is public by design](#46-why-the-passphrase-is-public-by-design)
  - [4.7 Kernel lockdown implications](#47-kernel-lockdown-implications)
  - [4.8 Recovery and verification](#48-recovery-and-verification)
  - [4.9 Alternatives & other distros](#49-alternatives--other-distros)
- [5. Shipping desktop opinion as data](#5-shipping-desktop-opinion-as-data)
  - [5.1 Defaults: gschema overrides vs the dconf distro database](#51-defaults-gschema-overrides-vs-the-dconf-distro-database)
- [margine-image/build_files/30-gnome-defaults/install.sh (heredoc, trimmed)](#margine-imagebuildfiles30-gnome-defaultsinstallsh-heredoc-trimmed)
- [/usr/share/glib-2.0/schemas/zz1-margine.gschema.override](#usrshareglib-20schemaszz1-marginegschemaoverride)
- [margine-image/build_files/30-gnome-defaults/install.sh:94-107](#margine-imagebuildfiles30-gnome-defaultsinstallsh94-107)
- [margine-image/build_files/30-gnome-defaults/install.sh:88-93](#margine-imagebuildfiles30-gnome-defaultsinstallsh88-93)
- [Extension preferences use dconf keyfiles rather than gschema](#extension-preferences-use-dconf-keyfiles-rather-than-gschema)
- [overrides. GNOME Shell Extension.getSettings() loads an extension's](#overrides-gnome-shell-extensiongetsettings-loads-an-extensions)
- [local schemas/ directory ahead of the global schema source, so global](#local-schemas-directory-ahead-of-the-global-schema-source-so-global)
- [gschema override defaults for org.gnome.shell.extensions.* can be](#gschema-override-defaults-for-orggnomeshellextensions-can-be)
- [shadowed at runtime. dconf defaults are keyed by path and apply to](#shadowed-at-runtime-dconf-defaults-are-keyed-by-path-and-apply-to)
- [the actual settings backend the extension reads.](#the-actual-settings-backend-the-extension-reads)
- [margine-image/build_files/30-gnome-defaults/dconf/01-margine-dash-to-dock (trimmed)](#margine-imagebuildfiles30-gnome-defaultsdconf01-margine-dash-to-dock-trimmed)
- [Anti-collision with Margine's Super+1..0 workspace binds.](#anti-collision-with-margines-super10-workspace-binds)
- [margine-image/build_files/30-gnome-defaults/dconf/07-margine-custom-keybindings](#margine-imagebuildfiles30-gnome-defaultsdconf07-margine-custom-keybindings)
  - [5.2 GNOME extensions: build-time install, downstream patches](#52-gnome-extensions-build-time-install-downstream-patches)
- [margine-image/build_files/build-margine-extensions.sh:56-57,102-117 (trimmed)](#margine-imagebuildfilesbuild-margine-extensionssh56-57102-117-trimmed)
- [margine-image/build_files/build-margine-extensions.sh:90,124-127](#margine-imagebuildfilesbuild-margine-extensionssh90124-127)
  - [5.3 systemd user drop-ins as integration glue](#53-systemd-user-drop-ins-as-integration-glue)
- [margine-image/build_files/45-wsf/install.sh:58-66 (trimmed)](#margine-imagebuildfiles45-wsfinstallsh58-66-trimmed)
- [Pre-enable the preload for gnome-shell system-wide. ... inject](#pre-enable-the-preload-for-gnome-shell-system-wide--inject)
- [LD_PRELOAD only into the gnome-shell unit (template drop-in covers](#ldpreload-only-into-the-gnome-shell-unit-template-drop-in-covers)
- [every org.gnome.Shell@<instance>.service, including the GDM greeter,](#every-orggnomeshellinstanceservice-including-the-gdm-greeter)
- [where it is a no-op). The library scrubs itself from LD_PRELOAD after](#where-it-is-a-no-op-the-library-scrubs-itself-from-ldpreload-after)
- [loading, so gnome-shell's children do not inherit it.](#loading-so-gnome-shells-children-do-not-inherit-it)
- [margine-image/build_files/45-wsf/margine-wsf-preload.conf](#margine-imagebuildfiles45-wsfmargine-wsf-preloadconf)
  - [5.4 ujust recipes: the user-facing API](#54-ujust-recipes-the-user-facing-api)
- [margine-image/build_files/60-ujust-services/install.sh:11-23 (trimmed)](#margine-imagebuildfiles60-ujust-servicesinstallsh11-23-trimmed)
- [Bluefin's /usr/share/ublue-os/just/00-entry.just hardcodes the list](#bluefins-usrshareublue-osjust00-entryjust-hardcodes-the-list)
- [of imported recipe files. The ONLY one declared as optional is](#of-imported-recipe-files-the-only-one-declared-as-optional-is)
- [60-custom.just (via `import?`) — that's the documented extension](#60-customjust-via-import--thats-the-documented-extension)
- [point for downstream distros. Files dropped under any other name](#point-for-downstream-distros-files-dropped-under-any-other-name)
- [(e.g. 99-margine.just) are simply ignored by `ujust --list`.](#eg-99-marginejust-are-simply-ignored-by-ujust---list)
- [margine-image/build_files/60-custom.just:394-419 (trimmed)](#margine-imagebuildfiles60-customjust394-419-trimmed)
  - [5.5 tuned profiles + the scheduler picker](#55-tuned-profiles--the-scheduler-picker)
- [margine-image/build_files/system_files/usr/lib/tuned/profiles/balanced-margine/tuned.conf](#margine-imagebuildfilessystemfilesusrlibtunedprofilesbalanced-marginetunedconf)
- [.../balanced-margine/script.sh](#balanced-marginescriptsh)
- [margine-image/build_files/system_files/usr/libexec/margine/scheduler-picker:105-122 (trimmed)](#margine-imagebuildfilessystemfilesusrlibexecmarginescheduler-picker105-122-trimmed)
- [margine-image/build_files/system_files/usr/share/applications/margine-scheduler.desktop (trimmed)](#margine-imagebuildfilessystemfilesusrshareapplicationsmargine-schedulerdesktop-trimmed)
  - [5.6 Plymouth: a script theme with a working LUKS prompt](#56-plymouth-a-script-theme-with-a-working-luks-prompt)
- [margine-image/build_files/50-branding/install.sh:78-97 (trimmed)](#margine-imagebuildfiles50-brandinginstallsh78-97-trimmed)
- [Bluefin DX ships Plymouth core but not the script plugin.](#bluefin-dx-ships-plymouth-core-but-not-the-script-plugin)
- [build_files/50-branding/assets/plymouth/margine.plymouth](#build_files50-brandingassetsplymouthmargineplymouth)
  - [5.7 Branding: the paths GNOME actually reads](#57-branding-the-paths-gnome-actually-reads)
- [margine-image/build_files/50-branding/install.sh:182-190 (trimmed)](#margine-imagebuildfiles50-brandinginstallsh182-190-trimmed)
- [fedora_logo_med.png is shown on LIGHT backgrounds (so a dark-text](#fedoralogomedpng-is-shown-on-light-backgrounds-so-a-dark-text)
- [wordmark); fedora_whitelogo_med.png on DARK backgrounds (white-text](#wordmark-fedorawhitelogomedpng-on-dark-backgrounds-white-text)
- [wordmark). gnome-control-center scales these 1200×300 transparent PNGs](#wordmark-gnome-control-center-scales-these-1200300-transparent-pngs)
- [to the About-panel logo slot.](#to-the-about-panel-logo-slot)
- [margine-image/build_files/50-branding/install.sh:201-208](#margine-imagebuildfiles50-brandinginstallsh201-208)
  - [Alternatives & other distros](#alternatives--other-distros)
- [6. Application payload: Flatpaks and the offline-docs module](#6-application-payload-flatpaks-and-the-offline-docs-module)
  - [6.1 Three delivery tiers](#61-three-delivery-tiers)
- [  BAKE (kickstart %post --nochroot at install time, ~22 apps):](#bake-kickstart-post---nochroot-at-install-time-22-apps)
- [    Browser, mail, password, office, image+pdf+video viewer,](#browser-mail-password-office-imagepdfvideo-viewer)
- [    GNOME productivity suite. Apps the user expects to find ALREADY](#gnome-productivity-suite-apps-the-user-expects-to-find-already)
- [    INSTALLED on the desktop the first time they log in.](#installed-on-the-desktop-the-first-time-they-log-in)
- [  DEFER (.preinstall files + flatpak-preinstall.service at first](#defer-preinstall-files--flatpak-preinstallservice-at-first)
- [  boot, ~12 apps):](#boot-12-apps)
- [    Heavy creative apps (GIMP, Inkscape, darktable, OBS, Reaper,](#heavy-creative-apps-gimp-inkscape-darktable-obs-reaper)
- [    ...) the user doesn't need in the first 10 min after first](#the-user-doesnt-need-in-the-first-10-min-after-first)
- [    login. flatpak-preinstall.service downloads them in background.](#login-flatpak-preinstallservice-downloads-them-in-background)
  - [6.2 One list, three consumers](#62-one-list-three-consumers)
- [fm.reaper.Reaper — INTENTIONALLY EXCLUDED from BAKE 2026-06-05:](#fmreaperreaper--intentionally-excluded-from-bake-2026-06-05)
- [Reaper's apply_extra script downloads the proprietary binary at](#reapers-applyextra-script-downloads-the-proprietary-binary-at)
- [install time, which fails inside the podman build container with](#install-time-which-fails-inside-the-podman-build-container-with)
- ["apply_extra script failed, exit status 256"](#applyextra-script-failed-exit-status-256)
  - [6.3 BAKE: build-time install, install-time rsync](#63-bake-build-time-install-install-time-rsync)
- [Copied straight from Bazzite's installer/build.sh — without these the](#copied-straight-from-bazzites-installerbuildsh--without-these-the)
- [apply_extra step (used by Reaper, Steam, openh264 for binary blobs)](#applyextra-step-used-by-reaper-steam-openh264-for-binary-blobs)
- [fails with:](#fails-with)
- [  F: Unable to provide a temporary home directory in the sandbox:](#f-unable-to-provide-a-temporary-home-directory-in-the-sandbox)
- [     Unable to open path "/var/roothome": No such file or directory](#unable-to-open-path-varroothome-no-such-file-or-directory)
- [  bwrap: cannot open /proc/sys/user/max_user_namespaces:](#bwrap-cannot-open-procsysusermaxusernamespaces)
- [     Read-only file system](#read-only-file-system)
  - [6.4 DEFER: declarative first-boot via `preinstall.d`](#64-defer-declarative-first-boot-via-preinstalld)
  - [6.5 Notify-and-install-later: first-boot UX for DEFER](#65-notify-and-install-later-first-boot-ux-for-defer)
  - [6.6 On-demand: `ujust margine-gaming`](#66-on-demand-ujust-margine-gaming)
- [gamescope + vkBasalt are the only RPMs strictly gaming-only.](#gamescope--vkbasalt-are-the-only-rpms-strictly-gaming-only)
  - [6.7 System Flatpak overrides](#67-system-flatpak-overrides)
  - [6.8 The offline-docs module, end-to-end](#68-the-offline-docs-module-end-to-end)
  - [Alternatives & other distros](#alternatives--other-distros)
  - [Takeaways](#takeaways)
- [7. Rechunking: shipping a 14 GB OS as reusable chunks](#7-rechunking-shipping-a-14-gb-os-as-reusable-chunks)
  - [7.1 Why naive podman layers churn](#71-why-naive-podman-layers-churn)
  - [7.2 What the client does with layers](#72-what-the-client-does-with-layers)
  - [7.3 hhd-dev/rechunk: ostree-aware re-layering](#73-hhd-devrechunk-ostree-aware-re-layering)
- [/var/home/daniel/dev/margine-image/.github/workflows/build.yml (lines 448-464)](#varhomedanieldevmargine-imagegithubworkflowsbuildyml-lines-448-464)
- [build.yml (lines 254-256)](#buildyml-lines-254-256)
- [build.yml (lines 270-272)](#buildyml-lines-270-272)
- [build.yml (lines 483-492, trimmed)](#buildyml-lines-483-492-trimmed)
  - [7.4 Rechunk is not just an optimization: composefs canonicalization](#74-rechunk-is-not-just-an-optimization-composefs-canonicalization)
- [/var/home/daniel/dev/margine-image/build_files/10-os-identity/install.sh (lines 80-87)](#varhomedanieldevmargine-imagebuildfiles10-os-identityinstallsh-lines-80-87)
- [/usr/lib/os-release — the canonical location written as a regular file.](#usrlibos-release--the-canonical-location-written-as-a-regular-file)
- [/etc/os-release — relative symlink to the canonical location.](#etcos-release--relative-symlink-to-the-canonical-location)
- [/var/home/daniel/dev/margine-image/build_files/70-passwd-seed-boot/install.sh (lines 18-21)](#varhomedanieldevmargine-imagebuildfiles70-passwd-seed-bootinstallsh-lines-18-21)
- [Workaround: ship a systemd oneshot that re-applies the seed at](#workaround-ship-a-systemd-oneshot-that-re-applies-the-seed-at)
- [every boot, before sysinit. Idempotent (only seeds if /etc/passwd](#every-boot-before-sysinit-idempotent-only-seeds-if-etcpasswd)
- [is below the entry threshold). Doesn't depend on rechunk preserving](#is-below-the-entry-threshold-doesnt-depend-on-rechunk-preserving)
- [/etc — it doesn't need to.](#etc--it-doesnt-need-to)
- [70-passwd-seed-boot/install.sh (unit body, lines 65-75, comment trimmed)](#70-passwd-seed-bootinstallsh-unit-body-lines-65-75-comment-trimmed)
- [... DO NOT add After=local-fs.target: it creates an ordering cycle](#do-not-add-afterlocal-fstarget-it-creates-an-ordering-cycle)
- [through systemd-tmpfiles-setup-dev.service ... (incident 2026-06-01)](#through-systemd-tmpfiles-setup-devservice--incident-2026-06-01)
  - [7.5 zstd:chunked and partial pulls](#75-zstdchunked-and-partial-pulls)
  - [7.6 Alternatives & other distros](#76-alternatives--other-distros)
  - [7.7 Takeaways](#77-takeaways)
- [8. Supply chain: cosign signing, host verification, and pinning](#8-supply-chain-cosign-signing-host-verification-and-pinning)
  - [8.1 The cosign keypair](#81-the-cosign-keypair)
- [margine-image/.gitignore](#margine-imagegitignore)
- [margine-image/secrets/cosign.pub](#margine-imagesecretscosignpub)
  - [8.2 Sign by digest, in a separate CI job](#82-sign-by-digest-in-a-separate-ci-job)
- [margine-image/.github/workflows/build.yml (header comment)](#margine-imagegithubworkflowsbuildyml-header-comment)
- [build_push does the heavy work (buildah + rechunk + skopeo push,](#buildpush-does-the-heavy-work-buildah--rechunk--skopeo-push)
- [~25 min). sign is a separate cheap job (~1 min) that signs the](#25-min-sign-is-a-separate-cheap-job-1-min-that-signs-the)
- [pushed manifest *by digest* instead of by tag — cosign warns](#pushed-manifest-by-digest-instead-of-by-tag--cosign-warns)
- [against by-tag signing as it's racy.](#against-by-tag-signing-as-its-racy)
- [On a failed sign step, `gh run rerun --failed <run-id>` re-runs](#on-a-failed-sign-step-gh-run-rerun---failed-run-id-re-runs)
- [only the sign job (~1 min) instead of redoing the whole build.](#only-the-sign-job-1-min-instead-of-redoing-the-whole-build)
- [margine-image/.github/workflows/build.yml — "Push rechunked image to GHCR"](#margine-imagegithubworkflowsbuildyml--push-rechunked-image-to-ghcr)
- [margine-image/.github/workflows/build.yml — sign job](#margine-imagegithubworkflowsbuildyml--sign-job)
- [margine-image/.github/workflows/smoke-boot.yml — promote step](#margine-imagegithubworkflowssmoke-bootyml--promote-step)
  - [8.3 SBOM as a signed OCI referrer](#83-sbom-as-a-signed-oci-referrer)
- [margine-image/.github/workflows/build.yml — "Attach + cosign-sign SBOM"](#margine-imagegithubworkflowsbuildyml--attach--cosign-sign-sbom)
  - [8.4 Host-side verification: policy.json + registries.d](#84-host-side-verification-policyjson--registriesd)
- [margine-image/README.md](#margine-imagereadmemd)
  - [8.5 SHA-pinning actions and base images](#85-sha-pinning-actions-and-base-images)
- [margine-image/.github/workflows/build.yml](#margine-imagegithubworkflowsbuildyml)
- [margine-image/.github/workflows/build.yml — specref step + label](#margine-imagegithubworkflowsbuildyml--specref-step--label)
  - [8.6 Secrets handling in GHA](#86-secrets-handling-in-gha)
- [margine-image/.github/workflows/build.yml](#margine-imagegithubworkflowsbuildyml)
- [margine-image/Containerfile](#margine-imagecontainerfile)
  - [8.7 Alternatives & other distros](#87-alternatives--other-distros)
  - [8.8 What this buys, and what it doesn't](#88-what-this-buys-and-what-it-doesnt)
- [9. CI/CD for an OS: GitHub Actions as the build farm](#9-cicd-for-an-os-github-actions-as-the-build-farm)
  - [9.1 Why GitHub-hosted (the PVE builder post-mortem)](#91-why-github-hosted-the-pve-builder-post-mortem)
- [History (2026-06-01): we used to run this on a self-hosted PVE VM](#history-2026-06-01-we-used-to-run-this-on-a-self-hosted-pve-vm)
- [(margine-builder, VM 170). After two freezes — the second one](#margine-builder-vm-170-after-two-freezes--the-second-one)
- [taking the entire PVE host down with ZFS spacemap corruption (see](#taking-the-entire-pve-host-down-with-zfs-spacemap-corruption-see)
- [proxmox-pve1/docs/operations/zfs-spacemap-corruption-recovery.md)](#proxmox-pve1docsoperationszfs-spacemap-corruption-recoverymd)
- [— the self-hosted runner has been decommissioned. GitHub-hosted](#the-self-hosted-runner-has-been-decommissioned-github-hosted)
- [is exactly the "container that wakes up when a job arrives and](#is-exactly-the-container-that-wakes-up-when-a-job-arrives-and)
- [shuts down after" model we wanted.](#shuts-down-after-model-we-wanted)
  - [9.2 build.yml: triggers, concurrency, build](#92-buildyml-triggers-concurrency-build)
  - [9.3 Validators as gates inside the build](#93-validators-as-gates-inside-the-build)
- [dash-to-dock background customisation present (cosmetic regression sentinel)](#dash-to-dock-background-customisation-present-cosmetic-regression-sentinel)
- [search-light rounded-corners daniel default: border-radius=7.0](#search-light-rounded-corners-daniel-default-border-radius70)
- [(the value is an INDEX 0-7 into the extension's px table, not](#the-value-is-an-index-0-7-into-the-extensions-px-table-not)
- [pixels — 7 = 32px max rounding; the old 30 was out of range and](#pixels--7--32px-max-rounding-the-old-30-was-out-of-range-and)
- [silently ignored. See #94.)](#silently-ignored-see-94)
  - [9.4 Push to GHCR and the job split](#94-push-to-ghcr-and-the-job-split)
- [On a failed sign step, `gh run rerun --failed <run-id>` re-runs](#on-a-failed-sign-step-gh-run-rerun---failed-run-id-re-runs)
- [only the sign job (~1 min) instead of redoing the whole build.](#only-the-sign-job-1-min-instead-of-redoing-the-whole-build)
- [That's the whole point of the split — failure cost dominates](#thats-the-whole-point-of-the-split--failure-cost-dominates)
- [the few seconds of cross-job overhead.](#the-few-seconds-of-cross-job-overhead)
  - [9.5 The QEMU smoke gate and `:stable` promotion](#95-the-qemu-smoke-gate-and-stable-promotion)
  - [9.6 Disk images and ISOs: build-disk.yml](#96-disk-images-and-isos-build-diskyml)
  - [9.7 Artifact egress pain → Internet Archive](#97-artifact-egress-pain--internet-archive)
  - [9.8 Alternatives & other distros](#98-alternatives--other-distros)
- [10. Getting the image onto metal: installers and ISOs](#10-getting-the-image-onto-metal-installers-and-isos)
  - [10.1 Path A — bootc-image-builder Anaconda ISO](#101-path-a--bootc-image-builder-anaconda-iso)
  - [10.2 Path B — Titanoboa live ISO](#102-path-b--titanoboa-live-iso)
  - [10.3 Escape hatch: plain `bootc install to-disk`](#103-escape-hatch-plain-bootc-install-to-disk)
  - [10.4 Alternatives & other distros](#104-alternatives--other-distros)
- [11. Shipping and day-2 operations](#11-shipping-and-day-2-operations)
  - [11.1 GHCR tag strategy](#111-ghcr-tag-strategy)
- [margine-image/.github/workflows/build.yml](#margine-imagegithubworkflowsbuildyml)
- [margine-image/.github/workflows/build.yml — "Push rechunked image to GHCR"](#margine-imagegithubworkflowsbuildyml--push-rechunked-image-to-ghcr)
- [margine-image/.github/workflows/smoke-boot.yml — "Promote candidate → stable"](#margine-imagegithubworkflowssmoke-bootyml--promote-candidate--stable)
- [margine-image/build_files/70-passwd-seed-boot/install.sh — /usr/libexec/margine-staleness-check](#margine-imagebuildfiles70-passwd-seed-bootinstallsh--usrlibexecmargine-staleness-check)
  - [11.2 ISO distribution: torrent-first via Internet Archive](#112-iso-distribution-torrent-first-via-internet-archive)
- [margine-image/.github/workflows/build-disk.yml — publish_ia](#margine-imagegithubworkflowsbuild-diskyml--publishia)
  - [11.3 The website pipeline is part of the product](#113-the-website-pipeline-is-part-of-the-product)
- [margine-image/.github/workflows/build-disk.yml — bump_site](#margine-imagegithubworkflowsbuild-diskyml--bumpsite)
  - [11.4 Client side: bootc upgrade + uupd orchestration](#114-client-side-bootc-upgrade--uupd-orchestration)
- [build_files/40-spec-scripts/declarations/margine-atomic.yaml](#build_files40-spec-scriptsdeclarationsmargine-atomicyaml)
- [docs/spec/config/topgrade.toml](#docsspecconfigtopgradetoml)
- [margine-image/live-env/src/build.sh — units that must not run in a live session](#margine-imagelive-envsrcbuildsh--units-that-must-not-run-in-a-live-session)
- [build_files/40-spec-scripts/scripts/validate-staged-deployment](#build_files40-spec-scriptsscriptsvalidate-staged-deployment)
  - [11.5 Rollback, pinning, /etc merge and drift](#115-rollback-pinning-etc-merge-and-drift)
- [docs/spec/02-install-lab.md — before the CachyOS kernel experiment](#docsspec02-install-labmd--before-the-cachyos-kernel-experiment)
  - [11.6 The rebase path from Bluefin DX](#116-the-rebase-path-from-bluefin-dx)
- [margine-image/README.md — Option A](#margine-imagereadmemd--option-a)
- [build_files/40-spec-scripts/scripts/validate-staged-deployment](#build_files40-spec-scriptsscriptsvalidate-staged-deployment)
- [THE check that motivated Bug 5: ostree-prepare-root must be inside](#the-check-that-motivated-bug-5-ostree-prepare-root-must-be-inside)
- [the initramfs, otherwise switch-root cannot pivot /sysroot ...](#the-initramfs-otherwise-switch-root-cannot-pivot-sysroot)
  - [11.7 Alternatives & other distros](#117-alternatives--other-distros)
- [12. Trust but verify: validators, diagnostics, and the lesson catalog](#12-trust-but-verify-validators-diagnostics-and-the-lesson-catalog)
  - [12.1 The margine-validate-* suite](#121-the-margine-validate--suite)
- [On Silverblue with composefs (Fedora 39+), /usr is embedded in the root](#on-silverblue-with-composefs-fedora-39-usr-is-embedded-in-the-root)
- [overlay and has no separate mountpoint. This is expected and correct.](#overlay-and-has-no-separate-mountpoint-this-is-expected-and-correct)
  - [12.2 margine-collect-diagnostics](#122-margine-collect-diagnostics)
  - [12.3 QEMU validation workflow for ISOs](#123-qemu-validation-workflow-for-isos)
- [Multi-marker approach (2026-06-01): systemd recent does NOT](#multi-marker-approach-2026-06-01-systemd-recent-does-not)
- [always emit "Reached target multi-user.target" verbatim on](#always-emit-reached-target-multi-usertarget-verbatim-on)
- [the serial console (seen on Fedora 44 with CachyOS kernel ...)](#the-serial-console-seen-on-fedora-44-with-cachyos-kernel)
  - [12.4 Lesson catalog](#124-lesson-catalog)
  - [12.5 Alternatives & other distros](#125-alternatives--other-distros)

---

# 1. The atomic, image-based OS model

Margine is not "a Fedora with packages preinstalled". It is an **OCI container image that boots**. The running system is a read-only checkout of that image; updating means downloading the next image and rebooting into it; a broken update means rebooting into the previous one. This chapter explains the machinery underneath (ostree, deployments, the bootc transport, the three-zone filesystem contract) and why this model was chosen over the half-dozen other ways to build an atomic distro.

The whole product fits in one sentence from the top of the image repo:

```dockerfile
# ----- Base: Bluefin DX (Fedora 44 track, "stable" tag) -----
FROM ghcr.io/ublue-os/bluefin-dx:stable
```
*`/var/home/daniel/dev/margine-image/Containerfile` (line 32)*

A distro is a `FROM` line plus deltas. Everything else in this handbook is about making those deltas correct, signed, and bootable.

## 1.1 Mutable vs image-based

A traditional package-managed system (`dnf`, `pacman`, `apt`) mutates the live root filesystem in place. Consequences:

- every machine is a unique snowflake: install order, partial upgrades, leftover config;
- a failed mid-transaction upgrade leaves the system in an undefined state;
- "rollback" means restoring from backup or downgrade gymnastics;
- you cannot test "the OS" in CI, because there is no single artifact that *is* the OS.

The image-based model inverts this. The OS is built once, centrally, as an immutable artifact. Machines *deploy* that artifact and never modify it. State that must vary per machine is confined to explicitly writable zones. The practical payoffs:

- **Atomicity**: an update either fully applies or doesn't exist. There is no half-upgraded state, the new deployment is assembled completely on disk before the bootloader ever points at it.
- **Rollback**: the previous deployment is kept; one boot-menu entry (or `bootc rollback`) returns to it byte-for-byte.
- **Testability**: Margine's CI boots the exact artifact in QEMU before tagging it `:stable` (chapter on CI). The bytes a user pulls are the bytes that passed the boot test.
- **Fleet identity**: every machine on the same digest runs the same `/usr`. Bug reports become reproducible.

## 1.2 ostree: a content-addressed object store for filesystems

ostree is "git for operating system binaries". The on-disk layout under `/ostree`:

- `/ostree/repo/objects/`, a content-addressed store: every file is stored once under its checksum, like git blobs.
- **Commits**, a commit is a complete filesystem tree (metadata + dirtree objects pointing into the object store), identified by a checksum.
- `/ostree/deploy/<stateroot>/deploy/<commit>.<serial>/`, **deployments**: hardlink checkouts of a commit. Files are hardlinks into the object store, so ten deployments of nearly-identical trees cost roughly one tree of disk.

At boot, the initramfs `ostree` module (more on why that matters in the kernel chapter) reads the `ostree=` karg, bind-mounts the chosen deployment as `/`, the real disk root at `/sysroot`, and mounts the OS content read-only. On Fedora 39+ this is fronted by **composefs**: instead of trusting the hardlink farm directly, an erofs+overlay view is constructed over the object store, which makes the root tamper-evident and removes the "someone ran `chattr -i` and edited a hardlinked object" hole. A side effect that trips up validators: `/usr` no longer has its own mountpoint. Margine's layout validator handles exactly this:

```bash
# On Silverblue with composefs (Fedora 39+), /usr is embedded in the root
# overlay and has no separate mountpoint. This is expected and correct.
if findmnt /usr >/dev/null 2>&1; then
  ...
else
  root_fstype_inner=$(mount_field FSTYPE /)
  if [[ "$root_fstype_inner" == "overlay" ]]; then
    ok "/usr is embedded in the composefs root overlay (expected on Silverblue)"
```
*`build_files/40-spec-scripts/scripts/validate-atomic-layout` (lines 113-123)*

Practical effect: do not write health checks that assert `findmnt /usr`, on a composefs system `/` is an `overlay` and `/usr` is inside it.

## 1.3 Deployments, staged updates, rollback

A machine keeps multiple deployments (booted, rollback, optionally pinned via `ostree admin pin`). The update lifecycle:

1. **Fetch**: `bootc upgrade` (or `rpm-ostree upgrade`) pulls the new image/commit. The live system is untouched.
2. **Stage**: the new deployment is checked out under `/ostree/deploy/...`, its `/etc` is produced by the 3-way merge (§1.4), and it is marked *staged*. `ostree-finalize-staged.service` writes the bootloader entry at clean shutdown, the very last moment, so a crash mid-update leaves the old bootloader config intact.
3. **Reboot**: the bootloader's default entry is the new deployment. The old one remains as the second menu entry.
4. **Rollback**: `bootc rollback` swaps the boot order back; or pick the older entry in GRUB by hand. Nothing is rebuilt, the old tree never left the object store.

Two asymmetries to internalize: `/etc` rolls back with the deployment (each deployment carries its own merged `/etc`), but `/var` never rolls back, treat `/var` schema changes like a database during a blue/green deploy, compatible in both directions. And the *staged* vs *pending* distinction looks like a bug the first time you meet it: after `bootc switch`, `ls /boot/loader/entries/` shows nothing new. Margine's pre-reboot validator documents why:

```bash
# Distinguish "staged" (bootc switch — finalized by
# ostree-finalize-staged.service at shutdown, BLS entries appear THEN)
# from "pending" (rpm-ostree rebase — BLS entries written immediately).
...
if [[ "$IS_STAGED" == "true" ]]; then
  info "Deployment is STAGED (bootc switch flow). BLS entries are not"
  info "rewritten now — ostree-finalize-staged.service does that at the"
  info "next shutdown, so GRUB sees the new entry on the boot AFTER."
  ok "BLS entry update is correctly deferred (this is normal)"
```
*`build_files/40-spec-scripts/scripts/validate-staged-deployment` (lines 80-83, 237-241)*

Because a staged deployment is inert until reboot, it can be audited *from the running system*: that same validator locates the checkout under `/ostree/deploy/*/deploy/<hash>.*` and inspects its os-release identity, initramfs contents, kernel signature, and bootloader wiring, every defect that would otherwise greet you in a dracut emergency shell is caught while you still have a working terminal to debug from.

The deployment a machine is running is fully described by `bootc status --json`. Margine uses this to tell the user what their reboot actually did:

```python
r = subprocess.run(["bootc", "status", "--json"], capture_output=True, text=True, timeout=15)
if r.returncode != 0:
    sys.exit(0)
booted = json.loads(r.stdout)["status"]["booted"]
digest  = booted["image"].get("imageDigest", "?")
version = booted["image"].get("version", "?")
```
*`/var/home/daniel/dev/margine-image/build_files/system_files/usr/libexec/margine-upgrade-notify`*

The booted OS is identified by an OCI **digest**, the same identifier CI signed and smoke-booted. That one-to-one mapping between "what runs on the laptop" and "what passed the pipeline" is the core operational win of the model.

Rollback is the user-side safety net; Margine adds a distro-side one: builds publish to `:candidate`, and only a QEMU boot that reaches multi-user gets promoted to `:stable` via `skopeo copy --preserve-digests` (details in the CI chapter). Per the 2026-06-01 lessons-learned: *"`:stable` no longer means 'the last build that compiled'; it means 'the last build that booted to a usable state inside QEMU'"*.

## 1.4 The three-zone filesystem contract

The whole model rests on a strict split of the filesystem, documented in Margine's architecture doc:

| Path | Role |
| --- | --- |
| `/` | deployment root |
| `/usr` | operating system content, read-only in normal operation |
| `/etc` | writable host configuration with ostree merge behavior |
| `/var` | writable persistent local state |
| `/home` | symlink to `/var/home` |
| `/opt` | symlink to `/var/opt` |
| `/usr/local` | symlink to `/var/usrlocal` |

*(table from `docs/spec/01-architecture.md`)*

### /usr — image-owned, read-only

Everything the distro ships lives in `/usr` and is immutable at runtime. The build-time corollary: *all* customization in this handbook, systemd units, GNOME extensions, branding, tuned profiles, is written into `/usr` during the container build, never at runtime on the machine.

> **Lesson, legacy units assume a remountable root (Bug 8)**
> **Symptom:** every boot, on Margine *and* stock Bluefin DX, `systemctl --failed` shows `systemd-remount-fs.service` failed: `mount: /: fsconfig() failed: overlay: No changes allowed in reconfigure.`
> **Root cause:** the unit is a pre-atomic relic, remount `/` rw per fstab after fsck. On a composefs root, `/` is an overlay the kernel refuses to reconfigure, and it is already rw via the upper layer; the unit is useless noise here.
> **Fix:** mask it at build time so a clean boot has *zero* failed units, turning any future `systemctl --failed` output into a real signal:
>
> ```bash
> ln -sf /dev/null /etc/systemd/system/systemd-remount-fs.service
> ```
> *`docs/spec/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md` (Bug 8; applied in `build_files/60-ujust-services/install.sh`)*

### /etc — the 3-way merge

`/etc` is writable, but it is not simply "persisted". Each image ships a factory copy at `/usr/etc`. On every deployment, ostree computes the new `/etc` as a **3-way merge**:

- new factory defaults (`/usr/etc` of the new image), plus
- the local diff (current `/etc` minus the *previous* image's `/usr/etc`).

Files the admin never touched track new image defaults; files the admin modified keep the local version (file granularity, no intra-file merging). `ostree admin config-diff` lists the local delta. Design consequence for image builders: defaults you want to be upgradeable belong in `/usr` (e.g. `/usr/lib/systemd/system`, dconf db under `/etc/dconf/db` compiled from `/usr`-shipped keyfiles), and `/etc` content baked into the image should be minimal, because it becomes "factory" state subject to merge semantics.

> **Lesson, /etc/passwd vanished after rebase (Bug 6)**
> **Symptom:** CI validation confirmed 65 entries in the image's `/etc/passwd`; a fresh VM rebased to the image had 1. System users (gdm, polkitd, ...) gone, services failing.
> **Root cause:** the rechunk step (§1.5) re-commits the image into ostree-canonical form and strips `/etc/passwd`/`/etc/group` from `/usr/etc`, so the factory side of the 3-way merge has nothing to merge.
> **Fix:** a boot-time idempotent seed from the `/usr/lib` factory copies, shipped as a `sysinit.target` oneshot:
>
> ```bash
> # Workaround: ship a systemd oneshot that re-applies the seed at
> # every boot, before sysinit. Idempotent (only seeds if /etc/passwd
> # is below the entry threshold). Doesn't depend on rechunk preserving
> # /etc, it doesn't need to.
> ```
> *`/var/home/daniel/dev/margine-image/build_files/system_files/usr/lib/systemd/system/margine-seed-etc-passwd.service`; merge logic in `/usr/libexec/margine-seed-etc-passwd`*

> **Lesson, early-boot unit ordering deadlocked the boot (incident 2026-06-01)**
> **Symptom:** fresh VM stalled into `emergency.target`; journal showed `local-fs-pre.target: Found ordering cycle` and every `/dev/disk/by-uuid/*` device timing out.
> **Root cause:** the passwd-seed unit declared `After=local-fs.target` *and* `Before=systemd-sysusers.service`. `local-fs.target` transitively depends on `systemd-tmpfiles-setup-dev.service`, which sits in the same chain, a closed loop. systemd broke the cycle by disabling `tmpfiles-setup-dev`, so `/dev/disk/by-uuid` symlinks never appeared.
> **Fix:** in an ostree system `/etc` and `/usr` are part of the deployment and exist before any local-fs unit, `local-fs-pre.target` is sufficient:
>
> ```diff
>  DefaultDependencies=no
> -Before=sysinit.target systemd-sysusers.service systemd-tmpfiles-setup.service
> -After=local-fs.target
> +Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
> +After=local-fs-pre.target
> ```
> *`docs/spec/lessons-learned/2026-06-01-systemd-ordering-cycle-and-rechunk-storage.md`*
>
> Follow-up hardening: CI now runs `SYSTEMD_OFFLINE=1 systemd-analyze verify default.target` inside every image before push, this bug class is statically detectable.

### /var — machine-local, never shipped

`/var` belongs to the machine, not the image. ostree/bootc populate it once (from `systemd-tmpfiles` factories) and never touch it again, and conversely, anything an installer environment puts in *its own* `/var` does not survive into the deployed system. Margine hits this head-on with its preinstalled Flatpaks (which live in `/var/lib/flatpak`):

```text
# This kickstart's only job is to rsync the populated
# /var/lib/flatpak from the installer rootfs to the target's
# /var/lib/flatpak. ostree+bootc reset /var per-deployment when
# they install, so without this rsync the Flatpaks would be lost
# at first reboot.
...
rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak "$DEPLOY_DIR/var/lib/"
```
*`/var/home/daniel/dev/margine-image/live-env/src/anaconda/post-scripts/install-flatpaks.ks`*

Rule of thumb when designing a feature: if it must survive updates and differ per machine → `/var`; if it is host configuration → `/etc`; everything else → `/usr` at build time.

## 1.5 bootc: the OCI image as the OS transport

Classic rpm-ostree distros (Silverblue circa Fedora 33) pulled commits from a dedicated **ostree remote**, distro-hosted infrastructure speaking the ostree wire format, with static deltas generated server-side. **bootc** replaces the transport: the ostree commit is encapsulated in a standard OCI container image, pushed to any container registry, and the client (`bootc upgrade` / `bootc switch`) pulls it like any container. Internally it is still ostree, layers unpack into the same object store, deployments work identically, but the distribution problem is outsourced to registries.

This makes "building a distro" literally a container build. Margine's entire image is a four-`RUN` Containerfile ending with a structural lint:

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# ----- Lint: verify final image is a valid bootc container -----
RUN bootc container lint
```
*`/var/home/daniel/dev/margine-image/Containerfile` (lines 49-53 trimmed, 69-70)*

`bootc container lint` fails the build if the image violates bootc invariants (content in `/var`, missing kernel layout, bad `/usr` structure), the cheapest possible guardrail, run before any artifact leaves the builder.

Switching a machine onto (or between) images is one command. Margine's installer wires the freshly installed system to the registry so future `bootc upgrade` calls track the published tag:

```bash
%post --erroronfail
# Point the freshly installed system at our public registry so
# subsequent `bootc upgrade` calls follow margine:stable.
bootc switch --mutate-in-place --transport registry ghcr.io/daniel-g-carrasco/margine:stable
%end
```
*`/var/home/daniel/dev/margine-image/live-env/src/anaconda/post-scripts/bootc-switch.ks`*

And the documented adoption path for an existing Fedora Atomic / Bluefin machine, from the Containerfile header:

```text
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
```
*`/var/home/daniel/dev/margine-image/Containerfile` (line 17)*

`rpm-ostree rebase` and `bootc switch` are two clients of the same mechanism: repoint the origin, stage a deployment, reboot. The `ostree-image-signed:` prefix enforces signature policy from `/etc/containers/policy.json` (signing chapter).

### Rechunking: making OCI layers behave like ostree deltas

Naive Containerfile layering is hostile to updates: any change in an early `RUN` invalidates every later layer, so users re-download gigabytes for a one-package bump. Margine repacks the final image with `hhd-dev/rechunk`, which splits content into stable, content-defined chunks (kernel, big packages, shared data each in their own layer) so unchanged chunks dedupe across releases:

```yaml
      - name: ReChunk image
        id: rechunk
        uses: hhd-dev/rechunk@5fbe1d3a639615d2548d83bc888360de6267b1a2  # v1.2.4
        with:
          ref: ${{ env.IMAGE_NAME }}:${{ steps.metadata.outputs.version }}
          version: ${{ env.CANDIDATE_TAG }}.${{ steps.date.outputs.ymd }}
          labels: |
            ...
            containers.bootc=1
          revision: ${{ github.sha }}
```
*`/var/home/daniel/dev/margine-image/.github/workflows/build.yml` (lines 448-464, trimmed)*

Practical effect: day-to-day `bootc upgrade` downloads shrink from "most of the image" to "the layers that actually changed", approximating ostree static deltas on plain registry infrastructure.

> **Lesson, os-release symlink vs composefs timing (Fix A wind-down)**
> **Symptom:** early Margine builds failed boot with `os-release file is missing`, `/etc/os-release → ../usr/lib/os-release` could not resolve because composefs was not fully assembled when switch-root read it; the image's commit metadata was also inherited from Bluefin rather than regenerated.
> **Root cause:** a buildah-produced image is not in ostree-canonical form; ordering assumptions that hold on Fedora/Bluefin images broke.
> **Fix (initial):** write `os-release` as a regular file ("Fix A"). **Fix (final):** rechunk re-commits the image into ostree-canonical state, composefs is fully set up before switch-root, and the canonical symlink was restored, deleting workaround surface instead of accumulating it.
> *`docs/spec/lessons-learned/2026-06-03-rechunk-and-fixb.md`*

### Where this is heading: sealed images

ADR 0007 tracks the next step of the model: **Sealed Bootable Container Images** (systemd-boot + UKI + composefs with fs-verity, every `/usr` page-read verified against a vendor-signed Merkle root). It changes the signing story substantially, UKI signing replaces per-module `sign-file`, the MOK enrollment dance disappears, GRUB goes away, and Margine deliberately waits for upstream (trigger: Bluefin/Bazzite shipping sealed `:stable`). See `docs/spec/adr/0007-sealed-bootable-images-tracker.md`.

## 1.6 Comparing the atomic models

### rpm-ostree-native vs bootc

| | rpm-ostree-native (ostree remote) | bootc (OCI) |
| --- | --- | --- |
| Transport | distro-hosted ostree repo + static deltas | any OCI registry |
| Build tooling | rpm-ostree compose (treefile), distro infra | Containerfile + buildah/podman, any CI |
| Signing | GPG on commits | sigstore/cosign on image digests |
| Derivation | hard (re-compose) | trivial (`FROM` + `RUN`) |
| Client-side package layering | yes (`rpm-ostree install`) | discouraged; bake into image instead |
| Hosting cost | you run the repo | GitHub/quay run the registry |

Fedora Atomic today is a hybrid: bootc transport, rpm-ostree still present for layering. Margine's stance (ADR 0005, `docs/01-architecture.md`): no runtime layering as policy, "repeated host helpers should later move into a native image or bootc build", because every layered package re-applies on each upgrade and reintroduces per-machine drift.

### The other atomic architectures

- **ABRoot (Vanilla OS 2)**, two root partitions; transactions are applied from an OCI image to the inactive root, bootloader flips on reboot. OCI-based like bootc but partition-granular: 2× root disk cost, no content dedup between roots, simpler mental model.
- **transactional-update + btrfs/snapper (openSUSE MicroOS/Aeon/Kalpa)**, `zypper` runs inside a new btrfs snapshot which becomes the default subvolume on reboot; rollback = boot an older snapshot. Atomic *updates* but not image-*based*: each machine still runs a package manager, so fleets drift; there is no single testable artifact. Contrast with Margine's explicit stance: "System rollback comes from ostree/rpm-ostree deployments, not from a custom Btrfs snapshot scheme" (`docs/01-architecture.md`).
- **NixOS generations**, declarative config evaluated into immutable `/nix/store` closures; every rebuild is a bootloader generation, rollback is free. The most expressive model, and the system *is* its config, at the cost of an entirely parallel packaging ecosystem (no FHS, patchelf/wrappers for foreign binaries) and a steep language. ostree tracks *trees*; Nix tracks *build graphs*.
- **A/B partition slots (ChromeOS, Android, SteamOS 3, Flatcar)**, full image written to the inactive slot, bootloader flips, failed boots auto-revert (boot counters). Maximally robust and verifiable (dm-verity per slot), but 2× space, fixed OS size, and OS customization is essentially unsupported, SteamOS makes `/` writable only via a "developer mode" that updates then wipe.
- **frzr (ChimeraOS)**, image tarballs deployed into btrfs subvolumes, bootloader points at the active one. A/B semantics with snapshot-level dedup; niche tooling.

## 1.7 Why Universal Blue (and Margine) picked OCI

uBlue's bet, inherited wholesale by everything `FROM ghcr.io/ublue-os/*`, comes down to using infrastructure that already exists at planet scale:

1. **Registry infrastructure is free and ubiquitous.** GHCR/quay host the artifacts, handle bandwidth, auth, and tag immutability. An ostree remote with static deltas is bespoke infrastructure a hobby distro cannot realistically operate; Margine ships from a personal GitHub account.
2. **Layer dedup ≈ delta updates.** OCI layers (especially after rechunking, §1.5) give incremental downloads without server-side delta generation. Bonus: `FROM bluefin-dx` means Margine users share base layers with every other uBlue derivative on their disk and on the registry.
3. **The signing ecosystem already exists.** cosign signs by digest, `policy.json` enforces at pull, SBOMs attach as OCI referrers. Margine's pipeline (build → syft SBOM → rechunk → push → cosign sign-by-digest) is standard container supply-chain tooling, not distro-specific machinery (CI chapter).
4. **The toolchain is the container toolchain.** Containerfiles, buildah, BuildKit secrets (Margine's MOK keys enter the build as `--mount=type=secret` and never persist in a layer, see the Containerfile lines 39-46), GitHub Actions, skopeo, `podman run` for inspection. Every contributor who has built a container can derive a distro. This is the whole "custom image" community model: Bazzite, Bluefin, Aurora, and hundreds of personal images are Containerfiles in public repos.

The trade-off accepted: OCI was not designed to carry bootable filesystems, hence rechunk, `bootc container lint`, and the canonical-form lessons of §1.5. The friction is real but front-loaded onto the image builder; the user-facing mechanics (staged deployments, 3-way merge, rollback) remain pure ostree.

## Alternatives & other distros

| Approach | Used by | One-line trade-off |
| --- | --- | --- |
| bootc / OCI image on ostree | Margine, Bluefin, Bazzite, Aurora, uCore | registry-native, derivable via `FROM`, cosign signing; needs rechunk for delta-efficient updates |
| rpm-ostree-native (ostree remote) | Fedora Silverblue/Kinoite (classic path), Endless OS, Fedora CoreOS | proven deltas + GPG, but distro-hosted infra and hard derivation |
| ABRoot (OCI → A/B root partitions) | Vanilla OS 2 | atomic + OCI-sourced, partition granularity: 2× root space, no object-store dedup |
| transactional-update + btrfs/snapper | openSUSE MicroOS, Aeon, Kalpa | atomic updates with a real package manager kept; per-machine drift, no single testable artifact |
| Nix generations | NixOS | fully declarative system-as-config, free rollback; parallel ecosystem, steep learning curve |
| A/B slots + dm-verity | ChromeOS, Android, SteamOS 3, Flatcar | auto-revert on boot failure, strongest integrity; 2× space, OS effectively closed to customization |
| btrfs deployment images (frzr) | ChimeraOS | simple A/B-on-btrfs with dedup; small ecosystem, image-tarball transport |
| systemd-sysupdate + UKI partition images | GNOME OS, ParticleOS | systemd-native A/B with measured boot; young tooling, no derivation story comparable to `FROM` |
| swupd manifest/bundle deltas | Clear Linux (discontinued 2025) | fine-grained per-file deltas without reboot atomicity; bespoke infra died with the distro |
| Sealed bootable containers (UKI + composefs/fs-verity) | Fedora/bootc test images, future Bluefin — tracked in Margine ADR 0007 | fully verified boot chain and sane TPM2 defaults; immature, breaks current MOK/GRUB pipelines |

Margine sits in row one deliberately: it inherits Bluefin DX's maintenance (codecs, Mesa, virt stack, ADR 0005's "stop hand-rolling 70% of Bluefin") and spends its own effort only on the deltas the next chapters cover: a signed CachyOS kernel, GNOME defaults, branding, an installer, and a CI gate that refuses to ship an image that didn't boot.


---

# 2. Anatomy of the image repo

A bootc distro is, at its core, one git repo that produces one OCI image. For Margine that repo is `margine-image`. This chapter walks its layout, the Containerfile, the staged build scripts, and the build-time write rules that bootc/ostree impose.

## 2.1 Lineage: ublue-os/image-template

Margine descends from the Universal Blue **image-template** pattern (`github.com/ublue-os/image-template`), the same skeleton behind Bluefin, Bazzite and Aurora customizations. The contract is minimal:

- a `Containerfile` whose `FROM` is an existing bootc base image;
- a `build_files/` directory holding everything needed *during* the build but not wanted *inside* the final image;
- a single `RUN` invocation (or a few) that bind-mounts `build_files/` and runs a `build.sh`;
- a final lint that proves the result is still a valid bootc container;
- CI that builds, signs and pushes to a registry on every commit.

Margine credits this explicitly (`/var/home/daniel/dev/margine-image/README.md`):

```text
- Bluefin — base image and source of most of what Margine ships.
- Universal Blue — image-template, CI patterns, `uupd`.
- Origami Linux — reference for the MOK-signing kernel script.
- hhd-dev/rechunk — ostree rechunking action.
```

Repo top level:

```text
margine-image/
├── Containerfile            # the whole OS definition
├── build_files/             # build-time scripts + system_files overlay
├── installer/               # Anaconda installer-image context (Flatpak BAKE)
├── disk_config/             # bootc-image-builder TOML (qcow2, anaconda-iso)
├── live-env/                # Titanoboa live-ISO layer
├── docs/                    # repo-local postmortems and plans
└── .github/workflows/       # build, disk, smoke-boot, ISO publish
```

`installer/`, `disk_config/` and `live-env/` are consumed by later chapters; everything that defines the *booted OS* lives in `Containerfile` + `build_files/`.

## 2.2 The Containerfile, stage by stage

### The `ctx` scratch stage: build inputs that never ship

```dockerfile
# /var/home/daniel/dev/margine-image/Containerfile
# ----- Build context: scripts that should NOT end up in the final image -----
FROM scratch AS ctx
COPY build_files /
# Make installer/flatpaks-base reachable from build.sh at
# /ctx/installer-flatpaks-base. Single source of truth for the BAKE
# Flatpak list (audit §3.5: drop the duplicate here-doc in build.sh).
COPY installer/flatpaks-base    /installer-flatpaks-base
```

Practical effect: scripts live in a throwaway `scratch` stage and reach the real build only through an ephemeral `--mount=type=bind`. Nothing in `build_files/` can leak into a shipped layer, and editing a script does not invalidate the base layer cache. The extra `COPY installer/flatpaks-base` makes one file the single source of truth for both the OCI image and the Anaconda installer (chapter on ISOs).

### `FROM bluefin-dx` and pinning

```dockerfile
# /var/home/daniel/dev/margine-image/Containerfile
# ----- Base: Bluefin DX (Fedora 44 track, "stable" tag) -----
FROM ghcr.io/ublue-os/bluefin-dx:stable
```

Margine pins to the floating `:stable` tag, not a digest. Trade-off: every weekly rebuild silently absorbs whatever Bluefin shipped (good: free maintenance of GNOME, drivers, dev tooling; bad: an upstream regression lands without a diff to review). The mitigations are downstream: a CI asset validator and a QEMU smoke-boot gate must pass before anything is promoted to Margine's own `:stable` (chapter on CI). The stricter alternative (digest pinning with Renovate/Dependabot bump PRs) is what several uBlue community images do; it buys reviewability at the cost of merge churn.

### `RUN --mount` anatomy

Each build stage uses the same mount set:

```dockerfile
# /var/home/daniel/dev/margine-image/Containerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok-key,target=/tmp/certs/MOK.key \
    --mount=type=secret,id=mok-cert,target=/tmp/certs/MOK.pem \
    /ctx/custom-kernel/install.sh
```

- `type=bind,from=ctx`: scripts visible at `/ctx`, gone after the `RUN`.
- `type=cache` on `/var/cache` and `/var/log`: dnf metadata and logs persist *across builds* but never enter a layer. This doubles as a guard: anything written there cannot ship, which is exactly what ostree wants for `/var` (see §2.5).
- `type=tmpfs` on `/tmp`: scratch space, guaranteed empty in the image.
- `type=secret`: the MOK private key, certificate and enrollment password exist only for the duration of this one `RUN`. No `COPY` of key material, no credentials in layer history.

### The four RUN stages

1. **`/ctx/custom-kernel/install.sh`**: swap the Fedora kernel for CachyOS from COPR, sign vmlinuz + every module with the MOK secrets, rebuild the initramfs (chapter 3).
2. **`/ctx/build.sh`**: the orchestrator over all numbered `NN-*/install.sh` stages (§2.3).
3. **`/ctx/build-margine-extensions.sh`**: bake GNOME Shell extensions system-wide into `/usr/share/gnome-shell/extensions/`. The Containerfile comment records why this is a separate stage: it replaces a racy per-user first-login installer, copying the Bluefin/Bazzite practice of build-time system-wide extensions.
4. **`bootc container lint`**: final validation (§2.6).

Stage granularity matters for iteration speed: a change to a GNOME default re-runs stages 2-4 but reuses the cached (expensive, COPR-fetching, module-signing) kernel layer.

## 2.3 The build orchestrator and numbered stages

`build.sh` is deliberately boring: a 1416-line monolith was decomposed into per-area scripts (documented in `/var/home/daniel/dev/margine-image/docs/build-sh-decomposition.md`):

```bash
# /var/home/daniel/dev/margine-image/build_files/build.sh
set -euo pipefail
. /ctx/00-common.sh

log "==== Margine build orchestrator: starting ===="

# Run every sub-script in lexicographic order. Globs expand
# deterministically because we name dirs <NN>-<area>.
for d in /ctx/[1-9][0-9]-*/install.sh; do
  log "==> running $d"
  bash "$d"
done
```

Practical effect: adding a build concern = adding a directory. Ordering is encoded in the name, the glob is deterministic, and `set -euo pipefail` plus `bash "$d"` (not `source`) means one failing stage kills the build without leaking state into the next.

Shared state lives in one sourced file:

```bash
# /var/home/daniel/dev/margine-image/build_files/00-common.sh
log() { printf '[margine-build] %s\n' "$*"; }
# retry_curl <url> <out>        — 5 attempts, 30-150s backoff (COPR/raw.githubusercontent brownouts)
# retry_curl_strict <url> <out> — same, but aborts the build on missing/empty asset

export FEDORA_VER="${FEDORA_VER:-$(rpm -E %fedora 2>/dev/null || echo 44)}"
export BUILD_DATE="${BUILD_DATE:-$(date -u +%Y%m%d)}"
```

`retry_curl_strict` exists because a silently-failed asset download shipped user-visible regressions twice (missing welcome logo, missing About-panel logo); for assets the image is broken without, fail-loud beats a quiet placeholder.

The stages:

| Dir | Concern |
|---|---|
| `10-os-identity/` | `os-release` rewrite, `/etc/passwd`+`/etc/group` factory seed, `build_files/system_files/` overlay copy |
| `20-flatpaks/` | BAKE list → `/usr/share/margine/`, DEFER list → `/usr/share/flatpak/preinstall.d/` |
| `30-gnome-defaults/` | `zz1-margine.gschema.override` (10 enabled extensions, favorites, accent), dconf keyfiles in `/etc/dconf/db/distro.d/` |
| `40-spec-scripts/` | install the vendored `configure-*`/`validate-*` helpers + `declarations.yaml` to `/usr/bin` |
| `45-wsf/` | build `wayland-scroll-factor`, install `LD_PRELOAD` drop-in for `org.gnome.Shell@.service` |
| `50-branding/` | logo, wallpaper, Plymouth theme, offline docs, GDM background, strip Bluefin branding |
| `60-ujust-services/` | `60-custom.just` recipes, mask `systemd-remount-fs`, skel defaults |

The boot-time passwd re-seed unit, staleness/upgrade notifiers, and first-boot autostarts no longer have a build stage of their own: their payloads ship as tracked files under `build_files/system_files/` (libexec scripts + systemd units), copied wholesale into the rootfs by stage `10-os-identity`, the system_files overlay this chapter already describes.

One detail in `60-ujust-services` generalizes to any Bluefin derivative: the recipe file **must** be named `60-custom.just`.

```bash
# /var/home/daniel/dev/margine-image/build_files/60-ujust-services/install.sh
# Bluefin's /usr/share/ublue-os/just/00-entry.just hardcodes the list
# of imported recipe files. The ONLY one declared as optional is
# 60-custom.just (via `import?`) — that's the documented extension
# point for downstream distros. Files dropped under any other name
# (e.g. 99-margine.just) are simply ignored by `ujust --list`.
install -Dm0644 /ctx/60-custom.just /usr/share/ublue-os/just/60-custom.just
```

## 2.4 The `build_files/system_files/` overlay

Static files (units, libexec scripts, tuned profiles, icons, autostart entries) do not get heredoc'd in scripts; they live under `build_files/system_files/` in a tree that mirrors their final path, and stage 10 overlays the whole thing onto `/`:

```bash
# /var/home/daniel/dev/margine-image/build_files/10-os-identity/install.sh
# The whole tree gets rsync'd into the rootfs at "/" so file paths in
# the repo mirror their final installed location. Same pattern as
# Bluefin's system_files/shared/.
if [[ -d /ctx/system_files ]]; then
  log "Copying /ctx/system_files/ → / (overlaying base rootfs)"
  cp -a /ctx/system_files/. /
  # Set executable bit on libexec scripts (cp -a preserves mode but
  # git may have flagged them differently across platforms).
  find /usr/libexec /usr/bin -type f \( \
      -path '*/margine-*' -o \
      -path '/usr/libexec/margine/*' \
    \) -exec chmod 0755 {} \;
fi
```

Practical effect: `git log build_files/system_files/usr/lib/systemd/system/margine-docs-refresh.service` is the change history of that exact file on disk. The current tree ships almost exclusively into `/usr` (units in `/usr/lib/systemd/system/`, scripts in `/usr/libexec/margine/`, tuned profiles in `/usr/lib/tuned/profiles/`), plus one `/etc/xdg/autostart` entry, consistent with the write rules below.

Stage 10 also rewrites OS identity. The non-obvious part is which fields a derivative may change:

```bash
# /var/home/daniel/dev/margine-image/build_files/10-os-identity/install.sh
NAME="Margine"
ID=fedora            # bootc-image-builder fails "could not find def file for
ID_LIKE=bluefin      # distro margine-44" if ID=margine; BIB does NOT fall
VARIANT_ID=margine   # back to ID_LIKE. Discriminate on VARIANT_ID instead.
...
printf '%s\n' "$OS_RELEASE_CONTENT" > /usr/lib/os-release
ln -sf ../usr/lib/os-release /etc/os-release   # canonical Fedora layout
```

`NAME`/`PRETTY_NAME`/`VARIANT*` are the branding surface; `ID` is an ecosystem contract (tooling does exact `ID-VERSION_ID` lookups). Fedora's own spins (Silverblue, Kinoite) follow the identical `ID=fedora` + distinct `VARIANT_ID` pattern.

> **Lesson: os-release symlink vs switch-root.**
> *Symptom:* first VM boots failed with `Failed to switch root: ... os-release file is missing`, despite the file existing in the deployment.
> *Root cause:* two stacked issues. The initramfs lacked the `ostree` dracut module (so `/sysroot` was never pivoted to the deployment view), and the image pushed by plain buildah was not ostree-canonical, so composefs was not mounted over `/usr` when systemd's switch-root check did `openat(fd, "etc/os-release", O_NOFOLLOW)`. The `/etc/os-release → ../usr/lib/os-release` symlink dangled.
> *Fix:* short-term, ship `os-release` as a regular file in both places ("Fix A"); proper fix ("Fix B"), add `dracut --add ostree` in the kernel stage and wire `hhd-dev/rechunk` into CI so the published image is re-committed in ostree-canonical form, after which the canonical symlink was restored (the `ln -sf` above). Full writeups: `docs/spec/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md` and `.../2026-06-03-rechunk-and-fixb.md`.

## 2.5 What may write where at build time

The rule set every script in this repo obeys:

- **`/usr`: yes.** The immutable payload. Binaries, units, schemas, extensions, kernels (`/usr/lib/modules/<kver>/vmlinuz` + `initramfs.img`), even the passwd factory (`/usr/lib/passwd`).
- **`/etc`: yes, but it becomes the *factory*.** At commit/rechunk time `/etc` content is captured as `/usr/etc`; on each deployment ostree 3-way-merges it with the machine's live `/etc`. Writes here are defaults, not state.
- **`/var`: no.** `/var` is machine-local and reset/merged per deployment; content baked into it is dead weight at best and a lint error at worst. The Containerfile makes this structural: `/var/cache` and `/var/log` are cache mounts, so dnf can do its job without the result ever entering a layer.
- **`/tmp`: tmpfs mount,** guaranteed not to ship.
- **`/opt`, `/usr/local`**: symlinks into `/var` on Fedora/ostree; same prohibition applies.

Some tooling assumes a writable, persistent `/var` and has to be tricked. akmods is the canonical offender:

```bash
# /var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh
# akmodsbuild on bootc images skips signing if /var isn't writable; patch
# it out so akmods proceeds inside the container build.
disable_akmodsbuild() {
  _ak="/usr/sbin/akmodsbuild"
  cp -p "$_ak" "$_ak.backup"
  sed '/if \[\[ -w \/var \]\] ; then/,/fi/d' "$_ak" > "$_ak.tmp"
  mv "$_ak.tmp" "$_ak"
  chmod +x "$_ak"
}
```

The patch is reverted (`restore_akmodsbuild`) before the layer is committed: temporary mutations of `/usr` must be cleaned up by the same script that made them.

A second class of "build-time write" bug: transient dnf installs. The extensions stage refuses them entirely after an `autoremove`/`Requires:`-cascade incident:

```bash
# /var/home/daniel/dev/margine-image/build_files/build-margine-extensions.sh
# NO transient dnf installs. Lesson learned the hard way 2026-06-04:
#   dnf5 -y remove jq    # STILL broke things: scx-tools-git declares
#                        # Requires: jq → removal cascades through
#                        # scx-tools-git → scx-scheds → 16 packages.
# Robust fix: don't add or remove dnf packages here at all. Use
# Python stdlib (always present) for JSON parsing + zip extraction.
```

> **Lesson: rechunk strips the `/etc` factory.**
> *Symptom:* after rebasing a Bluefin machine to Margine, boot spews dozens of `Failed to resolve group 'audio'/'kvm'/'tty'`; TPM unlock and audio break.
> *Root cause:* Bluefin ships a near-empty `/etc/passwd` (sysusers populates it at boot). The build-time seed (stage 10) fills it, and CI confirmed 65 entries post-build, but rechunk's re-commit stripped `/etc/passwd`/`/etc/group` from the `/usr/etc` factory, so ostree's 3-way merge on the rebased machine kept only `root` plus the human user.
> *Fix:* belt and suspenders: keep the build-time seed *and* ship an idempotent boot-time oneshot that re-merges from `/usr/lib/{passwd,group}` whenever `/etc/passwd` drops below 20 entries:
> ```ini
> # build_files/system_files/usr/lib/systemd/system/margine-seed-etc-passwd.service
> [Unit]
> DefaultDependencies=no
> # DO NOT add After=local-fs.target: it creates an ordering cycle through
> # systemd-tmpfiles-setup-dev.service → /dev/disk/by-uuid never populated
> # → boot times out into emergency mode (incident 2026-06-01).
> After=local-fs-pre.target
> Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
> ```
> The comment is its own sub-lesson: the first version of this unit ordered itself `After=local-fs.target` and systemd resolved the resulting dependency cycle by disabling `systemd-tmpfiles-setup-dev`, pushing every boot into `emergency.target` (`.../lessons-learned/2026-06-01-systemd-ordering-cycle-and-rechunk-storage.md`).

## 2.6 Commit and lint

The image must end as something bootc can deploy. Margine's Containerfile finishes with:

```dockerfile
# /var/home/daniel/dev/margine-image/Containerfile
# ----- Lint: verify final image is a valid bootc container -----
RUN bootc container lint
```

`bootc container lint` checks the invariants this chapter described: no content baked into `/var`, valid kernel/initramfs layout under `/usr/lib/modules/`, sane `/etc` and composefs-compatible structure. It fails the build, so a violating commit never reaches the registry.

Two related mechanisms in the same family:

- **`ostree container commit`**: the older uBlue/image-template idiom, appended to each `RUN` to clean `/var` and verify the layer (`RUN /ctx/build.sh && ostree container commit`). bootc-era templates replace it with the final `bootc container lint`; Margine never carried the old form.
- **rechunk** (`hhd-dev/rechunk`, in CI, post-build): re-commits the OCI image as an ostree-canonical tree with size-balanced layers. For Margine it is not just a bandwidth optimization: it is what made composefs come up early enough for the os-release symlink (Lesson above). The trade-off (it rewrites `/usr/etc` aggressively) produced the passwd-stripping Lesson.

## Alternatives & other distros

**Repo/build skeleton**
- **ublue-os/image-template** (Bluefin/Bazzite/Aurora customs, Margine): Containerfile + `build_files/` + GitHub Actions; lowest-friction entry.
- **BlueBuild**: declarative `recipe.yml` compiled to a Containerfile; less bash, less control over stage ordering.
- **Fedora rpm-ostree treefiles** (Silverblue/Kinoite proper): YAML/JSON compose on Fedora infra; not container-native, no `RUN` step.
- **NixOS**: full system from a Nix expression; maximal reproducibility, entirely different ecosystem, no OCI base reuse.
- **Vanilla OS (Vib + ABRoot)**: modular YAML recipe → OCI image, A/B partition deployment instead of ostree.
- **openSUSE MicroOS/Aeon**: built with KIWI on OBS; btrfs-snapshot atomicity (`transactional-update`), not image-based delivery.

**Base pinning**
- Floating tag (`bluefin-dx:stable`, Margine, most uBlue customs): zero maintenance, regressions absorbed silently; compensate with CI gates.
- Digest pin + Renovate bumps: reviewable upstream diffs, constant PR churn.
- Build-from-source base (Bazzite, Bluefin themselves build from `ublue-os/main`/Fedora base): full control, full maintenance burden.

**Script staging**
- Numbered `NN-*/install.sh` dirs (Margine) ≈ Bluefin's `build_files/shared/*.sh`: deterministic, diff-friendly.
- Single `build.sh` (stock image-template): fine until ~300 lines.
- One `RUN` per concern in the Containerfile (Bazzite, dozens of layers): better layer caching per concern, registry layer-count bloat, exactly why rechunk exists.

**Config overlay**
- `build_files/system_files/` mirror-tree copied to `/` (Margine, Bluefin, Bazzite): file paths == repo paths.
- Heredocs in scripts (Margine uses these for *generated* files only): content next to logic, but unreviewable past a screenful.
- Nix modules / Vib modules: typed config instead of file trees; ecosystem lock-in.

**Validation**
- `bootc container lint` (Margine, current uBlue): in-build, blocking.
- `ostree container commit` (legacy uBlue): per-layer cleanup + check.
- External smoke boot in QEMU before tag promotion (Margine's `smoke-boot.yml`, Bazzite's CI): catches what static lint cannot: the passwd and switch-root Lessons above were both runtime-only failures.


---

# 3. Replacing the kernel in an atomic image

The kernel is just files in the image: `/usr/lib/modules/<kver>/vmlinuz`, the module tree next to it, and an `initramfs.img` in the same directory. In a bootc image build you can remove the stock kernel and install another one with plain `dnf` inside the Containerfile: no bootloader scripting, no per-machine `kernel-install` dance. What makes it hard is everything around the files: the kernel-install hooks that assume a running system, out-of-tree modules that must be built against the *new* headers, an initramfs that must be regenerated for hardware the build container cannot see, and a handful of ostree-specific invariants (output path, dracut `ostree` module, the `ostree.linux` OCI label) that fail only at first boot.

Margine replaces Bluefin DX's stock kernel with `kernel-cachyos` from the `bieszczaders/kernel-cachyos` COPR. The whole swap lives in one script, invoked as the first RUN stage so every later stage (Plymouth, extensions) already sees the final kernel:

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok-key,target=/tmp/certs/MOK.key \
    --mount=type=secret,id=mok-cert,target=/tmp/certs/MOK.pem \
    /ctx/custom-kernel/install.sh
```
*`/var/home/daniel/dev/margine-image/Containerfile` (lines 39-46)*

The BuildKit `type=secret` mounts stage the MOK signing material as ephemeral files: they exist during this RUN only and never land in a layer. Signing itself (sbsign on vmlinuz, `sign-file` on every `.ko`, the first-boot `mok-enroll.service`) is the Secure Boot chapter's subject; this chapter covers the swap, the module builds, and the initramfs.

## 3.1 Why a custom kernel at all

The decision is written down in ADR 0006 (`docs/spec/adr/0006-kernel-cachyos-decision.md`). Three options were on the table for a Fedora-Atomic-derived desktop in 2026:

| | A — `kernel-cachyos` (chosen) | B — OGC kernel (Bazzite et al.) | C — Bluefin's stock kernel |
|---|---|---|---|
| BORE scheduler | builtin (`CONFIG_SCHED_BORE=y`) | opt-in upstream, not in default config | no |
| ThinLTO build | yes (~3-5% win) | no | no |
| `CONFIG_HZ` | 1000 | 300 | 300 |
| Handheld HID / NTSYNC / gyro | not the focus | yes, in tree | no |
| Maintainer surface | single Fedora packager | 8-distro shared CI | Bluefin/uBlue team |
| Build pipeline cost | ~420 LOC + MOK secrets in CI | adopt akmods OCI pull | zero — inherit from base |

Margine is creator-first (real-time audio: Reaper, EasyEffects on PipeWire), so BORE + `HZ=1000` + ThinLTO win over OGC's handheld patch set; for a gaming/handheld distro the matrix flips. Option C is the correct answer if you don't have a measured reason to deviate: it deletes this entire chapter from your build. The accepted risk is the single-maintainer COPR, mitigated with a re-review trigger ("no new COPR build for >30 days while kernel releases are in flight") watched by `scripts/check-upstreams.sh`.

The choice is also pinned in the spec, including the fallback story:

```yaml
kernel:
  shipped:
    provider: cachyos-copr
    repo: bieszczaders/kernel-cachyos
    package: kernel-cachyos
    signed_with: margine-mok
    secure_boot_compliant: true
    installed_at: image-build-time
  fallback:
    provider: fedora
    available_via: rpm-ostree rollback (previous deployment)
```
*`/home/daniel/dev/build_files/40-spec-scripts/declarations/margine-atomic.yaml` (lines 197-207)*

Rollback to the previous deployment is the kernel safety net: atomic model means a bad kernel never strands the machine (chapter 1).

## 3.2 The swap, step by step

### 3.2.1 Neutralize kernel-install hooks

Installing a kernel RPM triggers `/usr/lib/kernel/install.d/` hooks. Two of them misbehave in a container: the rpm-ostree hook assumes a live ostree deployment, and the dracut hook would generate a host-only initramfs for the build container (wrong by construction, §3.4). Margine stubs them out for the duration of the swap:

```bash
disable_kernel_install_hooks() {
  for _f in \
      /usr/lib/kernel/install.d/05-rpmostree.install \
      /usr/lib/kernel/install.d/50-dracut.install
  do
    [[ -f "$_f" ]] || continue
    mv "$_f" "$_f.bak"
    printf '#!/bin/sh\nexit 0\n' >"$_f"
    chmod +x "$_f"
  done
}
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 63-73)*

Each hook becomes `exit 0`; `restore_kernel_install_hooks` puts the originals back after the install so the shipped image is unmodified. Practical effect: the kernel RPM lays down files and nothing else: initramfs generation is done explicitly, once, at the end.

### 3.2.2 Remove the stock kernel

```bash
dnf -y remove \
    kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
    kernel-devel kernel-devel-matched || true
rm -rf /usr/lib/modules/* || true
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 174-177)*

The `rm -rf /usr/lib/modules/*` matters: bootc and several build scripts assume **exactly one** kernel under `/usr/lib/modules/` (Margine's live-ISO build asserts this twice). Leftover module dirs from a half-removed stock kernel would produce two boot entries, a doubled initramfs loop, and an ambiguous `ostree.linux` label.

### 3.2.3 Install from COPR — with a retry loop

```bash
dnf -y copr enable "$COPR_REPO"
...
attempt=1
max_attempts=5
while :; do
  if dnf -y install --refresh $KERNEL_PACKAGES akmods; then
    log "CachyOS kernel install OK on attempt $attempt"
    break
  fi
  if (( attempt >= max_attempts )); then
    log "CachyOS kernel install FAILED after $max_attempts attempts (COPR likely down)"
    exit 1
  fi
  backoff=$(( attempt * 30 ))
  sleep $backoff
  dnf -y clean metadata || true
  attempt=$(( attempt + 1 ))
done
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 180, 198-214, trimmed)*

`$KERNEL_PACKAGES` is `kernel-cachyos kernel-cachyos-core kernel-cachyos-modules kernel-cachyos-devel-matched`. Two non-obvious choices:

- **`-devel-matched`, not `-devel`.** The `devel-matched` virtual guarantees headers for *exactly* the installed kernel version. Plain `-devel` can resolve to a newer headers build if the COPR has published one between mirror syncs, and then every out-of-tree module compiles against headers the running kernel doesn't have.
- **The outer retry loop exists because COPR is a free service that browns out.** A real build (run #26838562527, 2026-06-02) died with `Curl error (28): Timeout was reached` after librepo's five internal retries were already exhausted. Linear backoff (30/60/90/120s) plus `dnf clean metadata` per attempt rides out multi-minute COPR 5xx windows instead of sinking a ~28-minute image build.

> **Lesson: persistent build caches poison dnf**
> **Symptom:** two consecutive builds on the self-hosted runner failed identically: `package kernel-cachyos-modules-7.0.8... does not verify: Payload SHA256 ALT digest: BAD`, same expected/actual hashes on retry, so not a flaky download.
> **Root cause:** the Containerfile mounts `--mount=type=cache,dst=/var/cache`. On GitHub-hosted runners that cache is born fresh per job; on the self-hosted runner it persists across builds, so one partial RPM in `/var/cache/libdnf5/` gets re-used by every subsequent `dnf install`, forever.
> **Fix** (before the kernel install):
> ```bash
> dnf -y clean packages metadata
> ...
> dnf -y install --refresh $KERNEL_PACKAGES akmods
> ```
> *`install.sh` lines 188, 201.* Belt and suspenders: `clean packages` drops cached RPMs, `--refresh` drops cached metadata.

### 3.2.4 Capture the version, scrub the repo

```bash
KERNEL_VERSION="$(rpm -q "$KERNEL_PKG" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
...
rm -f /etc/yum.repos.d/*copr*
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 217, 224)*

`KERNEL_VERSION` (e.g. `7.0.8-cachyos1.fc44.x86_64`) drives everything downstream: signing paths, akmods `--kernels`, the dracut loop. The COPR `.repo` file is deleted from the final image: deployed machines must never pull kernel updates from the COPR directly; kernel updates arrive only as new *images* through the CI pipeline. This "enable repo, install, scrub repo" pattern repeats for every third-party repo in the script (kernel-cachyos-addons, RPM Fusion).

## 3.3 Out-of-tree modules: the akmods pattern in a container

akmods is Fedora's mechanism for rebuilding out-of-tree kernel modules (`akmod-*` source packages → `kmod-*` binary RPMs) whenever a new kernel lands. On a normal system it runs as a boot-time service. In an image build you run it once, by hand, against the kernel you just installed, and you fight two container-specific problems.

**Problem 1: akmodsbuild wants a writable `/var`.** On bootc builds `/var` is a cache mount; `akmodsbuild` has a guard that silently skips work when `/var` isn't writable the way it expects. Margine patches the guard out of the script for the duration of the build:

```bash
disable_akmodsbuild() {
  _ak="/usr/sbin/akmodsbuild"
  [[ -f "$_ak" ]] || return 1
  cp -p "$_ak" "$_ak.backup"
  sed '/if \[\[ -w \/var \]\] ; then/,/fi/d' "$_ak" > "$_ak.tmp"
  mv "$_ak.tmp" "$_ak"
  chmod +x "$_ak"
}
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 85-92)*

`sed` deletes the whole `if [[ -w /var ]]` block from `/usr/sbin/akmodsbuild`; the backup is restored afterwards. Ugly, effective, and bounded to the build.

**Problem 2: `akmods` always exits 0.** Success must be detected by the *absence* of a failure log, not by exit code:

```bash
if dnf -y install \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
   && dnf install -y --setopt=install_weak_deps=False --setopt=tsflags=noscripts \
      akmod-v4l2loopback; then
  if akmods --force --verbose --kernels "$KERNEL_VERSION" --kmod v4l2loopback; then
    # akmods always returns 0; check for *.failed.log explicitly
    V4L2_FAILED=0
    for _f in /var/cache/akmods/v4l2loopback/*-for-"$KERNEL_VERSION".failed.log; do
      [[ -f "$_f" ]] && V4L2_FAILED=1 && break
    done
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 240-249)*

Notes on the flags: `tsflags=noscripts` skips the akmod RPM's %post scriptlet (which would try to kick off a build via the boot-time service path); `--kernels "$KERNEL_VERSION"` builds against the CachyOS headers from `-devel-matched`, not whatever `uname -r` says inside the container (the *runner's* kernel, always wrong).

If the build succeeded, the produced binary `kmod-*` RPM is installed from the akmods cache:

```bash
_kmod_rpm="$(find /var/cache/akmods/v4l2loopback/ -name "kmod-v4l2loopback-*$KERNEL_VERSION*.rpm" -print -quit 2>/dev/null || true)"
if [[ -n "${_kmod_rpm:-}" && -f "$_kmod_rpm" ]]; then
  dnf -y install "$_kmod_rpm"
  TRANSIENT="$TRANSIENT kmod-v4l2loopback"
fi
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 263-267)*

The `.ko` lands under `/usr/lib/modules/$KERNEL_VERSION/` and gets MOK-signed later in the same script along with every other module, out-of-tree modules need the same signature as in-tree ones under Secure Boot.

The whole v4l2loopback block is deliberately **best-effort**: a failed virtual-camera module is logged and skipped, never a failed image (`v4l2loopback` is the documented exception to the project's "no unjustified `|| true`" rule). RPM Fusion is enabled only for this block and scrubbed immediately after (`dnf -y remove rpmfusion-free-release; rm -f /etc/yum.repos.d/rpmfusion-free*.repo`).

**Cleanup of build-only packages** is explicit, never `autoremove`:

```bash
log "Removing transient build-only packages: $TRANSIENT"
dnf -y remove $TRANSIENT || true
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 396-398)*

`TRANSIENT` = `akmods sbsigntools kernel-cachyos-devel-matched` (+ the akmod/kmod pair when built, the kmod's *files* survive; only the RPM bookkeeping is dropped to avoid a dangling package whose repo no longer exists). The comment at lines 374-377 records why `dnf autoremove` is banned here: with the COPR already disabled, autoremove decided the freshly installed `kernel-cachyos` chain itself was removable (margine-image PR #26).

### Same-COPR userland: scx-scheds

The CachyOS kernel ships `CONFIG_SCHED_CLASS_EXT=y`, so Margine also installs the sched_ext BPF schedulers (`scx_lavd`, `scx_bpfland`, `scx_rusty`, …) from the sibling COPR `bieszczaders/kernel-cachyos-addons`, same maintainer, kernel and schedulers released as a pair, no version drift. Same retry loop, same repo scrub, and the daemon is opt-in:

```bash
log "Disabling scx_loader.service by default (opt-in via margine-scheduler)"
systemctl disable scx_loader.service 2>/dev/null || true
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 316-317)*

Bazzite pattern: ship the capability in the image, leave the service off (it cost battery with no obvious default win); users enable it via `ujust margine-scheduler` or a GUI picker.

## 3.4 Regenerating the initramfs in-container

This is where every naive kernel swap dies. Dracut's defaults are calibrated for "regenerate on the machine that will boot this", and the build container is *not* that machine. Three defaults are wrong, and each one independently produces an unbootable image. Margine hit all three in production (lessons-learned, 2026-05-28 VM smoke test), plus two ostree-specific failures on top.

> **Lesson — `--kver` + `--regenerate-all` are mutually exclusive, and `|| true` ate the proof**
> **Symptom:** kernel panic at first boot: `VFS: Cannot open root device "UUID=..."`; available partitions listed as raw `vda{1,2,3}`, no LUKS mapper, no btrfs.
> **Root cause:** the build called `dracut --force --kver "$KVER" --regenerate-all || true`. dracut printed `--regenerate-all cannot be called with a kernel version`, exited 1 — and `|| true` swallowed it. **No initramfs was ever generated by our code**; boot used a stale base-layer fallback built for Bluefin's kernel.
> **Fix:** drop the conflicting flag combination, and drop the `|| true` — if dracut fails the image is unbootable, so fail loud. Meta-rule adopted project-wide: every `|| true` in an image build needs a written justification.

> **Lesson, host-only initramfs of the wrong "host"**
> **Symptom:** same panic, after the first fix.
> **Root cause:** dracut defaults to host-only mode, and "the host" is the CI build container: no LUKS device, no btrfs root, no virtio_blk. dracut correctly omitted exactly the modules every real install needs.
> **Fix:** force generic mode on the command line *and* persist the policy so any later regeneration (user-triggered `rpm-ostree initramfs`, the Plymouth stage's regen) inherits it:
> ```bash
> mkdir -p /etc/dracut.conf.d
> cat > /etc/dracut.conf.d/01-margine-no-hostonly.conf <<'CONF'
> # Required for bootc / OCI image builds: the build environment is not
> # the deployment environment, so initramfs must be generic.
> hostonly="no"
> hostonly_cmdline="no"
> CONF
> ```
> *`install.sh` lines 409-415.*

> **Lesson, dracut writes to `/boot/`; ostree reads `/usr/lib/modules/<kver>/`**
> **Symptom:** same panic. The published image *did* contain a correct 303 MB generic initramfs, at `/boot/initramfs-7.0.8-cachyos1.fc44.x86_64.img`.
> **Root cause:** bootc/ostree picks the initramfs from `/usr/lib/modules/<kver>/initramfs.img` at deploy time and **ignores `/boot/`** (dracut's traditional default output). With nothing at the canonical path, ostree falls back to deploy-time auto-generation, host-only again.
> **Fix:** pass the output path as dracut's positional argument (see the final loop below). Verified against the Bluefin DX base image, which keeps its initramfs at exactly that path.

> **Lesson, the `ostree` dracut module is never auto-included**
> **Symptom:** with all three fixes in, boot got past the initramfs and dropped to a dracut emergency shell: `Failed to switch root: os-release file is missing`. `/sysroot` contained only `home/ root/ var/`, raw btrfs subvolumes, not a deployment.
> **Root cause:** dracut does not include the `ostree` module just because the build host is ostree-based. Without it the initramfs lacks `ostree-prepare-root`, the tool that pivots `/sysroot` from the raw disk root to the deployment checkout *before* systemd's switch-root. Diagnosed with `lsinitrd <initramfs> | grep ostree` → zero lines on the published image.
> **Fix:** `--add "ostree"` on every dracut invocation. `--no-hostonly` alone is not sufficient.

The final, correct invocation, all four lessons folded in:

```bash
for kver_dir in /usr/lib/modules/*/; do
  kver=$(basename "$kver_dir")
  dracut --force --no-hostonly --no-hostonly-cmdline \
      --add "ostree" \
      --kver "$kver" \
      "${kver_dir}initramfs.img"
  log "Wrote ${kver_dir}initramfs.img ($(du -h ${kver_dir}initramfs.img | cut -f1))"
done
```
*`/var/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` (lines 460-467)*

One initramfs per kernel directory (there is exactly one, §3.2.2), written to the bootc-canonical path, generic, with ostree support. Two peripheral details from the surrounding script: dracut runs *after* module signing so the modules copied into the initramfs are the signed ones, and `mkdir -p /root && chmod 700 /root` beforehand silences a spurious `dracut-install: ERROR: installing '/root'` from the ssh-client module probing for `/root/.ssh/` in a sysroot where `/root` doesn't exist (cosmetic; the alternative `omit_dracutmodules+=" ssh-client "` would also drop dropbear-based remote LUKS unlock support).

> **Lesson, the inherited `ostree.linux` OCI label points at the *old* kernel**
> **Symptom:** initramfs fully fixed, boot fails at `initrd-switch-root.service`; bootloader entries reference deployment hashes that don't exist on disk.
> **Root cause:** Bluefin DX labels its image `ostree.linux=<bluefin-kernel-version>`. The kernel swap replaced the files but inherited the label, and bootc/rpm-ostree consult `ostree.linux` at deploy time to pick the kernel version for the bootloader entry and to find `/usr/lib/modules/<label>/`. Pointed at a nonexistent kernel, deployment-dir hash and bootloader-entry hash diverge.
> **Fix:** rewrite the label after build from the image's actual content (`buildah config --label ostree.linux=<kver>`, reading `<kver>` from `/usr/lib/modules/` inside the built image). In the current pipeline this is subsumed by the rechunk step (`hhd-dev/rechunk@v1.2.4` in `/var/home/daniel/dev/margine-image/.github/workflows/build.yml` lines 448-464), which re-commits the image in ostree-canonical form; a CI invariant check still asserts label == installed kernel on every build.
> **General rule:** `FROM` inherits *all* of the base's OCI labels. Any label describing content you changed (kernel version, rechunk manifest) must be overwritten.

## 3.5 Validating the swap

Three layers, because "image builds green" ≠ "image boots":

- **Build-time (CI, blocks push):** `/usr/lib/modules/*/initramfs.img` exists; initramfs size sanity (>50 MB — a host-only one is <30); `lsinitrd | grep ostree-prepare-root` non-empty; dm-crypt/dm-mod/btrfs/virtio_blk present as modules or builtins; `ostree.linux` label matches the installed kernel. Every one of these maps 1:1 to a bug above.
- **Boot-time (CI, gates `:stable`):** the QEMU smoke-boot workflow boots the candidate qcow2 under OVMF+swtpm and requires `Reached target Multi-User System` before `skopeo copy --preserve-digests` promotes candidate → `:stable` (CI chapter).
- **On-machine (user-run):** `margine-validate-cachyos-kernel` confirms the running kernel is actually the shipped one:

```bash
section "Kernel"
kernel=$(uname -a)
if printf '%s\n' "$kernel" | grep -Eiq 'cachy|cachyos'; then
  ok "running kernel appears to be CachyOS"
else
  fail "running kernel does not appear to be CachyOS"
fi
```
*`build_files/40-spec-scripts/scripts/validate-cachyos-kernel` (lines 30-38)*

It also warns if stock Fedora `kernel-*` RPMs are visible in the deployment, and flags common out-of-tree module packages (nvidia, zfs, vbox) as out-of-policy.

## 3.6 Benchmarking the kernel

The kernel is Margine's one performance-relevant delta from Bluefin DX, so it is the one thing worth measuring, and the only fair way to measure it is to hold everything else constant. The harness lives in `tools/bench/` in the image repo; it is host-side, never baked into the image, and excluded from CI (`tools/**` is in `build.yml`'s `paths-ignore`).

**The harness, `margine-bench-kernel.sh`.** Margine's host has no `dnf`, so the benchmark tools (`perf`, `sysbench`, `stress-ng`, and an optional `schbench` built from git) run inside a throwaway Fedora distrobox with a dedicated scratch `HOME`. This is sound because *a distrobox container shares the host kernel*, the numbers reflect the real booted CachyOS/BORE kernel, not the container's userspace. Four scheduler benchmarks run under a `stress-ng --cpu` background load, because an idle machine tells you nothing about behaviour under use:

| Benchmark | Measures | Note |
| --- | --- | --- |
| `schbench` | wakeup-latency percentiles under load | optional, built from kernel.org git in-container; the parser takes the *final* steady-state checkpoint, not the first interval |
| `perf bench sched pipe` | context-switch round-trip latency + rate | pure userspace, no `perf_event` access needed |
| `perf bench sched messaging` | many-task messaging throughput | the packaged hackbench stand-in (hackbench is not in Fedora) |
| `sysbench threads` | throughput + latency under mutex contention | |

With `BENCH_JSON_OUT` set, the run also writes a machine-readable result, the parsed metrics plus identity (kernel, governor, nproc, and the DMI machine model) and *start/end CPU temperature*, and *fails loudly* (a red banner, a non-zero exit, `metrics_collected: 0` in the JSON) if the tools never ran, so an interrupted run cannot silently produce an identity-only file that later looks like a real measurement.

**The method, a deployment-switch A/B.** The comparison runs on *one laptop*: benchmark Margine, then switch ostree deployments and benchmark the baseline, so the *only* variable is the kernel:

```bash
# on Margine (CachyOS/BORE):
BENCH_LABEL=margine-cachyos BENCH_JSON_OUT=m.json ./margine-bench-kernel.sh
# rebase to the stock-kernel baseline, dropping any layered pkgs so depsolve passes:
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/bluefin-dx:stable --uninstall steam …
# …reboot, benchmark again, then `rpm-ostree rollback` back to Margine.
```

Same hardware, same userspace, same governor (`performance`), no `scx` scheduler loaded, stock BORE vs stock Fedora EEVDF. The kernel *point* versions differ (each distro's current stable; different trees, not version-matchable), but that gap is bug-fix backports, far too small to explain the deltas.

**The comparer, `margine-bench-compare.py`** (pure stdlib) groups result JSONs by label and reports the *median* of each metric, so several runs collapse into one throttling-resistant column. It refuses identity-only inputs (naming the file), flags any metric that swings more than 25% across runs, warns when two systems' median start temps differ by more than 8 °C (not thermally comparable), and emits an ASCII-safe SVG (numeric XML entities + a UTF-8 declaration, so `×`/`µ`/`°` render in any viewer instead of mojibake) plus a Markdown table.

**Thermal control matters on a thin-and-light.** Under sustained all-core load this hardware hits its ~100 °C limit and throttles, both kernels equally. A hotter *start* throttles sooner and looks worse, so each side is run several times at varied start temperatures and the *median start temp is matched* (the comparer enforces the 8 °C rule). Every run ends at the thermal limit, so the absolute numbers are conservative; the relative gap is fair.

**Result (median of 4, Framework Laptop 13 / AMD Ryzen 5 7640U, 2026-06-16):** CachyOS/BORE does ~1.8× the context-switch throughput, +54% thread throughput, and 40–55% lower median / average scheduling latency than the stock Fedora kernel, at a ~10% cost to *tail* latency (p95/p99). That common-case-for-tail trade is BORE's design, and the fact that it shows up (rather than a clean sweep) is a sign the measurement is honest rather than cherry-picked. Raw per-run data, the chart, and a provenance README are committed under `margine-image` `tools/bench/results/2026-06-16/`; the user-facing write-up is the [Kernel performance](https://margine.dev/docs/kernel-performance) doc.

## Alternatives & other distros

Approaches to "which kernel ships in the image", roughly by increasing maintenance cost:

- **Stock Fedora kernel, untouched**, Bluefin, Aurora, Silverblue/Kinoite, Fedora CoreOS. Signed by Fedora, boots under Secure Boot with zero ceremony, zero pipeline cost. The default; deviate only with a measured reason (ADR 0006 option C).
- **Stock kernel + prebuilt akmods from `ghcr.io/ublue-os/akmods`**, Bluefin DX, Aurora, uBlue NVIDIA variants. Universal Blue builds/signs kmods (nvidia, xone, v4l2loopback, …) in dedicated OCI images; consumers `COPY --from=ghcr.io/ublue-os/akmods:main-<fedora>` the RPMs in. No compiler in your build, modules signed with the uBlue key (whose MOK users enroll once). The cleanest pattern if the kernels/kmods you need are already published.
- **OGC kernel (`ghcr.io/ublue-os/akmods:ogc-…` flavor)**, Bazzite (migrated off its own `kernel-bazzite` fork, archived 2026-05-01), Nobara, ChimeraOS, Playtron, PikaOS. Shared 8-distro CI, upstream-first charter, handheld HID + NTSYNC + gyro in tree. The gaming-consensus kernel; no BORE/ThinLTO/HZ=1000 by default.
- **Surface kernels**, Bluefin's `-surface` images swap in the linux-surface kernel the same remove-and-replace way, for Microsoft Surface hardware support. Demonstrates the pattern generalizes to any hardware-enablement tree.
- **COPR kernel installed in your own build**, Margine (this chapter), Origami Linux (whose `custom-kernel.sh` Margine's script descends from). Maximum flexibility, you own signing, retries, initramfs, and the single-maintainer-COPR risk.
- **Runtime layering on the deployed machine**, `rpm-ostree override remove kernel{,-core,-modules,...} --install kernel-cachyos`. Margine's pre-image lab path (`docs/spec/03-cachyos-kernel.md`); works per-machine, rollback-safe, but unsigned (Secure Boot off only), per-machine drift, and every deployment rebuilds the override. Kept as documentation, superseded by image-baking.
- **NixOS**, `boot.kernelPackages = pkgs.linuxPackages_cachyos;` declaratively; module packages rebuilt by Nix against the chosen kernel. Same outcome, entirely different toolchain.
- **openSUSE MicroOS/Aeon**, stock SUSE kernel via transactional-update/snapper snapshots; custom kernels are plain zypper packages in a transaction. Rollback via btrfs snapshot instead of image swap.
- **Vanilla OS (ABRoot)**, Debian-based A/B partitions; kernel changes go through ABRoot transactions on the inactive root.
- **UKI / sealed images (systemd-boot + unified kernel image + composefs fs-verity)**, tracked by Margine in ADR 0007, not yet shipping anywhere mainstream on the Fedora desktop track. Would replace the vmlinuz+initramfs pair (and most of §3.4) with a single signed PE binary; the long-term direction for measured boot.


---

# 4. Secure Boot for a custom kernel: shim → MOK

Chapter 3 swapped Bluefin's stock kernel for CachyOS. That swap breaks exactly one link in the
UEFI trust chain: the kernel image is no longer signed by Fedora. This chapter covers how Margine
repairs that link with a Machine Owner Key (MOK), signing at image build, certificate shipping,
and the first-boot enrollment UX, and what the alternatives would have cost.

## 4.1 The trust chain and where a custom kernel breaks it

On a stock Fedora Atomic / Universal Blue system with Secure Boot enabled:

```
UEFI firmware db (Microsoft 3rd-party UEFI CA)
  └─ verifies → shim-x64.efi          (Fedora's shim, Microsoft-signed)
       └─ verifies → grubx64.efi      (Fedora-signed; shim embeds the Fedora CA)
            └─ verifies → vmlinuz     (Fedora-signed, via the shim_lock protocol:
                                       checked against firmware db + shim's MokList)
                 └─ verifies → *.ko   (kernel module signature enforcement against
                                       the kernel's builtin keys + the MOK keyring)
```

Everything above `vmlinuz` is inherited unchanged from the base image. Margine never touches
shim or GRUB, so the Microsoft-signed entry point keeps working on every consumer machine
without firmware changes. A COPR kernel (`kernel-cachyos`) carries no Fedora signature, so with
Secure Boot on, GRUB refuses to load it ("bad shim signature") and every out-of-tree `.ko`
is rejected by the module loader.

shim's escape hatch is **MokList**: a list of extra certificates stored in EFI variables,
managed by the user through `mokutil` (stages a request from the running OS) and **MokManager**
(the blue pre-boot UI that confirms it with physical presence). Anything signed by a MokList
cert is as trusted as anything Fedora-signed. So the design is:

1. Generate one Margine keypair (RSA-2048).
2. At image build: sign `vmlinuz` with `sbsign` and every module with the kernel's `sign-file`.
3. Ship the public cert in the image at `/usr/share/cert/MOK.der`.
4. Get the cert into MokList on first boot with the least possible user pain.

Note the project did not start here. ADR 0003 (2026-05-22) explicitly deferred custom keys,
"Fedora signed shim → Fedora signed GRUB → Fedora signed kernel […] Do not use Limine, sbctl,
custom MOK keys", until the stock chain plus LUKS2/TPM2 was proven in the lab
(`docs/spec/adr/0003-fedora-native-boot-security.md`). The MOK
path arrived only with ADR 0006's CachyOS decision. Prove the boring baseline first.

## 4.2 Key material: what is secret and what is not

| File | Location | Visibility |
| --- | --- | --- |
| `MOK.key` (RSA-2048 private) | GitHub Actions secret `MOK_KEY` + offline backup, chmod 600 | **private, never committed** |
| `MOK.pem` (X.509 cert, PEM) | committed at `margine-image/secrets/MOK.pem` + secret `MOK_CERT` | public |
| `MOK.der` (same cert, DER) | committed at `margine-image/secrets/MOK.der`, shipped in-image | public |
| `MOK_PASSWORD` | hardcoded constant `MOK_PASSWORD="margine-os"` in `build_files/custom-kernel/install.sh` | **public by design** (§4.6) |

The build refuses to proceed with mismatched material. A wrong-cert build would produce an
image whose kernel can never be trusted, discovered only at a user's boot screen:

```bash
# margine-image/build_files/custom-kernel/install.sh:36-44
openssl pkey -in "$SIGNING_KEY"  -noout >/dev/null \
  || { err "MOK.key is not a valid private key"; exit 1; }
openssl x509 -in "$SIGNING_CERT" -noout >/dev/null \
  || { err "MOK.pem is not a valid X509 cert"; exit 1; }
_tmp1=$(mktemp); _tmp2=$(mktemp)
openssl pkey -in "$SIGNING_KEY"  -pubout        >"$_tmp1"
openssl x509 -in "$SIGNING_CERT" -pubkey -noout >"$_tmp2"
cmp -s "$_tmp1" "$_tmp2" \
  || { rm -f "$_tmp1" "$_tmp2"; err "MOK.key and MOK.pem don't match"; exit 1; }
```

Extracts the public key from both halves and byte-compares them. Fail-fast at minute 1 of a
28-minute build instead of fail-silent at the user's firmware.

### Getting secrets into the build without leaking them

CI materializes the GitHub secrets as files, then hands them to buildah as BuildKit secrets:

```yaml
# margine-image/.github/workflows/build.yml:125-136
- name: Stage MOK secrets for BuildKit
  env:
    MOK_KEY:      ${{ secrets.MOK_KEY }}
    MOK_CERT:     ${{ secrets.MOK_CERT }}
  run: |
    mkdir -p /tmp/margine-secrets
    chmod 700 /tmp/margine-secrets
    printf '%s' "$MOK_KEY"      > /tmp/margine-secrets/MOK.key
    printf '%s' "$MOK_CERT"     > /tmp/margine-secrets/MOK.pem
```

```dockerfile
# margine-image/Containerfile:39-46
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok-key,target=/tmp/certs/MOK.key \
    --mount=type=secret,id=mok-cert,target=/tmp/certs/MOK.pem \
    /ctx/custom-kernel/install.sh
```

`type=secret` mounts exist only during this RUN and never become an image layer; `/tmp` is a
tmpfs mount on top of that. The private key cannot end up in the published OCI image even by
accident. `COPY secrets/` into a layer is the classic way projects leak signing keys.

## 4.3 Signing at image build

### vmlinuz with sbsign

```bash
# margine-image/build_files/custom-kernel/install.sh:98-108
sign_kernel() {
  _vmlinuz="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"
  [[ -f "$_vmlinuz" ]] || { err "vmlinuz not found at $_vmlinuz"; return 1; }
  _tmp=$(mktemp)
  sbsign --key "$SIGNING_KEY" --cert "$SIGNING_CERT" --output "$_tmp" "$_vmlinuz"
  sbverify --cert "$SIGNING_CERT" "$_tmp" \
    || { rm -f "$_tmp"; err "sbverify failed on signed kernel"; return 1; }
  cp "$_tmp" "$_vmlinuz"
  chmod 0644 "$_vmlinuz"
  rm -f "$_tmp"
}
```

`sbsign` (from `sbsigntools`, installed transiently and removed at the end of the layer) embeds
an Authenticode signature in the PE binary. `sbverify` re-checks before the original is
overwritten, so a half-written signature can't ship. The path is the ostree-canonical
`/usr/lib/modules/<KVER>/vmlinuz`. Sign in place, before initramfs regeneration.

### Every module with sign-file

The kernel verifies modules itself (`CONFIG_MODULE_SIG`), with a detached-appended signature
format that `sbsign` does not produce. The kernel tree's own `scripts/sign-file` does. Fedora
kernels ship modules compressed, and signatures must go on the *uncompressed* ELF:

```bash
# margine-image/build_files/custom-kernel/install.sh:110-129 (trimmed: .gz arm omitted)
sign_kernel_modules() {
  _module_root="/usr/lib/modules/${KERNEL_VERSION}"
  _sign_file="${_module_root}/build/scripts/sign-file"
  [[ -x "$_sign_file" ]] || { err "sign-file missing: $_sign_file"; return 1; }
  find "$_module_root" -type f \( \
      -name "*.ko" -o -name "*.ko.xz" -o -name "*.ko.zst" -o -name "*.ko.gz" \
    \) | while IFS= read -r _mod; do
    case "$_mod" in
      *.ko)
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_mod" ;;
      *.ko.xz)
        _raw="${_mod%.xz}"
        xz -d -q "$_mod"
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_raw"
        xz -z -q "$_raw" ;;
      *.ko.zst)
        _raw="${_mod%.zst}"
        zstd -d -q --rm "$_mod"
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_raw"
        zstd -q "$_raw" ;;
```

Decompress → sign → recompress, per compression format. `sign-file` comes from
`kernel-cachyos-devel-matched` (also transient). One pass covers thousands of modules.

**Ordering matters.** `sign_kernel` / `sign_kernel_modules` run near the *end* of
`install.sh` (lines 384-388), after the v4l2loopback akmod build has dropped its `kmod-` RPM
into `/usr/lib/modules/${KERNEL_VERSION}`. Any module-producing step added *after* the signing
pass ships an unsigned `.ko` that the kernel will reject under lockdown (§4.7), a class of bug
invisible in CI (the QEMU smoke gate boots without Secure Boot) and visible only on enrolled
hardware. Keep signing last among module producers.

## 4.4 Shipping the cert + the first-boot fallback service

The same build layer converts the cert to DER (the format `mokutil` wants), drops it at a fixed
in-image path, and writes the fallback enrollment unit:

```bash
# margine-image/build_files/custom-kernel/install.sh:139-162 (trimmed)
create_mok_enroll_unit() {
  _mok_cert="/usr/share/cert/MOK.der"
  _unit_file="/usr/lib/systemd/system/mok-enroll.service"
  mkdir -p "$(dirname "$_mok_cert")"
  openssl x509 -in "$SIGNING_CERT" -outform DER -out "$_mok_cert"
  ...
  cat > "$_unit_file" <<EOF
[Unit]
Description=Enroll Margine MOK on first boot
ConditionPathExists=${_mok_cert}
ConditionPathExists=!/var/.mok-enrolled

[Service]
Type=oneshot
ExecStart=/bin/sh -c '(echo "${MOK_PASSWORD}"; echo "${MOK_PASSWORD}") | mokutil --import "${_mok_cert}"'
ExecStartPost=/usr/bin/touch /var/.mok-enrolled
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl -f enable mok-enroll.service
}
```

Mechanics worth knowing:

- `mokutil --import` does not modify MokList directly. It writes a *pending request* (cert +
  password hash) into the `MokNew` EFI variable. On the next boot, shim sees the request and
  chains into **MokManager**, the blue/grey pre-boot screen, where a human selects
  `Enroll MOK` → `Continue` → `Yes`, types the passphrase, and reboots. Only then does the cert
  enter MokList. No amount of root access enrolls a key without that console step.
- The two `echo`s feed mokutil's password + confirmation prompts non-interactively.
- The marker file lives in `/var`, which on ostree systems is machine-local state shared across
  deployments: the unit runs once per *machine*, not once per image update. `ConditionPathExists=!`
  makes the unit a no-op forever after, while leaving a trivially scriptable reset (§4.8).
- The unit is enabled at build time (`systemctl -f enable` works in a container build, it just
  creates the `multi-user.target.wants/` symlink in `/usr`), so every fresh deployment has it
  armed with zero installer cooperation.

The user-visible rebase flow is therefore: rebase → reboot (service stages the request) →
reboot again → MokManager → type `margine-os` → done. Two reboots; the kernel chain is verified
on every boot thereafter.

## 4.5 The ISO path: stage the request *before* the first installed boot

The fallback unit has a structural flaw on fresh installs: it runs inside the OS whose kernel is
not yet trusted. Margine's installer ISO closes the loop from Anaconda instead.

> **Lesson: ISO MOK enrollment timing (PR #88, 2026-06-08)**
> **Symptom:** fresh ISO installs got no MOK Manager screen on the first reboot; the installed
> system had to boot once (possible only because the lab machine had Secure Boot relaxed) just
> so `mok-enroll.service` could stage the request, then reboot again. On a strict Secure Boot
> machine the first installed boot would simply fail: the enrollment service can never run on
> a kernel that can't boot. Chicken-and-egg.
> **Root cause:** enrollment was staged only from *inside* the installed OS; nothing ran in the
> installer environment, which boots a Fedora-signed Anaconda kernel and is already fully
> trusted under Secure Boot.
> **Fix:** an Anaconda `%post --nochroot` (running in the trusted installer environment, with
> the EFI variables of the target machine) submits the import request before the first
> installed boot, mirroring Bluefin/Bazzite's ISO flow. shim opens MokManager on the very
> first post-install reboot, *before* the Margine kernel is ever loaded.

```bash
# margine-image/live-env/src/anaconda/post-scripts/secureboot-enroll-key.ks:15-64 (trimmed)
%post --nochroot --log=/mnt/sysimage/var/log/anaconda-post-mok-enroll.log
if [[ ! -d /sys/firmware/efi ]]; then
  log "EFI mode not detected — skipping MOK import"; exit 0
fi
MOK_CERT=""
for candidate in \
  /mnt/sysimage/usr/share/cert/MOK.der \
  /mnt/sysimage/ostree/deploy/default/deploy/*.0/usr/share/cert/MOK.der
do
  [[ -f "$candidate" ]] && { MOK_CERT="$candidate"; break; }
done
...
if mokutil --test-key "$MOK_CERT" >/dev/null 2>&1; then
  log "Margine MOK is already enrolled — nothing to import"; exit 0
fi
mokutil --timeout -1 || log "WARN: failed to set MokTimeout; continuing"
if printf '%s\n%s\n' 'margine-os' 'margine-os' | mokutil --import "$MOK_CERT"; then
  log "MOK import request submitted — shim should launch MokManager on the next boot"
fi
%end
```

Details that earn their bytes:

- The cert is read **from the target deployment** (both the `/mnt/sysimage` flat view and the
  raw ostree deploy path are probed), so the request always matches the exact image being
  installed, no second copy of the cert to drift.
- `mokutil --test-key` makes reinstalls idempotent: already-enrolled machines get no prompt.
- `mokutil --timeout -1` disables MokManager's 10-second auto-continue, so an unattended first
  reboot parks on the prompt instead of silently skipping enrollment.
- **It deliberately does not create `/var/.mok-enrolled`.** If the user mashes Enter past
  MokManager, the in-OS `mok-enroll.service` re-stages the request on the next successful boot.
  Belt and suspenders, each path covering the other's miss.
- Every exit path is a soft `exit 0`: a BIOS-mode install or a missing `mokutil` degrades to
  the service fallback instead of failing the whole install.

This fragment is the one the Titanoboa live ISO ships (ADR 0008 ported it verbatim from the
retired `iso-gnome.toml`), and it carries one wrinkle the BIB ISO didn't have: the live
environment itself runs Margine's CachyOS kernel, which is untrusted before enrollment. The
documented flow there is *disable Secure Boot → boot live ISO → install (request staged) →
re-enable Secure Boot → MokManager → enroll*. That is the cost of shipping one kernel in both
the live and installed environments instead of keeping a Fedora-signed live kernel.

## 4.6 Why the passphrase is public by design

`margine-os` is printed in the README, the docs site, and this handbook. That is correct, not
sloppy, because the password is not a secret-keeping mechanism:

- The real gate is **physical presence**. MokManager runs pre-OS, on the console, before any
  network or remote-access stack exists. The password's only job is to bind the console
  confirmation to the request staged earlier from the OS, proving the person at the keyboard
  is acting on *that* request, not rubber-stamping noise.
- An attacker with root could stage their own `mokutil --import` with their own password
  anyway; knowing Margine's adds nothing. An attacker *without* root can't stage a request at
  all. The password protects against exactly one thing, a user confirming a request they did
  not initiate, and a documented distro-wide value preserves that property: users are told
  "if the screen asks for a passphrase and `margine-os` works, this is the Margine request."
- Precedent: Universal Blue ships the same pattern with their public `ublue-os` key passphrase
  for Bazzite/Bluefin akmod signing. Margine copied it deliberately.

> **Lesson: passphrase rotation (2026-06-06)**
> **Symptom:** test installs stalled at MokManager: the original passphrase was a 24-character
> random base64 string, and MokManager is a pre-boot UI with no clipboard, no second screen
> docs, and a US-layout keymap.
> **Root cause:** treating a public-by-design value as if it were a secret; entropy bought
> nothing and cost typability.
> **Fix:** rotate `MOK_PASSWORD` to the short human-typable `margine-os` (same pattern as
> ublue-os) and print it in the install docs. Recorded in
> `docs/spec/07-secure-boot-tpm2.md` ("rotated 2026-06-06 […] so users can
> type it at the MOK Manager screen without copy-paste").

Avoid characters that move between keymaps (`y/z`, symbols). MokManager will not honor the
user's configured layout.

## 4.7 Kernel lockdown implications

When Secure Boot is enabled, Fedora kernels (CachyOS COPR builds included) activate
`lockdown=integrity`. For a distro builder this changes what users can do post-install:

- **Unsigned modules will not load.** No runtime DKMS/akmods for users: the private key is in
  CI, not on their disk. Anything module-shaped must be built *and signed* at image build time, 
  which is exactly why v4l2loopback is compiled in the kernel layer (before the signing pass)
  rather than documented as a user `rpm-ostree install akmod-v4l2loopback`. A user-layered akmod
  produces a module the kernel rejects with `Key was rejected by service`.
- **Hibernation is blocked** (unsigned/unverified resume image), `kexec` of unsigned kernels is
  blocked, and raw `/dev/mem`, MSR writes, and ACPI table overrides are restricted, relevant to
  undervolting/overclocking tools some performance-distro users expect.
- The flip side: disabling Secure Boot also disables lockdown. "Just turn off SB" (§4.9) is not
  only a trust-chain downgrade; it silently changes kernel behavior users may depend on.
- Interaction with chapter 5's TPM2 story: the hardware PCR policy is `0+7`: PCR 7 measures
  Secure Boot state, so toggling SB or enrolling new keys changes PCR 7 and TPM auto-unlock
  falls back to the LUKS passphrase (which Margine never removes). Enroll the MOK *first*, then
  bind TPM2.

## 4.8 Recovery and verification

If both enrollment paths were missed (or the user hit "Continue boot" at MokManager), the
marker-file design makes retry a three-liner:

```sh
sudo rm /var/.mok-enrolled
sudo systemctl start mok-enroll.service
sudo systemctl reboot
```

Verification on an enrolled system:

```sh
mokutil --sb-state                          # → SecureBoot enabled
mokutil --list-enrolled | grep -i margine   # cert visible in MokList
mokutil --test-key /usr/share/cert/MOK.der  # → "is already enrolled"
```

The on-image validator `margine-validate-atomic-layout` (chapter 9) checks Secure Boot state as
part of its layout assertions, and `margine-collect-diagnostics` captures `mokutil` output for
bug reports.

## 4.9 Alternatives & other distros

- **Keep the stock Fedora-signed kernel**: Bluefin, Aurora, Silverblue/Kinoite stock, Fedora
  CoreOS. Zero enrollment UX, zero key custody; you give up the custom kernel entirely. This
  was Margine's own phase-1 position (ADR 0003) until ADR 0006 accepted the MOK cost.
- **MOK for akmods only, stock kernel underneath**: Universal Blue's `ublue-os/akmods`
  (Bazzite/Bluefin NVIDIA + extra kmods, public `ublue-os` passphrase). Smallest possible MOK
  surface: only out-of-tree modules need the key, the kernel link stays Fedora-signed. The
  precedent Margine extended to a whole kernel.
- **Document "disable Secure Boot"**: Bazzite's docs fallback for stubborn firmware, and
  effectively mandatory on ChimeraOS and most Arch-derived gaming distros. Zero friction,
  works everywhere; loses boot-chain verification, disables lockdown, and changes PCR 7 (breaks
  TPM-bound LUKS policies that include it).
- **Enroll your own PK/KEK/db (full owner keys)**: `sbctl` on Arch/CachyOS classic;
  NixOS via **lanzaboote** (signs generations with owner keys since upstream NixOS has no shim).
  No shim, no MokManager, cryptographic ownership of the whole chain; but firmware-fiddly,
  per-machine (a distro can't pre-enroll for you), and dropping the Microsoft CA can brick
  GPU option ROMs unless the MS certs are re-added to db.
- **Distro-own CA inside shim** (openSUSE MicroOS/Aeon/Tumbleweed): Microsoft signs their shim,
  shim embeds openSUSE's CA, openSUSE signs kernels *and* kmod packages; MOK is used
  automatically for things like the NVIDIA driver. Same architecture as Fedora, viable only if
  you are big enough to get a shim review (shim-review is a months-long process; out of reach
  for a one-person distro, which is exactly why Margine rides Fedora's shim).
- **UKI + sealed images**: systemd-boot + Unified Kernel Images + composefs/fs-verity
  (Fedora's tracked future, ADR 0007 "Watching"; openSUSE Aeon is moving this way with FDE).
  Measures and signs the whole kernel+initramfs+cmdline as one PE; strictly stronger than
  signing vmlinuz alone (Margine's initramfs is unsigned today), but the bootc/ostree
  tooling isn't there yet.
- **Vanilla OS (ABRoot)**: sticks to the distro-signed kernel within its A/B image scheme;
  custom-kernel users are on their own, same trade as stock-kernel atomic distros.

The decision table reduces to: *who signs the kernel, and who has to click through firmware to
trust it?* MOK is the only option where a third-party builder signs once and every user trusts
it with a single physical-presence confirmation: no shim review, no firmware key surgery, no
Secure Boot off.

**Recap:** sign everything at build (`sbsign` for vmlinuz, `sign-file` for every `.ko`, keys as
BuildKit secrets); ship `MOK.der` in `/usr`; stage enrollment from the installer *before* the
first boot of the untrusted kernel, with a marker-gated oneshot service as the rebase/missed-
prompt fallback; make the passphrase short, public, and documented. Chapter 5 builds on the
enrolled state: LUKS2, TPM2 PCR policy, and why PCR 7 only makes sense after this chapter's
work is done.


---

# 5. Shipping desktop opinion as data

An atomic image is more than packages: most of what makes a distro *feel* like a distro is configuration: default settings, extensions, boot splash, logos, one-command workflows. The rule in this chapter: ship opinion as **data in `/usr` and `/etc`**, baked at image build, never as imperative first-boot scripts mutating user state behind the user's back. Margine's payload splits into five mechanisms: gschema overrides + dconf databases, extensions installed (and patched) at build, systemd drop-ins, ujust recipes, and Plymouth/branding assets.

## 5.1 Defaults: gschema overrides vs the dconf distro database

GNOME has two layered "vendor default" systems, and you need both.

**gschema overrides** patch the *compiled schema defaults*. They are read by anything that resolves a key through the global schema source. Files load in lexicographic order. Margine names its file `zz1-*` so it sorts after Bluefin's `zz0-bluefin-modifications`:

```ini
# margine-image/build_files/30-gnome-defaults/install.sh (heredoc, trimmed)
# /usr/share/glib-2.0/schemas/zz1-margine.gschema.override
[org.gnome.shell]
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'bazaar-integration@kolunmi.github.io', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gradia-integration@alexandervanhee.github.io', 'gsconnect@andyholmes.github.io', 'search-light@icedman.github.com', 'o-tiling@oliwebd.github.com', 'hide-cursor@elcste.com', 'caffeine@patapon.info']
favorite-apps=['app.zen_browser.zen.desktop', 'org.mozilla.Thunderbird.desktop', 'org.gnome.Nautilus.desktop', 'io.github.kolunmi.Bazaar.desktop', 'org.gnome.Ptyxis.desktop']

[org.gnome.desktop.interface]
accent-color='yellow'

[org.gnome.desktop.wm.preferences]
num-workspaces=10
focus-mode='sloppy'
auto-raise=false
```

Practical effect: these are *defaults*, not settings. The user's dconf still wins, and `gsettings reset` returns to *your* value, not GNOME's. Overrides only take effect after `glib-compile-schemas /usr/share/glib-2.0/schemas` (the install script runs it at the end).

**dconf system databases** sit below the user's database in the read path. Configured by a profile plus keyfile directories:

```sh
# margine-image/build_files/30-gnome-defaults/install.sh:94-107
mkdir -p /etc/dconf/db/distro.d/locks /etc/dconf/profile
install -m 0644 /ctx/30-gnome-defaults/dconf/* /etc/dconf/db/distro.d/

if [[ ! -f /etc/dconf/profile/user ]]; then
  cat > /etc/dconf/profile/user <<'PROFILE'
user-db:user
system-db:local
system-db:site
system-db:distro
PROFILE
elif ! grep -qxF 'system-db:distro' /etc/dconf/profile/user; then
  printf '\nsystem-db:distro\n' >> /etc/dconf/profile/user
fi
dconf update
```

The profile is a read stack, top wins: `user` > `local` > `site` > `distro`. `local`/`site` are reserved for the machine admin and site policy (the Fedora convention), `distro` is yours. `dconf update` compiles `distro.d/*` keyfiles into the binary `/etc/dconf/db/distro`. Without it nothing applies. The `locks/` subdirectory (created above, currently unused for `distro`) is where you list key *paths* that the user database may NOT override. Margine uses a lock in the GDM database (§5.8).

### Why extensions get dconf keyfiles, not gschema overrides

```sh
# margine-image/build_files/30-gnome-defaults/install.sh:88-93
# Extension preferences use dconf keyfiles rather than gschema
# overrides. GNOME Shell Extension.getSettings() loads an extension's
# local schemas/ directory ahead of the global schema source, so global
# gschema override defaults for org.gnome.shell.extensions.* can be
# shadowed at runtime. dconf defaults are keyed by path and apply to
# the actual settings backend the extension reads.
```

Practical effect: a `zz1` override for `org.gnome.shell.extensions.dash-to-dock` may simply never be consulted, because the extension compiles and loads its *own* copy of the schema from its `schemas/` directory. dconf keyfiles are keyed by path (`[org/gnome/shell/extensions/dash-to-dock]`), so they hit the backend no matter which schema object the extension instantiated. Example keyfile:

```ini
# margine-image/build_files/30-gnome-defaults/dconf/01-margine-dash-to-dock (trimmed)
[org/gnome/shell/extensions/dash-to-dock]
# Anti-collision with Margine's Super+1..0 workspace binds.
hot-keys=false
dash-max-icon-size=36
dock-fixed=true
running-indicator-style='DOTS'
transparency-mode='DYNAMIC'
```

Even ad-hoc user keybindings ship this way: relocatable schemas (`custom-keybindings/...`) have no fixed schema to override, but a dconf path always works:

```ini
# margine-image/build_files/30-gnome-defaults/dconf/07-margine-custom-keybindings
[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/margine-smile/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/margine-smile]
name='Smile emoji picker'
binding='<Super>period'
command='flatpak run it.mijorus.smile'
```

> **Lesson: the index-vs-pixels bug (search-light `border-radius`).**
> *Symptom:* the dconf default for search-light applied `background-color` fine, but the corner rounding never appeared, with no error anywhere.
> *Root cause:* the key is named like a pixel value but the extension treats it as an **array index**: `extension.js` does `rads[Math.floor(value)]` over `rads = [0,16,18,20,22,24,28,32]`, and an `if (r)` guard silently drops `undefined`. The shipped `30.0` hit `rads[30]`.
> *Fix:* read the extension source before writing "obvious" values; the keyfile now documents the encoding:
> ```ini
> # margine-image/build_files/30-gnome-defaults/dconf/02-margine-search-light:8-15
> # border-radius is NOT pixels: the extension uses it as an INDEX into
> # rads = [0, 16, 18, 20, 22, 24, 28, 32] px, extension.js does
> # rads[Math.floor(value)] and the `if (r)` guard silently drops
> # out-of-range values (the old 30.0 hit rads[30] = undefined, ...)
> # The prefs UI slider is 0..7. 7.0 = 32 px = maximum rounding.
> border-radius=7.0
> ```
> Generic rule: extension settings have no validation layer: dconf accepts any value of the right GVariant type, and bad values fail silently at render time. CI sentinel checks (Margine's build validator asserts `border-radius=7` is present in the image) catch regressions of the file, not of the semantics.

A second silent trap, documented inline in `zz1`: clearing keys to `@as []` expecting a later script to restore them. Margine once cleared `switch-applications`/`switch-windows` in the override, assuming `configure-gnome-keybindings` would re-bind them. It intentionally doesn't, so Alt+Tab was dead on fresh installs. Defaults files are append-only opinion; don't use them to "make room" for scripts.

## 5.2 GNOME extensions: build-time install, downstream patches

Margine originally installed extensions per-user at first login. That failed three ways (race with `flatpak-preinstall.service` network priority; a user-side copy *shadowing* Bluefin's newer system copy of search-light; silent whole-extension disable on shell-version mismatch). The fix is the Bluefin/Bazzite pattern: bake every extension into `/usr/share/gnome-shell/extensions/` at image build, enable via the gschema override above, and never touch `~/.local`.

```sh
# margine-image/build_files/build-margine-extensions.sh:56-57,102-117 (trimmed)
OTILING_VERSION="v2.8.8"
OTILING_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/o-tiling@oliwebd.github.com-${OTILING_VERSION}.zip"

install_otiling() {
  local target="${EXT_DIR}/o-tiling@oliwebd.github.com"
  rm -rf "${target}"; mkdir -p "${target}"
  curl -fL --retry 5 --retry-delay 10 -o /tmp/otiling.zip "${OTILING_URL}"
  extract_zip /tmp/otiling.zip "${target}"
  if [[ -d "${target}/schemas" ]] && compgen -G "${target}/schemas/*.xml" > /dev/null; then
    glib-compile-schemas --strict "${target}/schemas"
  fi
}
```

Pinned release zips make bumps reviewable PRs. For EGO-only extensions, resolve the compatible version against the shell actually in the image:

```sh
# margine-image/build_files/build-margine-extensions.sh:90,124-127
GNOME_SHELL_MAJOR="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
version_tag="$(curl -fsSL --retry 5 --retry-delay 10 \
  "https://extensions.gnome.org/extension-info/?uuid=${HIDECURSOR_UUID}&shell_version=${GNOME_SHELL_MAJOR}" \
  | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("version_tag",""))')"
```

Querying EGO's `extension-info` endpoint with the *image's* shell major version avoids the classic "extension disabled after rebase" mismatch. Note also what the script deliberately does **not** install: search-light, because Bluefin already bakes it system-wide from git master. A second copy re-creates the shadow bug.

> **Lesson: transient `dnf` installs in build scripts cascade.**
> *Symptom:* `scxctl`/`scx-scheds` vanished from built images, twice, after unrelated "cleanup" changes.
> *Root cause:* the script did `dnf5 install unzip jq` … `dnf5 remove jq; dnf5 autoremove`. `autoremove` reaped scx-scheds; after removing the autoremove, `dnf5 remove jq` *still* cascaded: `scx-tools-git` declares `Requires: jq`, so removing jq pulled 16 packages including scx-scheds.
> *Fix:* zero dnf operations. Python stdlib does JSON and zip:
> ```sh
> # margine-image/build_files/build-margine-extensions.sh:93-100
> extract_zip() {
>   local zipfile="$1" target="$2"
>   python3 -c "
> import zipfile, sys
> zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
> " "$zipfile" "$target"
> }
> ```
> Generic rule: in a derived image you don't own the dependency graph; `dnf remove` of a "build tool" can take base features with it. Prefer tools already in the base, or contain installs to a single stage that removes exactly what it added (as `45-wsf` does with meson/ninja).

### Patching an upstream extension downstream

Owning the bytes in `/usr` means you can carry mitigations the upstream hasn't merged.

> **Lesson: search-light unrealize-while-mapped shell crash.**
> *Symptom:* launching an app from the search overlay SIGABRTs the entire GNOME Shell on Wayland (session dies), and GNOME's crash protection then sets `disable-user-extensions=true`. One crash silently turns off *all* extensions.
> *Root cause:* `Clutter:ERROR:clutter-actor.c:1989 ... assertion failed: (!clutter_actor_is_mapped (self))`: search-light's `_release_ui()` calls `remove_child()` on the entry while the overlay is still mapped; Clutter 18's stricter unrealize asserts. Reproduced via coredump + journal; upstream issues #82/#133 open, no fix in v101.
> *Fix:* one-line build-time patch (unmap before detaching) applied idempotently and soft-failing:
> ```python
> # margine-image/build_files/build-margine-extensions.sh:203-220 (embedded Python)
> old = """  _release_ui() {
>     if (this._entry) {
>       if (this._entry.get_parent()) {
>         this._entry.get_parent().remove_child(this._entry);"""
> new = """  _release_ui() {
>     if (this._entry) {
>       if (this._entry.get_parent()) {
>         this._entry.hide(); // margine: unmap before detach (Clutter 18 unrealize assert)
>         this._entry.get_parent().remove_child(this._entry);"""
> if old not in s:
>     sys.exit(1)
> open(p, "w").write(s.replace(old, new, 1))
> ```
> Design points worth copying: match the **exact surrounding context** so the patch targets only the crash site (not the show-path occurrence of the same call); `grep` for the marker comment first so re-runs are no-ops; and if the pattern is gone (base image bumped the extension), **log and continue** rather than fail the build. A mitigation must not become load-bearing.

## 5.3 systemd user drop-ins as integration glue

Margine ships `wayland-scroll-factor` (WSF), an `LD_PRELOAD` interposer on libinput getters that scales touchpad scroll/pinch in GNOME Wayland. It's built from a pinned, checksummed tarball at image build (`meson setup build --prefix=/usr --libdir=lib64`, with `CCACHE_DISABLE=1` because the base image's ccache PATH shim breaks in the build container). The interesting part is *activation*: instead of upstream's per-user `~/.config/environment.d/` + logout, the image injects the preload into the gnome-shell unit itself via a template drop-in:

```sh
# margine-image/build_files/45-wsf/install.sh:58-66 (trimmed)
# Pre-enable the preload for gnome-shell system-wide. ... inject
# LD_PRELOAD only into the gnome-shell unit (template drop-in covers
# every org.gnome.Shell@<instance>.service, including the GDM greeter,
# where it is a no-op). The library scrubs itself from LD_PRELOAD after
# loading, so gnome-shell's children do not inherit it.
install -Dm0644 /ctx/45-wsf/margine-wsf-preload.conf \
  /usr/lib/systemd/user/org.gnome.Shell@.service.d/50-margine-wsf.conf
```

```ini
# margine-image/build_files/45-wsf/margine-wsf-preload.conf
[Service]
Environment=LD_PRELOAD=/usr/lib64/wayland-scroll-factor/libwsf_preload.so
```

Why this pattern is good glue:

- **Template drop-in** (`org.gnome.Shell@.service.d/`) applies to every instance, session and GDM greeter, with zero per-user state.
- **Scoped**: only gnome-shell gets the preload (the library is additionally process-guarded and self-scrubs from `LD_PRELOAD`, so children don't inherit it). Compare with setting it in `environment.d`, which leaks into every user process.
- **Safe default**: factor 1.0 is a mathematical no-op, so baking it on is inert until the user runs `wsf set`.
- **Layered opt-out**: unit-level `Environment=` beats the user-manager environment (no double-load from a per-user `wsf enable`), and `/etc` drop-ins beat `/usr` ones, `ujust wsf-preload off` writes `/etc/systemd/user/org.gnome.Shell@.service.d/99-margine-wsf-off.conf` with `UnsetEnvironment=LD_PRELOAD`, never touching the image file.

This `/usr` ships policy, `/etc` overrides policy split is the systemd-native way to make image opinion user-reversible without mutating the image.

## 5.4 ujust recipes: the user-facing API

Anything opt-in gets a `ujust` recipe (Universal Blue's `just` wrapper). One non-obvious constraint when deriving from Bluefin:

```sh
# margine-image/build_files/60-ujust-services/install.sh:11-23 (trimmed)
# Bluefin's /usr/share/ublue-os/just/00-entry.just hardcodes the list
# of imported recipe files. The ONLY one declared as optional is
# 60-custom.just (via `import?`) — that's the documented extension
# point for downstream distros. Files dropped under any other name
# (e.g. 99-margine.just) are simply ignored by `ujust --list`.
install -Dm0644 /ctx/60-custom.just /usr/share/ublue-os/just/60-custom.just
```

Margine's recipe set defines the supported surface:

- `margine-bootstrap [MODE]`, runs the idempotent `configure-*` chain (home layout, keybindings, appearance, default apps, app folders, Zen browser) and drops `~/.config/margine/bootstrapped` so the XDG-autostart first-login trigger doesn't refire. User dconf/HOME state is the one thing the image can't bake, the recipe is the explicit, re-runnable bridge.
- `margine-gaming` / `margine-gaming-native` (+ `-remove`), opt-in layers; the recipe text honestly states the rpm-ostree trade-off ("+30-60s per `bootc upgrade`, occasional file conflicts") before the prompt. Each install recipe has a symmetric remove recipe.
- `margine-scheduler [MODE]`, the sched_ext switcher (next section).
- `wsf-preload on|off|status` — the `/etc` drop-in toggle from §5.3.

```just
# margine-image/build_files/60-custom.just:394-419 (trimmed)
      default|stop|off)
        echo "Stopping scx_loader.service; kernel default (BORE on Margine) takes over."
        stop_loader
        ;;
      *)
        if ! scheduler_supported "$MODE"; then
          echo "Unknown or unsupported scheduler: $MODE"
          list_schedulers | sed 's/^/  - /'
          exit 1
        fi
        ensure_loader
        if scheduler_running; then
          scxctl switch --sched "$MODE"
        else
          scxctl start --sched "$MODE"
        fi
```

The recipe validates against `scxctl list` (whatever the shipped scx-scheds actually supports) instead of a hardcoded scheduler list, so a package bump can't desync the CLI from reality.

### The recipe surface, mid-2026

`60-custom.just` is the whole user-facing API, and it has grown a few opt-in layers and safety helpers since the first cut:

- **AI layer, `ujust margine-ai` / `margine-ai-remove`.** Installs **Alpaca** (`com.jeffser.Alpaca`), a Flatpak GUI that bundles its own Ollama backend, the AI layer is **100% Flatpak and lays nothing native** on the host (deliberate: the base stays lean, AI is sandboxed and fully removable). GPU acceleration is wired Flatpak-side, _not_ by layering: the recipe detects the GPU and offers the `com.jeffser.Alpaca.Plugins.AMD` ROCm extension for AMD, points APUs at Ollama's Vulkan backend (with an `HSA_OVERRIDE_GFX_VERSION=11.0.0` note for `gfx110x`), and explains the NVIDIA/CPU paths. (The base already ships AMD ROCm + Mesa Vulkan inherited from Bluefin, but a Flatpak sandbox can't reach the host ROCm, hence the in-sandbox plugin.) The installed Flatpak refs are CI-validated against Flathub (§9.11).
- **Safe disk/login helpers — `ujust margine-tpm-unlock` / `margine-autologin`.** Both are designed to be unfootgunnable. `margine-tpm-unlock enable` auto-detects the LUKS device backing root, **refuses to enroll unless a passphrase/recovery keyslot will survive** (the TPM can never become the sole key), only ever wipes the `tpm2` slot, confirms before mutating, and post-verifies; `status`/`disable` round it out. `margine-autologin on|off|status` edits `/etc/gdm/custom.conf` idempotently (preserves other keys, BOM- and multi-`[daemon]`-safe, timestamped backup, SELinux relabel) and never selects root or a system account. Both were authored and hardened through an adversarial review loop before shipping.
- **Freshness from the machine, `ujust margine-status` / `margine-update`.** The on-host counterpart to the `/status` page (§9.9): `margine-status` compares the booted deployment to the latest `:stable` and prints the Fedora → Bluefin → Margine chain plus the running kernel (`uname -r`, the only place the real booted kernel is knowable); `margine-update` stages the latest image and reboots.

## 5.5 tuned profiles + the scheduler picker

Margine ships the CachyOS kernel (BORE as default CPU scheduler) plus `scx-scheds`, with `scx_loader.service` **disabled**, sched_ext is opt-in. Two integration layers sit on top.

**tuned profiles** wrap the stock Fedora profiles and add a hook that nudges scx only if the user already opted in (Bazzite's pattern):

```ini
# margine-image/build_files/system_files/usr/lib/tuned/profiles/balanced-margine/tuned.conf
[main]
include=balanced
summary=Optimize balanced, flip scx scheduler mode via scxctl when scx is opt-in

[script]
script=script.sh
```

```sh
# .../balanced-margine/script.sh
case "$1" in
  start)
    if systemctl is-active --quiet scx_loader.service 2>/dev/null; then
      scxctl switch -m auto >/dev/null 2>&1 || true
    fi
    ;;
esac
exit 0
```

`include=` means you inherit all of Fedora's tuning and only add the delta; the `is-active` guard keeps the profile a strict no-op for users who never enabled scx. Same pair exists for `powersave-margine` and `throughput-performance-margine`.

**The GUI picker** is a zenity radiolist over `scxctl list`, pre-selecting the currently running scheduler, then delegating to the ujust recipe in a visible terminal:

```sh
# margine-image/build_files/system_files/usr/libexec/margine/scheduler-picker:105-122 (trimmed)
choice="$(
  zenity --list --radiolist \
    --title="$APP_NAME" \
    --text="Choose the active sched_ext scheduler." \
    --column="" --column="Scheduler" --column="Notes" \
    --print-column=2 \
    "${rows[@]}"
)" || exit 0

if command -v ptyxis >/dev/null 2>&1; then
  printf -v quoted_choice '%q' "$choice"
  ptyxis -- bash -lc "ujust margine-scheduler $quoted_choice; echo; read -rp 'Premi Invio per chiudere... '"
else
  ujust margine-scheduler "$choice"
fi
```

GUI and CLI funnel into the same recipe, one code path to test. The launcher additionally exposes every scheduler as a **desktop Action** (right-click quick picks on the dock/grid icon):

```ini
# margine-image/build_files/system_files/usr/share/applications/margine-scheduler.desktop (trimmed)
[Desktop Entry]
Name=Margine CPU Scheduler
Exec=/usr/libexec/margine/scheduler-picker
Actions=lavd;bpfland;rusty;flash;cosmos;rustland;off;status;

[Desktop Action lavd]
Name=Switch to scx_lavd (low-latency, gaming-tuned)
Exec=ptyxis -- bash -c "ujust margine-scheduler lavd; read -rp \"Premi Invio per chiudere... \""
```

## 5.6 Plymouth: a script theme with a working LUKS prompt

The theme is three files plus one plugin package:

```sh
# margine-image/build_files/50-branding/install.sh:78-97 (trimmed)
# Bluefin DX ships Plymouth core but not the script plugin.
dnf -y install plymouth-plugin-script

mkdir -p /usr/share/plymouth/themes/margine
for f in margine.plymouth margine.script watermark.png ; do
  cp "/ctx/50-branding/assets/plymouth/${f}" "/usr/share/plymouth/themes/margine/${f}"
done
plymouth-set-default-theme margine
```

```ini
# build_files/50-branding/assets/plymouth/margine.plymouth
[Plymouth Theme]
Name=Margine
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/margine
ScriptFile=/usr/share/plymouth/themes/margine/margine.script
```

Plymouth lives in the initramfs, so after `plymouth-set-default-theme` the build regenerates initramfs for every kernel with `dracut --force --no-hostonly --add ostree --kver "$kver" .../initramfs.img`, `--no-hostonly` because the image must boot any hardware, `--add ostree` because without that module switch-root fails on bootc systems, and the output path `/usr/lib/modules/<kver>/initramfs.img` is what bootc expects.

> **Lesson, a `script` theme has NO built-in LUKS prompt (`SetDisplayPasswordFunction` is REQUIRED).**
> *Symptom:* on encrypted installs, boot appears to hang on the splash. Pressing Esc (details view) reveals a passphrase prompt that was there all along.
> *Root cause:* verified in Plymouth 24.004.60 source, the script plugin advertises the display-password hook unconditionally (`src/plugins/splash/script/plugin.c:497`) but only runs whatever the theme registered via `Plymouth.SetDisplayPasswordFunction`; the slot starts null and calling a null object is a silent no-op (`script-lib-plymouth.c:128`, `:362`). The "built-in default prompt" only exists for the two-step (spinner/bgrt) and details plugins.
> *Fix:* the theme renders its own dialog with `Image.Text` and registers all three callbacks:
> ```js
> // build_files/50-branding/assets/plymouth/margine.script:132-158 (trimmed)
> fun display_password_callback (prompt, bullets)
>   {
>     dialog_show(prompt);
>     if (bullets > ENTRY_COLUMNS) bullets = ENTRY_COLUMNS;
>     bullet_text = "";
>     for (i = 0; i < bullets; i++) bullet_text += "* ";
>     dialog_set_input(bullet_text);
>   }
> Plymouth.SetDisplayPasswordFunction(display_password_callback);
> Plymouth.SetDisplayQuestionFunction(display_question_callback);
> Plymouth.SetDisplayNormalFunction(display_normal_callback);
> ```
> `Image.Text` needs `label-freetype.so` + a font; `plymouth-populate-initrd` packs both unconditionally, so no extra assets.

> **Lesson, the initramfs runs in the C locale; multi-byte UTF-8 breaks text rendering.**
> *Symptom:* the password bullets rendered as mangled `â` characters on a real encrypted boot (fine in casual testing).
> *Root cause / fix, from the theme itself:*
> ```js
> // build_files/50-branding/assets/plymouth/margine.script:58-61
> // NB: the bullet is ASCII "*", NOT U+2022 "•": the initramfs runs in the
> // C/POSIX locale (no locale data packed), label-freetype decodes glyphs
> // with mbrtowc which fails on multi-byte UTF-8 there, U+2022 would
> // render as a mangled "â" on the real encrypted boot.
> ```
> Generic rule: anything that runs pre-pivot (Plymouth themes, dracut hooks, emergency shells) must assume ASCII-only.

## 5.7 Branding: the paths GNOME actually reads

Branding a derived image is mostly knowing which hardcoded filenames each component consumes, and that your *base* image already replaced some of them with its own art.

- **About panel system logo**: `os-release` `LOGO=margine-logo` resolved via icon theme → install `/usr/share/icons/hicolor/scalable/apps/margine-logo.svg` (+ `/usr/share/pixmaps/margine-logo.png` fallback), then `gtk-update-icon-cache`.
- **About panel distributor wordmark**: Fedora's gnome-control-center build hardcodes two pixmap *filenames* at compile time. Deleting them shows no logo; the move is to overwrite them in place:

```sh
# margine-image/build_files/50-branding/install.sh:182-190 (trimmed)
# fedora_logo_med.png is shown on LIGHT backgrounds (so a dark-text
# wordmark); fedora_whitelogo_med.png on DARK backgrounds (white-text
# wordmark). gnome-control-center scales these 1200×300 transparent PNGs
# to the About-panel logo slot.
retry_curl_strict ".../margine-wordmark-dark.png"  /usr/share/pixmaps/fedora_logo_med.png
retry_curl_strict ".../margine-wordmark-light.png" /usr/share/pixmaps/fedora_whitelogo_med.png
```

Note the asset choice: a wordmark (wide, transparent) for the wordmark slot, an earlier revision put the square logo there and it rendered badly. Also note the inverted naming: `fedora_logo_med` = light theme = dark-text art.

- **Leftover base-image art**: Bluefin overlays `/usr/share/icons/hicolor/scalable/places/fedora-logo-sprite.svg` (unowned by any RPM), Margine overwrites it with an empty 296×296 SVG so icon-name lookups render nothing, and deletes nine other `fedora-*` pixmaps wholesale.
- **GDM greeter logo**: disabled rather than replaced (the available asset was a 2400×700 banner that GDM scaled to near-fullscreen). This is also Margine's one real **dconf lock**, the user database physically cannot re-set the key:

```sh
# margine-image/build_files/50-branding/install.sh:201-208
cat > /etc/dconf/db/gdm.d/02-margine-logo <<'EOF'
[org/gnome/login-screen]
logo=''
EOF
mkdir -p /etc/dconf/db/gdm.d/locks
cat > /etc/dconf/db/gdm.d/locks/02-margine-logo <<'EOF'
/org/gnome/login-screen/logo
EOF
```

GDM uses its own profile (`/etc/dconf/profile/gdm` → `system-db:gdm`), so greeter background/logo overrides live in `gdm.d`, not `distro.d`. Everything in this section is asserted by the CI first-boot-asset validator (chapter on CI), branding regressions fail the build, not the user.

## Alternatives & other distros

**Desktop defaults:**
- gschema overrides only (`zz0-bluefin-modifications`), Bluefin/Aurora; simplest, but loses to extension-local schemas and can't lock keys.
- dconf system DB + locks, RHEL/corporate GNOME standard; Margine's choice for extensions; heavier (needs `dconf update` and a profile).
- Patch upstream defaults in the schema XML itself, some spins; survives nothing, don't.
- Home-manager/NixOS `dconf.settings`, declarative per-user, but manages *user* state, not vendor defaults.
- KDE distros (Bazzite-KDE, Aurora… via `kreadconfig`/look-and-feel packages), entirely different mechanism; settings as INI files in `/etc/xdg`.

**Extensions:**
- Bake into `/usr/share/gnome-shell/extensions` at build, Bluefin, Bazzite, Margine; robust, but you own update cadence and compat patches.
- RPM-packaged extensions from Fedora repos, Silverblue stock; only covers a small curated set.
- Per-user install at first login (EGO download), Margine's abandoned v1; races, shadowing, silent shell-version failures.
- No extensions at all, openSUSE Aeon ("just GNOME"); zero maintenance, zero opinion.

**Opinion-as-recipes (user-facing API):**
- ujust, Universal Blue family (Bluefin, Bazzite, Aurora, Margine); discoverable `ujust --list`, recipes are plain shell.
- GUI control center (Bazzite Portal / yafti first-boot picker), friendlier, more code to maintain.
- NixOS, options system replaces recipes entirely; "opt-in" = flip a module option and rebuild.
- Vanilla OS, first-setup wizard + `abroot`/apx for layering equivalents.

**Scheduler/power integration:**
- tuned + scxctl hook, Bazzite (originator of the pattern), Margine; scx opt-in.
- ppd (power-profiles-daemon) only, Silverblue/Aeon stock; no sched_ext story.
- Always-on scx with a default scheduler, CachyOS (the distro); great defaults, less conservative.
- GameMode per-process governor flips, complementary; Margine ships it for the gaming layer.

**Boot splash:**
- script-plugin custom theme, Margine; full control, you must implement the password dialog (see Lesson).
- spinner/BGRT (firmware logo + spinner), Fedora default, Silverblue, Bluefin; zero effort, built-in prompts, weak branding.
- two-step themed (Bazzite's themed spinner), middle ground; password rendering built in.
- No Plymouth (console boot), server images, ChimeraOS (boots straight to Steam Big Picture).

**Branding:**
- Overwrite hardcoded pixmap paths + os-release LOGO, Margine, Bazzite; fights the base image's own branding layer (you must strip it too).
- Fork the `fedora-logos`/`system-logos` package, openSUSE (`branding-openSUSE` packages do this properly); cleanest but you maintain an RPM.
- Leave Fedora branding intact, many personal images; honest, but users can't tell what they're running.


---

# 6. Application payload: Flatpaks and the offline-docs module

The OCI image owns `/usr`. Apps live in `/var/lib/flatpak`, and ostree/bootc reset `/var` per deployment: anything you put there in the Containerfile is silently absent on the installed system. So "shipping apps" in a bootc distro is really a question of *when and through which channel `/var/lib/flatpak` gets populated*. Margine uses three tiers plus one supporting subsystem (system Flatpak overrides), and the same machinery powers the offline documentation mirror.

## 6.1 Three delivery tiers

| Tier | Mechanism | When the user gets the app | Cost |
|---|---|---|---|
| **BAKE** (~29 apps: browser, mail, office, GNOME suite) | `flatpak install` into the *installer image* at OCI build time, then Anaconda `%post --nochroot` rsync into the target's `/var/lib/flatpak` | Already on the desktop at first login | +5–10 min Anaconda "Running post-install scripts", 0 GB extra ISO logic |
| **DEFER** (heavy creative: GIMP, Inkscape, darktable, OBS, Reaper) | `/usr/share/flatpak/preinstall.d/*.preinstall` + `flatpak-preinstall.service` at first boot | 5–15 min after first boot, with desktop notifications | Background bandwidth; needs UX feedback |
| **On-demand** (gaming stack) | `ujust margine-gaming` recipe | When the user asks | Interactive; may layer host RPMs |

The split criterion is stated in the build script itself:

```bash
#   BAKE (kickstart %post --nochroot at install time, ~22 apps):
#     Browser, mail, password, office, image+pdf+video viewer,
#     GNOME productivity suite. Apps the user expects to find ALREADY
#     INSTALLED on the desktop the first time they log in.
#
#   DEFER (.preinstall files + flatpak-preinstall.service at first
#   boot, ~12 apps):
#     Heavy creative apps (GIMP, Inkscape, darktable, OBS, Reaper,
#     ...) the user doesn't need in the first 10 min after first
#     login. flatpak-preinstall.service downloads them in background.
```
*`margine-image/build_files/20-flatpaks/install.sh` (lines 14–28).* The boundary is UX, not size alone: "first 10 minutes after login" defines BAKE.

## 6.2 One list, three consumers

The BAKE list is a single flat file, `installer/flatpaks-base`, read by (a) the OS-image build (copied to `/usr/share/margine/installer-flatpaks-base` for the kickstart), (b) the BIB installer-image build (`installer/build.sh`), and (c) the Titanoboa live-env build (`live-env/src/flatpaks`). One edit propagates everywhere.

```
app.zen_browser.zen
org.mozilla.thunderbird_esr
com.bitwarden.desktop
org.libreoffice.LibreOffice
...
# fm.reaper.Reaper — INTENTIONALLY EXCLUDED from BAKE 2026-06-05:
# Reaper's apply_extra script downloads the proprietary binary at
# install time, which fails inside the podman build container with
# "apply_extra script failed, exit status 256"
...
com.github.tchx84.Flatseal         # Flatpak permissions GUI
io.github.flattool.Warehouse       # Flatpak management GUI
```
*`margine-image/installer/flatpaks-base` (trimmed).* Note the two embedded decisions: apps whose `apply_extra` hook downloads proprietary blobs may not survive a container build (Reaper stays DEFER-only), and inline `# comments` are allowed, which caused a real failure, below.

> **Lesson: inline comments become Flatpak IDs.**
> *Symptom:* `flatpak install` fails with `Invalid id #: Name can't start with #` (build #27075455521).
> *Root cause:* `grep -v '^#'` only strips whole-line comments; `Flatseal  # Flatpak permissions GUI` passes `#`, `Flatpak`, `permissions`, `GUI` as literal app IDs.
> *Fix:*
> ```bash
> APPS=$(grep -v '^[[:space:]]*#\|^[[:space:]]*$' "$LIST_PATH" \
>        | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' \
>        | grep -v '^$')
> ```
> *`margine-image/installer/build.sh` (lines 52–54).* Same sed replicated in `live-env/src/build.sh`.

## 6.3 BAKE: build-time install, install-time rsync

### Why not `flatpak install` inside the kickstart?

Margine's first approach ran `flatpak install --system` directly in Anaconda `%post`. It failed silently on a fresh install.

> **Lesson: install-time downloads of a 5 GB set are fragile.**
> *Symptom:* 2026-06-04 fresh install completed "successfully" but the apps were missing.
> *Root cause:* probably `/tmp` tmpfs OOM in the installer environment: the BAKE set is ~5 GB and the installer's `/var` is RAM-backed. Network blips produce the same silent partial result (`--noninteractive` returns 0 on partial failure).
> *Fix:* move the download to OCI build time (the CI runner has real disk). A dedicated **installer image** is built with the Flatpaks already in its `/var/lib/flatpak`, and the kickstart degrades to a pure local rsync. Documented in the kickstart itself:
> ```
> # Previously this %post also did `flatpak install --system` at
> # install time. That failed silently on the 2026-06-04 fresh install
> # (probably /tmp tmpfs OOM in installer env, since the BAKE set is
> # ~5 GB). Switching to installer-image moves that download to build
> # time (CI runner has plenty of disk) so install-time stays fast +
> # reliable.
> ```
> *Originally documented inline in the BIB kickstart (`disk_config/iso-gnome.toml`, now deleted); the same install-time-vs-build-time rationale carries over to `live-env/src/anaconda/post-scripts/install-flatpaks.ks` and ADR-0008 §4.*

### Installing Flatpaks inside a container build

`flatpak install` inside `podman build` needs two environment shims, because bwrap (used by `apply_extra`) expects a real `/root` and a writable `/proc/sys`:

```bash
# Copied straight from Bazzite's installer/build.sh — without these the
# apply_extra step (used by Reaper, Steam, openh264 for binary blobs)
# fails with:
#   F: Unable to provide a temporary home directory in the sandbox:
#      Unable to open path "/var/roothome": No such file or directory
#   bwrap: cannot open /proc/sys/user/max_user_namespaces:
#      Read-only file system
mkdir -p "$(realpath /root)"
mount -o remount,rw /proc/sys

flatpak remote-add --if-not-exists --system flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
...
flatpak install --system --noninteractive --or-update flathub $APPS
```
*`margine-image/installer/build.sh` (lines 21–31, 44–45, 66).* The build also requires `podman build --cap-add sys_admin --security-opt label=disable` (set in `build-disk.yml`): bwrap needs user namespaces.

### The rsync into the target

ostree deployments mount their own `/var`; the kickstart locates the freshly written deployment and copies the populated tree in:

```bash
DEPLOY_DIR=$(ls -d /mnt/sysimage/ostree/deploy/default/deploy/*.0 2>/dev/null | head -1)
...
mkdir -p "$DEPLOY_DIR/var/lib"
rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak "$DEPLOY_DIR/var/lib/"
sync
```
*`margine-image/live-env/src/anaconda/post-scripts/install-flatpaks.ks` (lines 26–40).* This `%post` is deliberately **not** `--erroronfail`: the bake is quality-of-life, and every BAKE app is also in the DEFER list (next section), so a failed rsync degrades to a first-boot download, never a bricked install. `bootc switch` keeps `--erroronfail` because *that* is install-critical.

> **Lesson: copy POSIX xattrs, strip SELinux labels.**
> *Symptom:* baked Flatpaks can fail to launch with AVC denials on the installed system.
> *Root cause:* `rsync -X` copies *all* xattrs, including `security.selinux` labels minted in the installer environment, wrong contexts for the target filesystem.
> *Fix:* Bluefin's verified-in-production incantation: keep `-AX` (ACLs + xattrs, needed by Flatpak's deploy metadata) but exclude the SELinux namespace; ostree's finalize relabels the target correctly:
> ```bash
> rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak "$DEPLOY_DIR/var/lib/"
> ```
> *`install-flatpaks.ks` line 39; rationale in `docs/spec/adr/0008-titanoboa-migration-plan.md` §4.* (The earlier BIB kickstart used plain `-aAXUHK --open-noatime`; the Titanoboa path adopted the filter as the invariant, and that BIB kickstart, `iso-gnome.toml`, has since been deleted.)

One more guard in the Titanoboa live environment: the live session and the installer share `/var/lib/flatpak`, so the baked set is bind-mounted read-only to keep the live user from tainting it before the rsync (`var-lib-flatpak.mount`, `Options=bind,ro`, `live-env/src/build.sh` lines 173–188, Bazzite pattern).

## 6.4 DEFER: declarative first-boot via `preinstall.d`

Flatpak 1.16 introduced an upstream declarative preinstall API: `.preinstall` keyfiles under `/usr/share/flatpak/preinstall.d/` are consumed by `flatpak-preinstall.service` at boot. This lives in `/usr`: image-owned, survives every update, no kickstart involved. Margine generates one file at image build:

```bash
mkdir -p /usr/share/flatpak/preinstall.d
{
  ...
  for app in \
      org.gimp.GIMP \
      org.inkscape.Inkscape \
      org.darktable.Darktable \
      com.obsproject.Studio \
      app.zen_browser.zen \
      ...
      it.mijorus.smile ; do
    echo "[Flatpak Preinstall $app]"
    echo "Branch=stable"
    echo "IsRuntime=false"
    echo
  done
} > /usr/share/flatpak/preinstall.d/margine-defaults.preinstall
```
*`margine-image/build_files/20-flatpaks/install.sh` (lines 72–154, trimmed).* Two design points:

1. **Belt and suspenders:** every BAKE app is *also* listed here. If the install-time rsync silently fails, `flatpak-preinstall.service` catches the gap at first boot (5–15 min wait instead of instant, but never "apps missing"). On a successful BAKE the entries are no-ops: flatpak skips already-installed refs.
2. **The legacy uBlue mechanism is dead:** `/etc/ublue-os/system-flatpaks.list` is *silently ignored* on current Bluefin DX. The build deletes it (`rm -f`, line 162) to prevent confusion. If you derive from a Universal Blue image, target `preinstall.d`, not the old list.

## 6.5 Notify-and-install-later: first-boot UX for DEFER

A background download with no feedback reads as "broken install". Margine ships an XDG autostart notifier that watches `flatpak-preinstall.service` and posts GNOME notifications at start and completion:

```bash
svc_state() {
  local s
  s=$(systemctl is-active flatpak-preinstall.service 2>/dev/null) || true
  [[ -z "$s" ]] && s=unknown
  printf '%s' "$s"
}
...
case "$initial" in
  active|activating|reloading)
    notify-send --app-name="Margine" --icon="org.gnome.Software" --urgency=low \
      --hint=string:desktop-entry:io.github.kolunmi.Bazaar \
      "Margine sta installando alcune app aggiuntive" "..."
    # Poll for completion. Cap at 60 min so we don't sit here forever
    deadline=$(( $(date +%s) + 3600 ))
```
*`margine-image/build_files/system_files/usr/libexec/margine-first-boot-status` (lines 63–92, trimmed).* Idempotent via a `~/.cache/margine/first-boot-notified` marker; if the service already finished before first login, it stays silent. A `failed` final state posts a recovery hint (`systemctl restart flatpak-preinstall.service`).

> **Lesson: `systemctl is-active` on an `activating` unit prints *and* fails.**
> *Symptom:* no notification on the 2026-06-06 fresh install; log shows `unexpected initial state: activating / unknown`.
> *Root cause:* `is-active` exits 3 for `activating` while still printing `activating`. The naive `systemctl is-active ... || echo unknown` therefore yields TWO lines (`activating\nunknown`), which matches no `case` arm.
> *Fix:* capture stdout, ignore the exit code, fall back to `unknown` only when stdout is empty, the `svc_state` helper above.

> **Lesson: GNOME 50+ skips autostart entries with `X-GNOME-Autostart-Phase`.**
> *Symptom:* notifier never ran at login ("non ho visto nessun messaggio", 2026-06-04).
> *Root cause:* gnome-session no longer manages session phases; entries carrying the key are warned about and *skipped entirely*.
> *Fix:* delete the key from the `.desktop` file; see the warning comment in `build_files/system_files/etc/xdg/autostart/margine-first-boot-status.desktop` (lines 12–19).

## 6.6 On-demand: `ujust margine-gaming`

The heaviest payload (Steam, Lutris, Heroic, Bottles, RetroArch + host gamescope/vkBasalt) is not preinstalled at all. A dedicated image variant existed and was retired 2026-06-06; the supported path is **two** interactive recipes, each with a symmetric `-remove`. The default, `ujust margine-gaming`, installs the gaming launchers as Flatpaks system-wide and layers only the two gaming-only RPMs (gamescope + vkBasalt) via rpm-ostree. For maximum Proton/Wine compatibility (anti-cheat, VR, NVIDIA-proprietary + Mesa side-by-side), `ujust margine-gaming-native` instead layers Steam + Lutris + RetroArch as **native RPMs**: the full 32-bit dependency closure is baked into the base image so the layering resolves offline. The Flatpak recipe below is the default path:

```make
flatpak install --system -y --or-update flathub \
    com.valvesoftware.Steam \
    net.lutris.Lutris \
    com.heroicgameslauncher.hgl \
    ...
# gamescope + vkBasalt are the only RPMs strictly gaming-only.
```
*`margine-image/build_files/60-custom.just` (lines 150–162, trimmed).* The recipe prints the trade-off before asking confirmation: layered RPMs branch the deployment from the base OCI image, add ~30–60 s per `bootc upgrade`, and can conflict when upstream relocates a file. Keeping this opt-in keeps the default image unbranched.

## 6.7 System Flatpak overrides

Sandboxed apps cannot see host paths the image wants them to read. Margine writes **system-level** overrides (`/var/lib/flatpak/overrides/`) from root services, and documents per-user overrides in recipes:

- Global, written by `docs-refresh` (next section): `flatpak override --system --filesystem=/var/lib/margine/offline-docs:ro`, grants *every* Flatpak read access to the docs mirror, so it keeps working if the user swaps Zen for another Flatpak browser.
- Per-user, suggested by `ujust margine-gaming`: `flatpak override --user --filesystem=xdg-config/MangoHud:ro com.valvesoftware.Steam`, lets Flatpak Steam read the host MangoHud config.

Rule of thumb: image-level guarantees → `--system` override written by a unit; user preference → `--user` override in a recipe.

## 6.8 The offline-docs module, end-to-end

A self-contained case study tying the above together: ship the project documentation offline, keep it fresh, and make it readable from a sandboxed browser.

### 6.8.1 Build: fetch + rewrite for `file://`

`build-offline-docs.py` crawls a fixed route list from the live docs site and rewrites each page for offline use: strip `<script>`, inline stylesheets, drop preload/prefetch/preconnect hints, and convert links: same-host `/docs/*` links become *relative* paths into the mirror, other root-relative URLs become absolute back to the live site:

```python
ROUTES = [
    "/docs",
    "/docs/what-is-margine",
    ...
    "/docs/faq",
]

def inline_or_remove_link(match, base_url):
    tag = match.group(0)
    rel = (attr_value(tag, "rel") or "").lower()
    href = attr_value(tag, "href")
    if "stylesheet" in rel and href:
        css_url = urljoin(base_url, href)
        css = rewrite_css_urls(fetch_text(css_url), base_url)
        return f'<style data-margine-offline="stylesheet">\n{css}\n</style>'
    if "modulepreload" in rel or "preload" in rel or "prefetch" in rel or "preconnect" in rel:
        return ""
```
*`margine-image/build_files/50-branding/build-offline-docs.py` (lines 17–34, 95–106, trimmed).* It also writes a `manifest.txt` and a `stamp` file (epoch seconds): the stamp is how runtime decides whether the image seed is newer than the runtime mirror.

### 6.8.2 Seed in `/usr` at image build

The branding stage installs the builder itself into the image *and* runs it, so build and runtime use the exact same fetch/rewrite logic:

```bash
install -Dm0755 /ctx/50-branding/build-offline-docs.py /usr/libexec/margine/build-offline-docs
python3 /usr/libexec/margine/build-offline-docs \
  --base-url "$MARGINE_DOCS_BASE_URL" \
  --output-dir "$OFFLINE_DOCS_DIR"   # /usr/share/margine/offline-docs
...
ln -sf ../margine-docs-refresh.timer \
   /usr/lib/systemd/system/timers.target.wants/margine-docs-refresh.timer
ln -sf ../margine-docs-refresh.service \
   /usr/lib/systemd/system/multi-user.target.wants/margine-docs-refresh.service
```
*`margine-image/build_files/50-branding/install.sh` (lines 332–346, trimmed).* Units are enabled with build-time wants-symlinks (no `systemctl enable` at runtime needed). CI validates the seed before push: 14+ `index.html` files, no live JS/CSS, no root-relative links (build.yml validator §A.4.bis).

### 6.8.3 Runtime: seed, grant, refresh

`docs-refresh` (run at boot by the service, periodically by the timer) does three ordered jobs, the first two work offline:

1. **SEED:** if `/var/lib/margine/offline-docs` is missing or its `stamp` is older than the `/usr` seed (e.g. right after a `bootc upgrade` shipped fresher docs), copy the seed into `/var`. Pure local `cp`: the mirror exists seconds after first boot, network or not.
2. **FLATPAK ACCESS:** `flatpak override --system --filesystem="${DOCS_DIR}:ro"`. Without it, a Flatpak browser opening a `file://` URI gets only that single file via the portal: the page renders, every relative link is dead.
3. **REFRESH:** gate on a 10 s `curl ${BASE_URL}/healthz`, then rebuild into `${DOCS_DIR}.new` with the shipped builder and sync in. Offline → keep current copy, exit 0 (not a failure).

The service is a tightly sandboxed oneshot: `ProtectSystem=strict` with writes confined to `StateDirectory=margine` plus `ReadWritePaths=/var/lib/flatpak/overrides` (for step 2), empty `CapabilityBoundingSet`, `ProtectHome`, `NoNewPrivileges` (*`build_files/system_files/usr/lib/systemd/system/margine-docs-refresh.service`*). Deliberately **no `DynamicUser`**: it would relocate state to `/var/lib/private` (0700), unreadable by users' browsers. The timer is monotonic (`OnBootSec=10min`, `OnUnitActiveSec=24h`, `RandomizedDelaySec=1h`) because monotonic timers re-arm at every boot: a laptop that is never up 24 h still refreshes ~10 min after each boot; `Persistent=` would be a no-op since it only applies to `OnCalendar=`.

> **Lesson: never swap a directory a Flatpak sandbox has bind-mounted.**
> *Symptom:* after a background refresh, already-running Flatpak browsers show "File not found" on every docs click until the app restarts.
> *Root cause:* Flatpak bind-mounts the override path *at app start*. The original refresh swapped the directory (`mv` away + `rm -rf` + rename new into place): the sandbox keeps the bind mount on the now-emptied old inode.
> *Fix:* sync **into** the existing directory; rsync replaces each file atomically (tmpfile+rename) and `--checksum` leaves unchanged files untouched, so live readers never see a partial mirror:
> ```bash
> sync_in() {
>   chmod -R a+rX "$1"
>   mkdir -p "$DOCS_DIR"
>   rsync -a --delete --checksum "$1"/ "$DOCS_DIR"/
>   rm -rf "$1"
> }
> ```
> *`build_files/system_files/usr/libexec/margine/docs-refresh` (lines 38–51).*

### 6.8.4 Open: offline-first launcher

`docs-open` (behind `margine-documentation.desktop`) opens the `/var` mirror instantly with no blocking network probe; fallbacks are live site (3 s healthz) then the `/usr` seed:

```bash
if [[ -f "${VAR_DIR}/docs/index.html" ]]; then
  exec xdg-open "file://${VAR_DIR}/docs/index.html"
fi
if curl -fsS --max-time 3 "https://margine.dev/healthz" >/dev/null 2>&1; then
  exec xdg-open "$ONLINE_URL"
fi
if [[ -f "${SEED_DIR}/docs/index.html" ]]; then
  exec xdg-open "file://${SEED_DIR}/docs/index.html"
fi
```
*`build_files/system_files/usr/libexec/margine/docs-open` (lines 25–38).* Why never the `/usr` seed first: Flatpak *reserves* `/usr`: no override can ever expose it to a sandbox, so the seed only works for non-Flatpak browsers. The whole reason the `/var` mirror exists is to give Flatpak browsers a path they are allowed to read.

## Alternatives & other distros

- **Bluefin / Aurora (Universal Blue):** upstream Flatpak `preinstall.d` (Flatpak 1.16) for system apps, plus a Homebrew `system-flatpaks.Brewfile` first-boot path for some apps. Trade-off: zero installer complexity, but everything downloads at first boot, empty desktop for the first minutes. (Margine BAKEs DistroShelf directly instead of going through brew; see the comment in `installer/flatpaks-base`.)
- **Bazzite:** the installer-image bake Margine copied (`install-flatpaks.ks` rsync) plus `ujust install-*` recipes for optional apps. Trade-off: best first-login UX; costs a dedicated installer image build and 5–10 min of Anaconda %post.
- **Fedora Silverblue/Workstation stock:** no preinstall; GNOME Software shows Flathub (filtered) and Fedora Flatpaks. Trade-off: zero image complexity, user assembles everything.
- **GNOME Software deploy lists / `org.gnome.software.first-run` + distro EULA-style curated lists:** declare apps via GSettings/`flatpak-repo` files and let Software prompt. Trade-off: discoverable and consentful, but not unattended.
- **Endless OS:** Flatpaks fully baked into the disk image itself (their `/var` is part of the image build via eos-image-builder). Trade-off: enormous images; perfect offline story, their target market.
- **openSUSE Aeon (MicroOS Desktop):** `tik` installer + first-boot `flatpak install` of a curated set. Trade-off: simple, network-dependent first boot.
- **Vanilla OS (ABRoot):** apps via the `apx`/`vso` layer and Flatpak by default; system images stay app-free. Trade-off: clean separation, no offline-first option.
- **NixOS:** `services.flatpak.enable` plus the community `nix-flatpak` module for declarative app lists; or skip Flatpak and declare everything as Nix packages. Trade-off: fully declarative and reproducible; outside the Flathub runtime-dedup model.
- **ChimeraOS / SteamOS:** the primary app (Steam) is baked into the read-only image; Flatpak relegated to extras on the user partition. Trade-off: appliance-grade for one app, generic apps second-class.
- **For offline docs specifically:** most distros ship none (online wikis), Debian-likes ship `-doc` packages into `/usr/share/doc` (works, but unreadable from sandboxed browsers, exactly the problem Margine's `/var` mirror + system override solves), and GNOME ships Yelp with local Mallard help (no sandbox issue, but a separate authoring toolchain).

## Takeaways

1. `/var` is per-deployment: app payload is a *delivery pipeline* (build-time bake → install-time rsync → first-boot preinstall → on-demand recipe), not a Containerfile line.
2. Make every tier a fallback for the previous one: BAKE apps duplicated in `preinstall.d` turn silent failures into a 15-minute delay instead of missing apps.
3. Downloads belong at build time (CI disk, retries, logs), not install time (tmpfs, silent partial failure).
4. Strip `security.selinux` when rsyncing `/var/lib/flatpak` across environments; let ostree finalize relabel.
5. Anything a Flatpak must read lives outside `/usr`, gets a `--system` override, and must be refreshed *in place*: sandboxes hold bind mounts on the directory inode they started with.


---

# 7. Rechunking: shipping a 14 GB OS as reusable chunks

The build so far produces a working bootc image. This chapter is about making it
*cheap to ship*: how OCI layering interacts with ostree on the client, why the
layers buildah emits are hostile to incremental updates, and how Margine
re-layers the image with `hhd-dev/rechunk` before pushing.

## 7.1 Why naive podman layers churn

Margine's `Containerfile` has four `RUN` stages on top of Bluefin DX
(`/var/home/daniel/dev/margine-image/Containerfile`): the CachyOS kernel swap,
the `build.sh` orchestrator, the extensions bake, and `bootc container lint`.
That yields four Margine-owned layers stacked on Bluefin's own layer set, and
the result is pathological for updates:

- **Layer identity is the digest of the layer tarball, not of the files.**
  A `RUN` that re-executes produces a new tar (new mtimes, new inode order)
  so the layer digest changes even when zero bytes of content changed.
  Every weekly rebuild (the Sunday cron exists precisely to pick up upstream
  Bluefin changes) re-runs all four stages.
- **Layers group files by *when they were written*, not by *how often they
  change*.** The kernel stage layer contains vmlinuz + all modules + a ~300 MB
  initramfs; the `build.sh` layer contains everything from branding PNGs to
  the offline docs mirror. One changed wallpaper invalidates the whole
  multi-GB blob.
- **The base is no better.** `FROM ghcr.io/ublue-os/bluefin-dx:stable` means a
  base rebuild upstream shifts every parent layer digest; the client re-pulls
  them all even though 95% of the file content is identical.

For a ~14 GB image (Margine bakes ~29 Flatpaks into `/var/lib/flatpak`, plus a
second kernel's worth of modules), "every update is a near-full download" is
not acceptable. The fix is to throw away the build-time layer boundaries
entirely and re-cut them along content lines.

## 7.2 What the client does with layers

bootc/ostree clients don't run the container: they import it. Each OCI layer
is unpacked into the ostree object store, where files are content-addressed by
checksum. Two consequences:

1. **Disk dedup is automatic and file-granular**: identical files across
   deployments are stored once, regardless of layer layout.
2. **Network cost is layer-granular**: the client skips any layer blob whose
   digest it already has, and downloads the rest *whole*.

So layer layout doesn't affect disk usage, only download size. The goal of
rechunking is purely: make layer digests stable across releases so the skip
path triggers as often as possible. The same property helps the registry:
`skopeo copy` won't re-upload blobs GHCR already has, so weekly pushes are
mostly no-ops too.

## 7.3 hhd-dev/rechunk: ostree-aware re-layering

[`hhd-dev/rechunk`](https://github.com/hhd-dev/rechunk) (built by antheas for
Bazzite, now used across Universal Blue) takes the *final* filesystem of the
built image and repacks it:

1. Flattens the image and commits it into an ostree repo. The commit
   canonicalizes the tree (zeroed mtimes, normalized ownership, ostree's
   `/usr/etc` factory view). This is what makes output deterministic: same
   file content in, same chunk digests out.
2. Re-splits the commit into ~dozens of layers ("chunks") grouped by RPM
   package ownership and update frequency, instead of by `RUN` boundary. The
   kernel and its modules land in their own chunks; GNOME lands in others;
   rarely-changing Flatpak runtimes in others still.
3. Emits a fresh OCI image with regenerated ostree metadata
   (`ostree.commit`, `ostree.linux`) and whatever labels/version you declare.

Result: a kernel bump changes the kernel chunks and the commit metadata;
everything else keeps its digest from last week, and clients download tens of
MB instead of GB. The chunking is content-addressed, not diff-based. There is
no "previous image" dependency at pull time, just blob digests that happen to
repeat.

### The actual invocation

```yaml
# /var/home/daniel/dev/margine-image/.github/workflows/build.yml (lines 448-464)
      - name: ReChunk image
        id: rechunk
        uses: hhd-dev/rechunk@5fbe1d3a639615d2548d83bc888360de6267b1a2  # v1.2.4
        with:
          ref: ${{ env.IMAGE_NAME }}:${{ steps.metadata.outputs.version }}
          version: ${{ env.CANDIDATE_TAG }}.${{ steps.date.outputs.ymd }}
          labels: |
            org.opencontainers.image.title=${{ env.IMAGE_NAME }}
            org.opencontainers.image.description=${{ env.IMAGE_DESC }}
            org.opencontainers.image.source=https://github.com/${{ github.repository }}
            org.opencontainers.image.url=https://github.com/${{ github.repository }}
            org.opencontainers.image.vendor=${{ github.repository_owner }}
            org.opencontainers.image.licenses=Apache-2.0
            io.artifacthub.package.keywords=${{ env.IMAGE_KEYWORDS }}
            io.artifacthub.package.license=Apache-2.0
            containers.bootc=1
          revision: ${{ github.sha }}
```

Notes on each input:

- `ref`: the locally-built `localhost/margine:candidate.<...>` image from the
  buildah step. Rechunk reads it out of **root** containers-storage
  (`sudo podman create`), which is why the build step runs
  `sudo buildah build` directly instead of a rootless action wrapper:

```yaml
# build.yml (lines 254-256)
      # NOTE: no "Move to root storage" step here — `sudo buildah build`
      # above already writes to /var/lib/containers (root storage),
      # which is exactly where rechunk's `sudo podman create` looks.
```

  (An earlier iteration built rootless and round-tripped through an
  oci-archive to move the image; going direct removed that bounce.)
- `version`: becomes `org.opencontainers.image.version` and the version
  string `bootc status` shows users, e.g. `candidate.20260610`. Date-stamped so
  every build is distinguishable even when content barely changed.
- `labels`: **re-declared in full.** Rechunk writes a fresh manifest; labels
  applied by buildah at build time do not carry over, so anything you want on
  the published image must be listed here. `containers.bootc=1` marks the
  image as bootable-container for tooling (Anaconda, bootc itself).
- `revision`: `org.opencontainers.image.revision=<git sha>`, the exact
  margine-image commit that produced the artifact.

### Pipeline placement

Order in `build_push` matters and is disk-driven (GitHub's ubuntu-24.04
runners have ~14 GiB free by default; the job starts by freeing ~30 GiB with
`ublue-os/remove-unwanted-software`):

1. `buildah build` → local root storage.
2. First-boot asset validation (blocks rechunk on regression: fail at minute
   22, not after a push).
3. SBOM via `podman export` + `syft dir:`, **pre-rechunk**, which is safe:

```yaml
# build.yml (lines 270-272)
      # Pre-rechunk is fine: rechunk doesn't add or remove packages,
      # it only repacks the layer boundaries for delta efficiency. The
      # SBOM describes the same package inventory either way.
```

4. Reclaim the ~14 GB expanded SBOM rootfs: "rechunk needs disk for its own
   staging" (`build.yml` lines 436-438).
5. Rechunk.
6. Push.

### Push and digest capture

The push step copies the rechunked output ref to every tag and captures the
manifest digest for the downstream cosign job (signing by digest, never by
tag):

```yaml
# build.yml (lines 483-492, trimmed)
          for tag in ${{ steps.metadata.outputs.tags }}; do
            sudo skopeo copy --retry-times 3 \
              --dest-creds="${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}" \
              --digestfile=/tmp/digest.txt \
              "${{ steps.rechunk.outputs.ref }}" \
              "docker://${IMG_FULL}:${tag}"
            if [[ -z "$DIGEST" ]]; then
              DIGEST="$(cat /tmp/digest.txt)"
            fi
          done
```

All tags point at the same manifest; the digest from the first copy is reused.
Later, promotion to `:stable` is `skopeo copy --preserve-digests` from the
candidate digest (chapter 8): no rebuild, no re-rechunk, the bytes users pull
are the bytes that smoke-booted.

## 7.4 Rechunk is not just an optimization: composefs canonicalization

Margine learned that rechunk's ostree re-commit changes *boot semantics*, not
just download size. Three real incidents, all from
`docs/spec/lessons-learned/`.

### Lesson: os-release symlink unreadable at switch-root (Fix A wind-down)

- **Symptom:** first boots died in the initramfs with
  `Failed to switch root: os-release file is missing`, even with the file
  present in the image.
- **Root cause:** without rechunk, the published image was not in
  ostree-canonical form and composefs was not fully set up by the time
  switch-root read `/etc/os-release`: the canonical
  `/etc/os-release → ../usr/lib/os-release` symlink couldn't be followed. The
  interim "Fix A" shipped both paths as regular files, which routed around
  exactly one symptom while anything else depending on early `/usr` would
  still fail quietly.
- **Fix:** wiring rechunk into `build.yml` (2026-06-01) re-commits the image
  into ostree-canonical state, so composefs is up before switch-root, same as
  upstream Fedora/Bluefin. The workaround was then deleted and the canonical
  layout restored:

```sh
# /var/home/daniel/dev/margine-image/build_files/10-os-identity/install.sh (lines 80-87)
# /usr/lib/os-release — the canonical location written as a regular file.
printf '%s\n' "$OS_RELEASE_CONTENT" > /usr/lib/os-release
chmod 0644 /usr/lib/os-release

# /etc/os-release — relative symlink to the canonical location.
ln -sf ../usr/lib/os-release /etc/os-release
```

See `2026-06-03-rechunk-and-fixb.md` for the wind-down validation (manual
build → QEMU smoke-boot → merge).

### Lesson: rechunk strips the /etc/passwd seed (Bug 6 v2)

- **Symptom:** Layer A validation confirms 65 entries in `/etc/passwd` at the
  end of buildah; a fresh VM rebased to the *published* image has 1. Boot
  journal fills with `Failed to resolve group 'audio'/'kvm'/'tty'`; TPM and
  audio permissions silently break.
- **Root cause:** rechunk re-commits the image as an ostree-canonical tree and
  in doing so strips the build-time-seeded `/etc/passwd`/`/etc/group` from the
  `/usr/etc` factory view (verified 2026-05-31). ostree's 3-way `/etc` merge
  on rebase then drops every system user except `root` and the human account.
- **Fix:** stop depending on rechunk preserving `/etc` at all: ship an
  idempotent boot-time oneshot that reseeds from the `/usr/lib` factory copies
  when `/etc/passwd` looks stripped:

```sh
# build_files/system_files/usr/lib/systemd/system/margine-seed-etc-passwd.service
# Workaround: ship a systemd oneshot that re-applies the seed at
# every boot, before sysinit. Idempotent (only seeds if /etc/passwd
# is below the entry threshold). Doesn't depend on rechunk preserving
# /etc — it doesn't need to.
```

  The unit ordering itself caused a follow-up incident (an
  `After=local-fs.target` + `Before=systemd-sysusers` cycle that systemd broke
  by disabling `systemd-tmpfiles-setup-dev`, timing out every `.device` unit
  into `emergency.target`). The corrected ordering is baked into the unit with
  the rationale inline:

```ini
# system_files/.../margine-seed-etc-passwd.service (unit body, comment trimmed)
DefaultDependencies=no
# ... DO NOT add After=local-fs.target: it creates an ordering cycle
# through systemd-tmpfiles-setup-dev.service ... (incident 2026-06-01)
After=local-fs-pre.target
Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
ConditionFileNotEmpty=/usr/lib/passwd
```

### Lesson: inherited OCI labels describe the parent, not you

- **Symptom (pre-rechunk era):** boot drops to dracut emergency shell at
  `initrd-switch-root.service`; bootloader entries point at deployment hashes
  that don't exist on disk.
- **Root cause:** `FROM bluefin-dx` inherits *all* of Bluefin's OCI labels,
  including `ostree.linux=<bluefin-kernel-version>`. bootc/rpm-ostree consult
  that label at deploy time to wire the bootloader entry and locate
  `/usr/lib/modules/<label>/`, which no longer existed after the CachyOS
  kernel swap.
- **Fix:** a workflow step rewrote the label from the actual installed kernel
  (`buildah config --label ostree.linux=<kver>`); with rechunk in place the
  ostree metadata labels (`ostree.commit`, `ostree.linux`) are regenerated
  from the re-committed tree, collapsing that whole workaround class. Rule:
  any derived image that materially changes what an inherited label describes
  must overwrite it. Rechunk does this for the ostree ones by construction.

## 7.5 zstd:chunked and partial pulls

Layer reuse is coarse: a chunk either matches or is re-downloaded whole.
`zstd:chunked` is the finer-grained complement: a compression format that
embeds a table of contents (per-file offsets + digests) in zstd skippable
frames. A `containers/storage` client with partial pulls enabled can fetch
only the file ranges it lacks and dedup the rest against local storage; it
also plugs directly into composefs. It stays valid zstd, so unaware clients
just decompress normally (unlike eStargz, which plays the same trick inside
gzip for containerd's lazy-pull snapshotter, a Kubernetes fast-start tool,
not a bootc one).

Margine's `skopeo copy` push does not currently set
`--dest-compress-format zstd:chunked`; the delta efficiency comes from
rechunk's stable layer digests alone. The two compose (rechunk decides *what*
the blobs are, zstd:chunked makes each blob partially fetchable) and
zstd:chunked is the obvious next increment, since Fedora's own bootc base
images and the bootc client stack are converging on it.

## 7.6 Alternatives & other distros

- **hhd-dev/rechunk (Margine, Bazzite, Bluefin, Aurora):** ostree-aware
  re-layering, stable chunks, deterministic output. Cost: an extra ~minutes CI
  step, root storage + disk staging, and it rewrites your manifest (labels
  must be re-declared, `/etc` factory handling can surprise you, §7.4).
- **Plain Containerfile layers (early uBlue images, most homelab bootc
  derivatives):** zero extra tooling, buildah cache works during builds, but
  every release re-downloads the fat `RUN` layers; fine for small images,
  painful past a few GB.
- **`rpm-ostree compose image` / ostree container encapsulate (stock Fedora
  Silverblue, Kinoite, IoT, CoreOS):** composes from a treefile and emits an
  OCI image with built-in package-aware chunking (capped layer count, files
  grouped by change frequency), the same idea as rechunk, but it requires
  owning the compose; it doesn't apply to a `FROM`-based derived build.
- **Flatten to one layer (`podman build --squash`):** simplest possible
  artifact, kills all reuse; every update is a full-image download. Only
  defensible for tiny images or air-gapped one-shot delivery.
- **estargz + stargz-snapshotter (containerd/k8s world):** lazy pulls: start
  before the image finishes downloading. Solves container *startup* latency,
  not OS *update* deltas; no bootc integration.
- **zstd:chunked (Fedora bootc base images, podman ecosystem direction):**
  per-file TOC, partial pulls, composefs-friendly local dedup; complementary
  to rechunk rather than a replacement.
- **ostree static deltas over plain HTTP (Endless OS, pre-OCI Fedora
  Atomic):** server-precomputed binary deltas between commits: excellent
  download efficiency, but you run an ostree repo server instead of reusing
  registry infrastructure.
- **openSUSE MicroOS/Aeon:** no image artifact at all: `transactional-update`
  installs RPMs into a new btrfs snapshot; deltas are RPM-granular, but the
  result is assembled per-machine rather than tested-as-built.
- **Vanilla OS (ABRoot v2):** OCI images applied to A/B root partitions;
  registry-based like bootc but partition-image semantics, without ostree's
  file-level store dedup.
- **ChimeraOS (frzr):** full root images as btrfs-subvolume tarballs from
  GitHub releases; dead simple, every update is a full download.
- **NixOS:** sidesteps the problem: there is no monolithic image; the store
  path is the dedup unit and `nix copy` substitutes only missing derivations.
  Finest granularity of the lot, at the price of an entirely different model.

## 7.7 Takeaways

- OCI layer digests are tar digests; rebuild churn is structural, not a
  buildah bug. Re-layer by content, not by `RUN` order.
- Rechunk earns its place twice in Margine: small weekly downloads, *and*
  ostree-canonical commits that made composefs boot timing match upstream
  (retiring two boot workarounds).
- It is also a manifest rewrite: re-declare labels, re-verify `/etc` factory
  behavior, and keep the smoke-boot gate (chapter 8) downstream of it: the
  artifact you test must be the post-rechunk one, and `--preserve-digests`
  promotion guarantees it's also the one users get.


---

# 8. Supply chain: cosign signing, host verification, and pinning

A bootc distro is a pipeline that turns a Git push into a root filesystem on someone's laptop. Every hop in that pipeline (GitHub Actions runners, third-party actions, the base image, the registry, the pull on the client) is an injection point. This chapter covers how Margine signs what it publishes, how a host verifies what it pulls, and how the CI itself is hardened against tampered dependencies.

The split of responsibilities:

| Layer | Mechanism | Where |
|---|---|---|
| Image authenticity | cosign keypair, signed by digest | `sign` job in `build.yml` |
| Pull-time verification | containers-policy + sigstore attachments | `/etc/containers/policy.json` + `registries.d` on the host |
| Boot chain | MOK-signed kernel + modules (chapter on Secure Boot) | build-time `sbsign`/`sign-file` |
| CI integrity | SHA-pinned actions, ephemeral secrets | every workflow |
| Inventory | SPDX SBOM as OCI 1.1 referrer, itself signed | `build_push` + `sign` jobs |

## 8.1 The cosign keypair

Margine uses key-based cosign signing: an ECDSA P-256 keypair generated once with `cosign generate-key-pair`. Private material never enters Git:

```gitignore
# margine-image/.gitignore
secrets/MOK.key
secrets/cosign.key
secrets/*.pem
```

The public half is committed (`secrets/cosign.pub`) and is the only thing a consumer needs:

```text
# margine-image/secrets/cosign.pub
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqOUib+6SVxWdP5wKCEBkJZEZTmza
rwTaC+nUx1VQmoRmEl9ZwNH4fL46VHhTHfpQukTinXKSkaDWafXupCRygw==
-----END PUBLIC KEY-----
```

The private key lives in two places: a GitHub Actions repository secret (`COSIGN_PRIVATE_KEY`) and an offline local backup. Same dual-custody model as the MOK key. The 2026-06-05 stack audit explicitly weighed this against keyless OIDC and chose to stay key-based for now (see §8.7 for the trade-off table).

## 8.2 Sign by digest, in a separate CI job

`build.yml` is split into `build_push` → `sign` → `notify`. The header comment in the workflow states the rationale:

```yaml
# margine-image/.github/workflows/build.yml (header comment)
# build_push does the heavy work (buildah + rechunk + skopeo push,
# ~25 min). sign is a separate cheap job (~1 min) that signs the
# pushed manifest *by digest* instead of by tag — cosign warns
# against by-tag signing as it's racy.
#
# On a failed sign step, `gh run rerun --failed <run-id>` re-runs
# only the sign job (~1 min) instead of redoing the whole build.
```

Two design decisions here, both worth copying:

**1. Capture the digest at push time.** `skopeo copy --digestfile` records the manifest digest of exactly what was uploaded; the job exports it as an output for the `sign` job:

```bash
# margine-image/.github/workflows/build.yml — "Push rechunked image to GHCR"
for tag in ${{ steps.metadata.outputs.tags }}; do
  sudo skopeo copy --retry-times 3 \
    --dest-creds="${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}" \
    --digestfile=/tmp/digest.txt \
    "${{ steps.rechunk.outputs.ref }}" \
    "docker://${IMG_FULL}:${tag}"
  if [[ -z "$DIGEST" ]]; then
    DIGEST="$(cat /tmp/digest.txt)"
  fi
done
...
echo "image_ref=${IMG_FULL}@${DIGEST}" >> "$GITHUB_OUTPUT"
```

All tags point at the same manifest, so one digest covers them all. Signing `image@sha256:...` instead of `image:tag` eliminates the TOCTOU window where someone retags between push and sign.

**2. Sign in a minimal job with only the digest as input:**

```yaml
# margine-image/.github/workflows/build.yml — sign job
- name: Install Cosign
  uses: sigstore/cosign-installer@7e8b541eb2e61bf99390e1afd4be13a184e9ebc5  # v3.10.1

- name: Sign image by digest
  env:
    COSIGN_PRIVATE_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
    COSIGN_PASSWORD: ""
  run: |
    set -euo pipefail
    IMAGE_REF="${{ needs.build_push.outputs.image_ref }}"
    ...
    cosign sign -y --key env://COSIGN_PRIVATE_KEY "${IMAGE_REF}"
```

`env://COSIGN_PRIVATE_KEY` keeps the key out of the filesystem and out of argv (visible in `/proc`). `COSIGN_PASSWORD: ""` declares the key is unencrypted, acceptable because the only at-rest copy is inside GitHub's secret store; encrypting it would just move the secret to a second variable. `cosign sign` pushes the signature as an OCI artifact to the same repository (the `sha256-<digest>.sig` tag), so no separate signature distribution channel is needed.

### Signatures survive promotion because promotion preserves digests

Margine's `:candidate` → `:stable` promotion (after the QEMU smoke boot, chapter 7) is a `skopeo copy --preserve-digests` of the exact digest the gate booted. The manifest digest does not change, so the signature made against `:candidate`'s digest is automatically valid for `:stable`:

```bash
# margine-image/.github/workflows/smoke-boot.yml — promote step
# ${PINNED} = ${BASE}@sha256:... resolved once (the digest just booted)
for promo_tag in stable "stable.${DATE_TAG}" "${DATE_TAG}"; do
  sudo skopeo copy --retry-times 3 --preserve-digests \
    "docker://${PINNED}" \
    "docker://${REGISTRY_IMAGE}:${promo_tag}"
done
```

Sign-by-digest plus copy-by-digest means the chapter-7 promotion gate adds zero signing work: the bytes that were smoke-booted are the bytes that were signed are the bytes users pull. (Promoting `${PINNED}` rather than re-resolving `:candidate` also closed a void-gate bug, see chapter 9 §9.5.)

## 8.3 SBOM as a signed OCI referrer

The image's package inventory ships as an SPDX SBOM attached to the manifest (OCI 1.1 referrer) and signed with the same key:

```bash
# margine-image/.github/workflows/build.yml — "Attach + cosign-sign SBOM"
ATTACH_JSON="$(oras attach \
  --artifact-type application/vnd.spdx+json \
  ...
  --format json \
  "${IMAGE_REF}" \
  sbom.spdx.json:application/spdx+json)"
ATTACH_DIGEST="$(jq -r '.reference | split("@")[1] // .digest // empty' <<<"$ATTACH_JSON")"
...
SBOM_REF="${IMG_BASE}@${ATTACH_DIGEST}"
cosign sign -y --key env://COSIGN_PRIVATE_KEY "${SBOM_REF}"
```

Consumers do `oras discover` → `oras pull` → `cosign verify` against the same `cosign.pub`. The SBOM is generated in `build_push` (not in `sign`) for a reason that cost six PRs to learn:

> **Lesson: syft OOM on large rechunked images**
> **Symptom:** the `sign` job was killed by a runner shutdown signal ~11-14 min into `syft`, across PRs #49, #52 (timeout bump), #53 (free 30 GB disk), #58 (`--scope squashed`), #60 (syntax fix), see `margine-image/docs/sbom-revisit-plan.md` for the full table.
> **Root cause:** `syft` on a registry image reference *always pulls every layer*; `--scope squashed` changes the SBOM representation, not the input. A 14 GB rechunked image's expanded in-memory layer tree exceeds the 16 GB RAM of a stock `ubuntu-24.04` runner. Freeing disk didn't help because the bottleneck was RAM.
> **Fix:** generate the SBOM inside `build_push` *before* rechunk, from a flat filesystem export instead of the layer model, peak RAM ~1 GB:
> ```bash
> # margine-image/.github/workflows/build.yml, SBOM step
> sudo podman container create --replace --name sbom-export \
>   --entrypoint /bin/true \
>   "localhost/${{ env.IMAGE_NAME }}:${{ steps.metadata.outputs.version }}"
> sudo podman export sbom-export | sudo tar -C "$ROOTFS" -xf -
> sudo "$(which syft)" --source-name "..." "$ROOTFS" -o spdx-json=sbom.spdx.json
> ```
> The SBOM file is handed to the `sign` job as a 1-day workflow artifact. Pre-rechunk is fine: rechunk repacks layer boundaries, it does not change the package set.

> **Lesson: `oras attach` digest extraction**
> **Symptom:** build #27065187939 (2026-06-06) failed with `Signing SBOM: ghcr.io/.../margine@<no value>`.
> **Root cause:** `oras` 2.x `--format go-template='{{.Digest}}'` resolves to `<no value>`: the JSON key is lowercase `digest` and the documented template path doesn't match.
> **Fix (PR #73):** use `--format json` and parse with `jq -r '.reference | split("@")[1] // .digest // empty'`, then hard-fail if empty (see snippet above).

## 8.4 Host-side verification: policy.json + registries.d

Signing is worthless unless the client checks. Container verification on a Fedora/bootc host is configured by two files, both consulted by everything that pulls through containers/image (podman, skopeo, bootc, rpm-ostree's container backend):

**`/etc/containers/policy.json`** maps registry scopes to requirements. To require Margine's cosign signature:

```json
{
  "transports": {
    "docker": {
      "ghcr.io/daniel-g-carrasco/margine": [
        {
          "type": "sigstoreSigned",
          "keyPath": "/etc/pki/containers/margine.pub",
          "signedIdentity": { "type": "matchRepository" }
        }
      ]
    }
  }
}
```

`sigstoreSigned` means "a cosign-style signature verifiable with this key must exist for the pulled digest". `matchRepository` accepts any tag in the repo (necessary, because the signature is made against `:candidate`'s digest but pulled via `:stable`).

**`/etc/containers/registries.d/margine.yaml`** tells the stack *where* signatures live. Cosign stores them as OCI artifacts in the same repository, which must be opted into:

```yaml
docker:
  ghcr.io/daniel-g-carrasco/margine:
    use-sigstore-attachments: true
```

Without this, verification looks for a lookaside (web-server) sigstore and fails with "no signature found" even though the signature exists on GHCR.

Because Margine derives from Bluefin DX, the base image already ships a populated `/etc/containers/policy.json` and `/etc/pki/containers/` for the `ghcr.io/ublue-os` scope; the Margine-specific scope and key are the distro's job to add at image build time, so every installed host verifies its own updates. The 2026-06-05 audit flags this as the load-bearing check (§6.5):

> Verify `/etc/containers/policy.json` allows your registry path with `cosign` verification, not just `insecureAcceptAnything`. This is what makes `bootc switch --enforce-container-sigpolicy ghcr.io/daniel-g-carrasco/margine:stable` *actually* verify, not just succeed.
> `docs/spec/audits/2026-06-05-margine-stack-audit.md`

The same audit section cites the cautionary upstream incident: ublue-os/bluefin#4197 (2026-02-12), where `bluefin-dx:stable` shipped *without* `/etc/pki/containers/ublue-os.pub`, breaking `bootc upgrade` for every downstream consumer enforcing signature policy. Policy enforcement cuts both ways: if the key file is missing from the image, verified updates brick themselves. Margine's end-to-end check of this path on a booted install is tracked as deferred in the audit status delta (`2026-06-05-margine-stack-audit-status-delta.md`: "Verify `/etc/pki/containers/<key>.pub` + policy.json (§6.5) … ⏸ Deferred: needs a running install"), and `docs/spec/roadmap.md` keeps the honest TODO:

```text
- ⏳ Move the `:stable` redirect to a *signed cosign verification* on
  the user side (today `bootc` trusts the registry; we could
  configure rpm-ostree's `verify-by-key` to enforce cosign at the
  client). Defense in depth.
```

### The `ostree-image-signed:` transport

The documented rebase command selects the policy-enforcing transport explicitly:

```sh
# margine-image/README.md
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
```

rpm-ostree's container transports encode the trust decision in the ref itself:

| Transport | Behavior |
|---|---|
| `ostree-unverified-registry:` / `ostree-unverified-image:` | Pull, no signature check (TLS only) |
| `ostree-image-signed:docker://...` | Pull **fails** if the policy for that scope resolves to `insecureAcceptAnything` — i.e. it requires that a real verification policy exists and passes |
| `ostree-remote-image:<remote>:...` | Verify GPG against an ostree remote config (legacy commit-signing path) |

Putting `ostree-image-signed:` in the user-facing docs means the deployment origin file records the signed transport, and every subsequent `rpm-ostree upgrade`/`bootc upgrade` on that origin re-verifies. `bootc switch --enforce-container-sigpolicy` is the bootc-native equivalent. Per the SBOM revisit plan: "Consumer verification flow (`bootc switch --enforce-container-sigpolicy`) works on cosign-by-digest alone". The SBOM is hygiene, the image signature is the actual trust gate.

## 8.5 SHA-pinning actions and base images

Every third-party action in Margine's workflows is pinned to a full 40-character commit SHA, with the human-readable version kept as a comment so Renovate can bump both in lockstep (Margine retired `dependabot.yml` for a `renovate.json5`):

```yaml
# margine-image/.github/workflows/build.yml
- name: Checkout
  # SHA-pinned for supply-chain safety. Comment is the human-readable
  # version the bump bot (Renovate) uses to bump both fields in lockstep.
  # See the tj-actions/changed-files incident (2025-03) for why @vN alone
  # is unsafe.
  uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3
```

A `@v6` tag is a mutable pointer in someone else's repo; the tj-actions/changed-files compromise (March 2025) retroactively poisoned the floating tags of an action used by ~23k repos, exfiltrating CI secrets. A SHA cannot be moved. The same pattern covers `docker/metadata-action`, `anchore/sbom-action`, `actions/upload-artifact`/`download-artifact`, `oras-project/setup-oras`, `ublue-os/remove-unwanted-software`, `osbuild/bootc-image-builder-action`, and `daniel-g-carrasco/titanoboa` (a personal fork carrying the margine patch set, see the ISO chapter, SHA-pinned via the `TITANOBOA_REF` env in `build-disk.yml`) in the disk/ISO workflows.

> **Lesson: a floating action tag is also a floating tool version (CVE-2026-39395)**
> **Symptom:** audit §6.2 flagged `sigstore/cosign-installer@v3` (floating) in both build workflows as CRITICAL.
> **Root cause:** `@v3` doesn't pin which *cosign binary* gets installed. CVE-2026-39395 / GHSA-w6c6-c85g-mmv6 (April 2026): `cosign verify-blob-attestation` returns false positives on malformed payloads; patched in cosign v3.0.6. A floating installer tag gives no guarantee of `>= v3.0.6`.
> **Fix (margine-image #41):**
> ```yaml
> uses: sigstore/cosign-installer@7e8b541eb2e61bf99390e1afd4be13a184e9ebc5  # v3.10.1
> ```
> v3.10.1 of the installer pulls cosign v3.0.6. Pinning the action SHA pins the toolchain version transitively.

One deliberate exception, worth stating because pinning is a policy, not a reflex (a former second one, `hhd-dev/rechunk`, once tag-pinned at `@v1.2.4`, is now closed: it is SHA-pinned `hhd-dev/rechunk@5fbe1d3a639615d2548d83bc888360de6267b1a2 # v1.2.4` like every other action):

- **`FROM ghcr.io/ublue-os/bluefin-dx:stable`** in the Containerfile floats on purpose. Margine *wants* upstream drift: the weekly cron (`schedule: '0 4 * * 0'` in `build.yml`) rebuilds against whatever Bluefin DX currently is, and the QEMU smoke gate (chapter 7) catches breakage before `:stable` moves. Digest-pinning the base would trade silent drift for a Renovate-style bump treadmill; the gate makes the float survivable. If you have no boot gate, pin the FROM digest.

A third reproducibility note, and a piece of history. The scripts, branding and declarations the image installs used to live in a separate spec repo (`margine-fedora-atomic`), fetched over the network at build time. That fetch had to be ref-pinned to a commit SHA (resolved at build start, passed in as `--build-arg MARGINE_REF=<sha>`, stamped as an OCI label) or the image would not be reproducible, and even then it carried a TOCTOU caveat. Since the 2026-07-05 unification those files are vendored in this repo under `build_files/`, so the build fetches nothing at all. Reproducibility comes for free: every image is byte-reproducible from the single `margine-image` commit it was built from, stamped as the standard `org.opencontainers.image.revision` label, with no second ref to pin and no fetch to race.

### Linting the pipeline itself, and automating the bumps

Pinning is only half a policy; the other half is keeping the pins fresh and the glue scripts honest. Two pieces close that loop:

- **`lint.yml`** in each repo runs `actionlint` (workflow schema + shellcheck over every `run:` block), a **shebang-aware** `shellcheck` pass (tracked `*.sh` *plus* the extensionless `system_files` payloads discovered by their `#!` line, the GUI probe and the seed scripts would otherwise be invisible to shellcheck), and `ruff` over the Python build helpers. This is why the inline heredocs got extracted into real files: a script shellcheck can't see is a script nobody is checking.
- **Renovate** replaced Dependabot: `dependabot.yml` was retired for a `renovate.json5` that bumps the SHA pins (and their version comments) in lockstep, including the `# Renovate disabled` carve-out for the personal Titanoboa fork that must not be auto-bumped.

## 8.6 Secrets handling in GHA

Margine's CI holds three secrets: `MOK_KEY`, `MOK_CERT` (kernel signing) and `COSIGN_PRIVATE_KEY`. (The mokutil enrollment passphrase is *not* a secret: it's a hardcoded constant `MOK_PASSWORD="margine-os"` in `custom-kernel/install.sh`, public by design; §4.6.) Handling rules visible in the workflow:

```yaml
# margine-image/.github/workflows/build.yml
- name: Stage MOK secrets for BuildKit
  env:
    MOK_KEY:      ${{ secrets.MOK_KEY }}
    MOK_CERT:     ${{ secrets.MOK_CERT }}
  run: |
    mkdir -p /tmp/margine-secrets
    chmod 700 /tmp/margine-secrets
    printf '%s' "$MOK_KEY"      > /tmp/margine-secrets/MOK.key
    ...
    chmod 600 /tmp/margine-secrets/*
...
- name: Wipe staged secrets
  if: always()
  run: rm -rf /tmp/margine-secrets
```

Secrets are passed via `env:` (never string-interpolated into `run:` script bodies, which would land them in the rendered script), staged with restrictive modes, and wiped in an `if: always()` step so a failed build doesn't leave key material on a runner that might persist for later steps. Inside the build they enter only as BuildKit secret mounts, which exist for the duration of one `RUN` and never become a layer:

```dockerfile
# margine-image/Containerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    ...
    --mount=type=secret,id=mok-key,target=/tmp/certs/MOK.key \
    --mount=type=secret,id=mok-cert,target=/tmp/certs/MOK.pem \
    /ctx/custom-kernel/install.sh
```

A `COPY MOK.key` + `rm` would leave the key recoverable in the layer history; a secret mount cannot.

Token scoping follows least privilege per job: `GITHUB_TOKEN` permissions are declared explicitly (`contents: read, packages: write, id-token: write`) instead of inheriting the repo default, and the cosign job authenticates with an explicit `cosign login ghcr.io` because `cosign sign` reads `~/.docker/config.json`, which a fresh job hasn't populated. The `notify` job receives only job *results*, never secrets beyond the ntfy URL, and degrades to a no-op if that secret is absent.

## 8.7 Alternatives & other distros

**Signing schemes:**

- **Key-based cosign (Margine, Bazzite, most ublue community images, the ublue image-template historically):** one keypair, `cosign.pub` committed in-repo and baked into `/etc/pki/containers/`. Pros/cons per Margine's audit: "Works in air-gapped CI; signature verifiable without sigstore trust root" vs "Key rotation is a maintenance task; private key in repo secrets."
- **Keyless sigstore, Fulcio + Rekor (Universal Blue's direction for first-party images):** `id-token: write` → `cosign sign $IMAGE` with no `--key`; a short-lived cert from Fulcio binds the signature to the GHA workflow's OIDC identity, logged in Rekor. No key to leak or rotate, provenance is the workflow identity itself; but verification needs the sigstore trust root and an identity-matching policy (`--certificate-identity-regexp`), and `policy.json` support uses `fulcio`/`rekorPublicKey` stanzas, more moving parts on every client. Margine's audit verdict: migration is "a future improvement, not a fix."
- **GPG-signed ostree commits (stock Fedora Silverblue/Kinoite ostree remotes):** the classic pre-OCI model: the compose server signs the ostree *commit*; clients verify via `gpg-verify=true` + keyring in the remote config (`ostree-remote-image` transport bridges this to containers). Solid, but ties you to ostree remotes rather than plain registries, and signs commits, not OCI manifests: useless for `podman pull` consumers.
- **Notation / Notary v2 (CNCF, Azure ecosystem):** signs OCI manifests with X.509 chains. Fine for cluster admission controllers; effectively unsupported in `containers-policy.json`, so wrong tool for a bootc host.
- **Sealed bootable images (systemd-boot + UKI + composefs fs-verity):** moves integrity from *pull time* to *every boot*. Margine tracks this as ADR 0007 (`docs/spec/adr/0007-sealed-bootable-images-tracker.md`, status Watching). Complementary, not alternative: cosign authenticates the download, fs-verity would authenticate the running tree.

**Other distros' supply chains, for calibration:**

- **Bluefin / Aurora / Bazzite (Universal Blue):** same shape as Margine (which copied it): cosign sign in GHA, key in `/etc/pki/containers/ublue-os.pub`, policy.json scoped to `ghcr.io/ublue-os`, and the #4197 incident shows the failure mode when the key file goes missing from the image.
- **Fedora Silverblue (registry path):** Fedora's official bootc images are signed with Fedora's infrastructure (sigstore keys shipped in `fedora-repos`); the legacy ostree remote path uses Fedora's GPG key.
- **openSUSE MicroOS / Aeon:** no OCI signing: trust is RPM GPG signatures + signed repo metadata, applied through `transactional-update` snapshots. Verification granularity is per-package, not per-image.
- **Vanilla OS (ABRoot v2):** OCI-image-based A/B transactions; trust rests primarily on registry TLS + their build pipeline, no end-user signature policy comparable to containers-policy enforcement.
- **NixOS:** no image to sign: closures are verified via Ed25519 signatures on binary-cache narinfo (`cache.nixos.org-1:...` trusted-public-keys), and full source reproducibility is the fallback. Strongest story on paper, completely different mechanism.
- **ChimeraOS:** `frzr` deploys squashfs images from GitHub releases; integrity is HTTPS + release checksums, no client-side signature policy.

**CI pinning alternatives:** Renovate/Dependabot with `pinDigests` (automates the SHA+comment dance Margine does manually), Chainguard's `frizbee`/StepSecurity to mass-pin existing workflows, or GitHub's allowed-actions policy as an org-level backstop. For the base image, digest-pinned `FROM` + automated bump PRs (common in Renovate-managed ublue forks) trades Margine's "float + boot gate" for explicit review of every upstream change.

## 8.8 What this buys, and what it doesn't

End state: a Margine host that pulled via `ostree-image-signed:` with the margine key in `/etc/pki/containers/` will refuse an update whose manifest wasn't signed by the Margine key: a compromised GHCR token alone can push a tag but cannot mint a valid signature. What it does *not* cover: a compromised GHA runner during the build (it holds the cosign key via secrets), a malicious upstream `bluefin-dx:stable` (floated by design, gated only behaviorally by the smoke boot), and the deferred §6.5 end-to-end verification on a booted install. Supply-chain work is a ratchet; the audit documents each remaining click.


---

# 9. CI/CD for an OS: GitHub Actions as the build farm

An atomic distro's "release engineering" is a container pipeline. Margine ships from three workflows in `margine-image/.github/workflows/`:

| Workflow | Job shape | Output |
|---|---|---|
| `build.yml` (672 lines) | `build_push` → `sign` → `notify` | OCI image → GHCR `:candidate` |
| `smoke-boot.yml` (271 lines) | `smoke_boot` (auto after build) | promotion `:candidate` → `:stable` |
| `build-disk.yml` (901 lines) | `build_disk` (qcow2) + `build_iso_titanoboa` → `publish_ia` → `bump_site` → `notify` | qcow2 + Titanoboa live ISO → Internet Archive |

Everything runs on GitHub-hosted `ubuntu-24.04`. That was not the first choice.

## 9.1 Why GitHub-hosted (the PVE builder post-mortem)

Margine originally built on a self-hosted runner: a Proxmox VM (`margine-builder`, VM 170). It was decommissioned, and the workflow header preserves the reason:

```yaml
# History (2026-06-01): we used to run this on a self-hosted PVE VM
# (margine-builder, VM 170). After two freezes — the second one
# taking the entire PVE host down with ZFS spacemap corruption (see
# proxmox-pve1/docs/operations/zfs-spacemap-corruption-recovery.md)
# — the self-hosted runner has been decommissioned. GitHub-hosted
# is exactly the "container that wakes up when a job arrives and
# shuts down after" model we wanted.
```
*`margine-image/.github/workflows/build.yml` (header)*

The trade: hosted runners give ~14 GiB free disk and 16 GB RAM, no persistence, no babysitting. A 14 GB bootc image build does not fit in 14 GiB. Every job's first step reclaims space:

```yaml
- name: Maximize build space
  # ubuntu-24.04 has ~14 GiB of free disk by default; we need
  # ~30+ GiB for the buildah cache + base image + Margine layers
  # + rechunk staging. This action removes Android/Haskell/.NET/
  # Swift/CodeQL/GHC pre-installed bundles, freeing ~30 GiB.
  uses: ublue-os/remove-unwanted-software@cc0becac701cf642c8f0a6613bbdaf5dc36b259e # v9
  with:
    remove-codeql: true
```
*`margine-image/.github/workflows/build.yml:100-107`*

Note the SHA-pinned action. Every third-party action in these workflows is pinned to a commit SHA with the version as a comment. The build.yml checkout step explicitly cites the `tj-actions/changed-files` compromise (2025-03) as the reason `@vN` floating tags are unsafe in a pipeline that holds kernel-signing keys.

## 9.2 build.yml: triggers, concurrency, build

### Triggers — four entry points

```yaml
on:
  push:
    branches: [main]
    paths-ignore:
      - '.github/workflows/build-disk.yml'
      - 'README.md'
      - 'CHANGELOG.md'
      - 'docs/**'
  pull_request:
    types: [labeled, synchronize]
    branches: [main]
  schedule:
    # Weekly nightly: Sunday 04:00 UTC = 06:00 CEST. Picks up upstream
    # Bluefin DX changes even if there are no commits to this repo.
    - cron: '0 4 * * 0'
  workflow_dispatch:
```
*`margine-image/.github/workflows/build.yml:43-69` (trimmed)*

- **`push` with `paths-ignore`**: docs commits don't burn a 25-minute build.
- **`schedule`**: the security-critical one. A bootc image is a frozen snapshot: if you only build on commit, your users stop receiving upstream CVE fixes (Fedora → Bluefin DX → you) the moment you stop committing. The cron rebuild re-pulls `ghcr.io/ublue-os/bluefin-dx:stable` and republishes even with zero repo changes. Margine runs weekly; ublue-org images do this daily.
- **`pull_request` only when labeled `vm-test`**: guarded at the job level:

```yaml
build_push:
  # On pull_request, only build for PRs explicitly labeled `vm-test`.
  # All other PRs (docs, CI tweaks, etc.) skip the 30-min image build.
  if: github.event_name != 'pull_request' || contains(github.event.pull_request.labels.*.name, 'vm-test')
```
*`margine-image/.github/workflows/build.yml:83-87`*

Labeled PRs publish a transient `:pr-N` tag so a lab VM can `bootc switch` to the PR image before merge.

### Concurrency — cancel superseded builds

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref || github.run_id }}
  cancel-in-progress: true
```
*`margine-image/.github/workflows/build.yml:78-80`*

Two pushes to `main` in quick succession: the first 25-minute build is dead weight (its output would be immediately superseded), so it is cancelled. The `|| github.run_id` fallback gives `workflow_dispatch`/`schedule` runs their own group so they never cancel each other.

### The build step — raw buildah, no wrapper action

```yaml
sudo -E buildah build \
  --file ./Containerfile \
  --format docker \
  --layers \
  --secret id=mok-key,src=/tmp/margine-secrets/MOK.key \
  --secret id=mok-cert,src=/tmp/margine-secrets/MOK.pem \
  "${TAG_ARGS[@]}" \
  "${LABEL_ARGS[@]}" \
  .
```
*`margine-image/.github/workflows/build.yml:238-247`*

Margine dropped `redhat-actions/buildah-build` for a direct shell call (the pattern Bazzite uses): no Node-runtime deprecation warnings, no waiting on the action repo for fixes, and the exact same command works on a laptop. Two side effects worth copying: `sudo buildah` writes to root storage (`/var/lib/containers`), which is where rechunk's `podman create` looks: the old rootless action needed an extra oci-archive bounce; and BuildKit `--secret` mounts keep the MOK private key out of every layer (chapter 4). The secrets are staged to `/tmp/margine-secrets` from GitHub Actions secrets and wiped in an `if: always()` step.

One more reproducibility note: the validators, scripts and branding the image installs used to be fetched from a separate spec repo, which had to be ref-pinned to a commit SHA at build start (`--build-arg MARGINE_REF=<sha>` plus an OCI label) or the build would not be reproducible. Since the 2026-07-05 unification they are vendored in this repo under `build_files/`, so nothing is fetched at build time and the image is byte-reproducible from the single commit it was built from (`org.opencontainers.image.revision`), with no second ref to pin.

## 9.3 Validators as gates inside the build

Static checks ("Layer A") run between `buildah build` and rechunk/push. The technique: create a container without running it, export the filesystem to a directory, assert against files.

```yaml
- name: Validate first-boot assets in built image (blocks rechunk)
  run: |
    sudo podman container create --replace --name validate-fs \
      --entrypoint /bin/true \
      "localhost/${{ env.IMAGE_NAME }}:${{ steps.metadata.outputs.version }}"
    ROOTFS=$(mktemp -d)
    sudo podman export validate-fs | sudo tar -C "$ROOTFS" -xf -
```
*`margine-image/.github/workflows/build.yml:273-291` (trimmed)*

Six sections, each born from a real first-boot regression observed on a fresh install (2026-06-06): A.1 About-panel logo (`LOGO=margine-logo` in os-release + pixmaps present), A.2 welcome icon is a valid GTK4 symbolic SVG (no embedded raster), A.3 all 10 `enabled-extensions` UUIDs exist under `/usr/share/gnome-shell/extensions/`, A.4 first-boot autostart files, A.4.bis offline-docs mirror completeness (≥14 `index.html`, no live JS/CSS references), A.3.bis dconf keyfiles in `/etc/dconf/db/distro.d/`.

The dconf checks include *sentinel values*: a grep for one representative key per keyfile, proving the file content (not just its existence) survived the build:

```yaml
grep -qE "^border-radius=7" "$DCONF_DIR/02-margine-search-light" || { echo "::error::A.3.bis search-light border-radius!=7 — daniel default lost"; fail=1; }
# dash-to-dock background customisation present (cosmetic regression sentinel)
grep -qE "^running-indicator-style='DOTS'" "$DCONF_DIR/01-margine-dash-to-dock" || { echo "::error::A.3.bis dash-to-dock running-indicator-style sentinel missing"; fail=1; }
```
*`margine-image/.github/workflows/build.yml:388-390`*

Placement matters: the gate runs at ~22 minutes in, **before** SBOM/rechunk/push/sign, so a regression fails fast and nothing broken ever reaches the registry, not even `:candidate`.

### Lesson: the sentinel that broke the build

- **Symptom:** build run 27297409457 failed in the first-boot asset validator: `A.3.bis search-light border-radius!=30 — daniel default lost`. No file was missing; the keyfile was present and correct.
- **Root cause:** the *default itself* had just been fixed. PR #94 discovered that search-light's `border-radius` is not pixels but an index into `rads = [0,16,18,20,22,24,28,32]`. The old `30.0` hit `rads[30] = undefined` and was silently ignored at runtime. The keyfile was corrected to `7.0` (= 32 px), but the CI sentinel still asserted the old literal `30`. A sentinel is a duplicated constant: change the source of truth, and the copy in the gate becomes a tripwire.
- **Fix:** same-day commit `b4e8680` (`ci(validator): search-light border-radius sentinel 30 -> 7`) updated the assertion and inlined the rationale so the next editor updates both:

```yaml
# search-light rounded-corners daniel default: border-radius=7.0
# (the value is an INDEX 0-7 into the extension's px table, not
# pixels — 7 = 32px max rounding; the old 30 was out of range and
# silently ignored. See #94.)
grep -qE "^border-radius=7" "$DCONF_DIR/02-margine-search-light" || ...
```
*`margine-image/.github/workflows/build.yml:384-388`*

Takeaway: sentinel gates are worth the duplication (they catch silent file truncation and staging-order bugs that existence checks miss), but treat the sentinel as part of the change: "update default" PRs must touch the validator in the same commit, or generate the assertion from the keyfile itself.

### Validators as the single source of truth, run in-container

The "generate the assertion from the keyfile itself" half of that takeaway is where the chapter's own sentinel-duplication Lesson is finally retired. The grep sentinels were duplicated *constants*, the keyfile said one thing, the CI step asserted another, and they drifted. The fix is to stop duplicating the check and instead **run the real validator against the built image**, the same binary the OS ships:

```yaml
- name: Run image validators (single source of truth)
  run: |
    for v in margine-validate-margine-system margine-validate-branding; do
      sudo podman run --rm -e MARGINE_VALIDATE_CONTEXT=image \
        "localhost/${IMAGE_NAME}:${VERSION}" "$v"
    done
```
*`margine-image/.github/workflows/build.yml` (Layer A validator step).* `MARGINE_VALIDATE_CONTEXT=image` tells the validator it is inspecting a built rootfs rather than a running system (so it skips checks that need a live session). The decisive property: **one** validator now runs in three places, here in CI (Layer A), inside the Layer C GUI probe (below), and on a user's machine via `ujust margine-doctor` (which iterates every `/usr/bin/margine-validate-*`). There is no second copy of the assertion to drift from the default; if the keyfile and the check disagree, it is one bug in one file.

## 9.4 Push to GHCR and the job split

After SBOM generation (`podman export` + `syft dir:`, the rechunked-image-from-registry path OOMs a 16 GB runner; chapter 10) and `hhd-dev/rechunk` (repacks layers for OSTree delta efficiency; chapter 3), the push captures the manifest digest:

```yaml
for tag in ${{ steps.metadata.outputs.tags }}; do
  sudo skopeo copy --retry-times 3 \
    --dest-creds="${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}" \
    --digestfile=/tmp/digest.txt \
    "${{ steps.rechunk.outputs.ref }}" \
    "docker://${IMG_FULL}:${tag}"
  ...
done
echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
echo "image_ref=${IMG_FULL}@${DIGEST}" >> "$GITHUB_OUTPUT"
```
*`margine-image/.github/workflows/build.yml:483-498` (trimmed)*

The digest is a job output consumed by a **separate** `sign` job, which cosign-signs `image@sha256:...` by digest (tag-based signing is racy, the tag can move between push and sign). Why a separate job at all? Failure economics, documented in the header:

```yaml
# On a failed sign step, `gh run rerun --failed <run-id>` re-runs
# only the sign job (~1 min) instead of redoing the whole build.
# That's the whole point of the split — failure cost dominates
# the few seconds of cross-job overhead.
```
*`margine-image/.github/workflows/build.yml:27-30`*

A final `notify` job (`if: always()`) aggregates both results into an ntfy push, with the partial-success case (image pushed, sign failed) spelled out explicitly including the exact `gh run rerun --failed` command to recover.

## 9.5 The QEMU smoke gate and `:stable` promotion

`build.yml` publishes to `:candidate` + `:candidate.YYYYMMDD`, never directly to the tag users track. Layer A checks files; every bug from the 2026-05-28/29 smoke tests (dracut/initramfs, systemd ordering cycle → `emergency.target`) was a **runtime** bug Layer A could not see. `smoke-boot.yml` is Layer B: actually boot the thing.

It auto-triggers on every successful build via `workflow_run` (guarded so cancelled/failed builds don't waste a runner), builds a qcow2 from the candidate with bootc-image-builder, and boots it under QEMU, GHA `ubuntu-24.04` runners have had `/dev/kvm` since 2024, so boot to desktop is minutes, not hours:

```yaml
sudo qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 -smp 4 \
  -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file=ovmf_vars.fd \
  -drive file="$QCOW",format=qcow2,if=virtio \
  -serial file:serial.log \
  -display none \
  -no-reboot \
  &
```
*`margine-image/.github/workflows/smoke-boot.yml:152-163` (trimmed)*

Design decisions encoded here: no LUKS in the qcow2 (automation can't type a passphrase; encrypted boot is exercised in the manual VM lab), and Secure Boot intentionally **off** (SB would need the MOK pre-enrolled in the OVMF VARS file; the kernel signature is already asserted at build time, Layer B's question is "does ostree+composefs+systemd reach a usable state", not "is the SB chain intact").

Pass/fail is a grep loop over the serial log. The naive marker broke in practice, systemd on Fedora 44 doesn't reliably print `Reached target Multi-User System` on serial, so the gate accepts any of three equivalent signals:

```bash
for i in $(seq 1 1200); do
  if [[ -f serial.log ]] && grep -qE "Started.*gdm\.service|Reached target graphical\.target|margine login:" serial.log; then
    echo "✓ Boot reached usable state at second $i"
    echo "passed=true" >> $GITHUB_OUTPUT
    ...
```
*`margine-image/.github/workflows/smoke-boot.yml:184-191`*

The budget is 20 minutes, not 30 seconds: first boot pulls 2–3 GB of Flatpaks via `flatpak-preinstall.service` plus `ostree-finalize-staged`. On failure the serial log is uploaded as an artifact, with a pre-digested triage dump (`Reached target` vs `Failed to start`, most-restarted units) printed in the job log.

### Promotion: same bytes, new name

A "Resolve image ref to digest" step runs first and pins the candidate to an immutable digest *once*, and every later step (the qcow2 build, the boot, the promotion) consumes that one `${PINNED}` value:

```yaml
- name: Resolve image ref to digest
  id: ref
  run: |
    DIGEST="$(sudo skopeo inspect --no-tags --format '{{.Digest}}' "docker://$REF")"
    echo "pinned=${BASE}@${DIGEST}" >> "$GITHUB_OUTPUT"

- name: Promote candidate → stable (only if boot passed)
  if: success() && steps.boot.outputs.passed == 'true'
  run: |
    for promo_tag in stable "stable.${DATE_TAG}" "${DATE_TAG}"; do
      sudo skopeo copy --retry-times 3 --preserve-digests \
        "docker://${PINNED}" \
        "docker://${REGISTRY_IMAGE}:${promo_tag}"
    done
```
*`margine-image/.github/workflows/smoke-boot.yml` (resolve + promote steps).*

`skopeo copy --preserve-digests` is a registry-side tag move: no rebuild, no re-rechunk, the digest promoted to `:stable` is byte-identical to the manifest that just booted, and the cosign signature made by digest stays valid. `:stable.YYYYMMDD` and `:YYYYMMDD` give users pinnable rollback targets. Policy in one sentence: **no image reaches `:stable` without having booted in QEMU.**

This closed a previously-void gate. The earlier version resolved `:candidate` independently in the qcow2-build step and again in the promotion step, so if a *new* build finished mid-smoke, the gate booted one digest and `skopeo copy` promoted whatever `:candidate` pointed at by then (a different, never-tested digest). Resolving to `${PINNED}` once makes "booted" and "promoted" provably the same bytes (code-quality review finding A1; the per-tag re-resolve was A2). A guard was also added so the three stable tags can't split across two digests: this is the only workflow that mutates `:stable`, so it carries `concurrency: { group: smoke-boot, cancel-in-progress: false }`, concurrent promotions queue instead of racing, and a run is never cancelled mid-`skopeo copy`.

### Layer C: a GUI smoke probe

Layer B answers "did userspace come up", it greps the serial log for `gdm.service`/`graphical.target`. But a GNOME session can *reach* `graphical.target` with a gnome-shell that immediately crashes on a bad extension: the login screen appears, the user's session never does. To catch that class, a third layer boots the qcow2 with a throwaway autologin user and a root oneshot that interrogates the live session, printing its verdict to the same serial console the watcher already reads:

```bash
# .github/smoke/gui-probe.sh (run as margine-gui-smoke.service in the VM)
pgrep -u smoke -x gnome-shell >/dev/null || fail "gnome-shell never started"
sleep 30   # let extensions load
EXT=$(runuser -u smoke -- gnome-extensions list --enabled | wc -l)
[[ "$EXT" -ge 6 ]] || fail "only $EXT extensions enabled (expected >=6)"
pgrep -u smoke -x gnome-shell >/dev/null || fail "gnome-shell died during the probe"
coredumpctl -q list 2>/dev/null | grep -q gnome-shell && fail "gnome-shell dumped core"
out "MARGINE-GUI-SMOKE: PASS ext=$EXT"
```
*`margine-image/.github/smoke/gui-probe.sh` + `margine-gui-smoke.service`, injected offline into the qcow2 by `.github/scripts/inject-gui-probe.sh` (GDM autologin + the oneshot + a permissive-SELinux karg for this one boot).* Injection runs `continue-on-error` so a failed injection can never block the Layer B gate, and the unit is `After=graphical.target` with its wants-symlink in `graphical.target.wants` (the first deployment hooked it into `multi-user.target.wants`, creating an ordering cycle that made systemd silently skip it, a "no verdict" non-result). The verdict is **warn-only** until two consecutive green runs prove it isn't flaky (both achieved 2026-06-13); then it becomes gating.

> **Lesson, "reached graphical.target" is not "the desktop works".**
> *Symptom:* a candidate passed Layer B (login screen reached) but the autologin session showed a black screen; gnome-shell was respawning.
> *Root cause:* a crashing GNOME extension took down the shell *after* `graphical.target` was reached. Layer B's grep can't see past the target; it never logs into a session.
> *Fix:* Layer C logs in as a disposable user and checks the things a human would notice, shell alive, ≥6 extensions enabled, no `gnome-shell` coredump, no Clutter `Bail out!` in the journal, and prints `MARGINE-GUI-SMOKE: PASS/FAIL` to serial. Catching a crashing-extension regression that Layer B passes is exactly the gap it exists to close.

### Layer C, part two: a soft user-smoke gate

Layer C (above) asks "is the _session_ alive?". A second injected oneshot asks a sharper question: "is this **Margine**, or just some GNOME?". `inject-gui-probe.sh` now stages a second payload alongside the GUI probe, `.github/smoke/user-smoke-probe.sh` + `margine-user-smoke.service`, and the extra injection is guarded, so a missing payload only warns (the GUI probe still goes in; you never lose the whole gate to a renamed file).

```bash
# margine-image/.github/smoke/user-smoke-probe.sh (shape — every check WARN-only)
check KERNEL      "uname -r | grep -q cachyos"
check GDM         "systemctl is-active --quiet gdm && pgrep -u smoke -x gnome-shell"
check OTILING     "enabled-extensions contains o-tiling@oliwebd.github.com"
check SEARCHLIGHT "enabled-extensions does NOT contain search-light@icedman.github.com"
check KEYBINDS    "Hyprland-style binds present in the booted user dconf"
check GAMING      "ujust --list | grep -q margine-gaming"
check GSCHEMA     "gsettings get org.gnome.desktop.interface accent-color == 'yellow'"
```

The probe asserts Margine _identity_ — the signed CachyOS kernel actually booted, the session is up, o-tiling is enabled, the Hyprland-style binds are present, search-light is gone, the gaming recipe shipped, and the `zz1-margine` gschema override took. But it never fails: it always `exit 0` and writes `MARGINE-USER-SMOKE: <CHECK> <PASS|WARN>` lines to the same serial console a `smoke-boot.yml` step parses into `$GITHUB_STEP_SUMMARY`. A regression shows up as a table on the run, not a red X.

It is non-blocking three ways on purpose — `if: always()` on the parse step, `continue-on-error: true`, and a trailing `|| true`. Promotion to `:stable` still keys **solely** on `steps.boot.outputs.passed` (Layer B). The identity probe is a dashboard, not a veto: it tells you "this still looks like Margine" without ever standing between a booting image and `:stable`.

The wants-symlink lives in `graphical.target.wants`, deliberately, not `multi-user.target.wants`. Hooking a `After=graphical.target` unit into `multi-user.target.wants` re-creates the ordering-cycle skip bug from §9.5 (systemd silently drops the unit, and you get a "no verdict" non-result that reads as success).

## 9.6 Disk images and ISOs: build-disk.yml

The OCI image updates installed systems; the ISO/qcow2 pipeline creates new ones. It is manual-trigger only (`workflow_dispatch`, plus PR runs on `disk_config/`/`live-env/` path changes), ISOs are ~5–9 GB, built per release event, not per push. The ISO is built by a separate Titanoboa job (§10.2); the BIB-driven `build_disk` job now produces only the smoke-gate `qcow2` (the `anaconda-iso` matrix entry was removed in ADR-0008 Phase 5/7):

```yaml
matrix:
  image: ["margine"]
  disk-type: ["qcow2"]
```
*`margine-image/.github/workflows/build-disk.yml` (`build_disk` matrix).*

Notables in the `build_disk` job (and the retired `anaconda-iso` path it once carried):

- **BIB pinned by digest** (`quay.io/centos-bootc/bootc-image-builder@sha256:7ae88…`) and pre-pulled with 8-attempt exponential backoff, because quay.io 5xx brownouts otherwise surface as a single opaque failed pull inside the action.
- **`rootfs: btrfs` is mandatory**: Bluefin DX doesn't set the `containers.bootc.rootfs` OCI label, so BIB errors with "DefaultRootFs missing" without it.
- **Installer-image pattern (Bazzite)** *(historical, only the retired `anaconda-iso` path used it)*: a transient `margine-installer:run-<run_id>` image was built first, base image + ~29 Flatpaks baked into `/var/lib/flatpak`, and *that* fed to BIB, so the kickstart only rsynced Flatpaks instead of downloading them in the installer environment (which OOM'd `/tmp` and failed silently; chapter 8). The build needed `--cap-add sys_admin --security-opt label=disable` because `flatpak install` uses bwrap user namespaces inside the container. The Titanoboa path keeps the same trick in `live-env` (§10.2).
- **GHCR garbage collection**: each ISO run pushes a new run-scoped tag and GHCR keeps everything forever, so an `always()` step prunes the package via `gh api`, keeping the newest 3 versions.
- **Checksums with relative paths**: `SHA256SUMS` is written with paths relative to the output dir, because absolute build-side paths broke `sha256sum -c` after the artifact was re-unpacked in the publish job at a different root (run #26789024483).

### BTRFS loopback: buying disk with compression

The Titanoboa live-ISO job (ADR-0008, now the default ISO build) squashes a ~14 GB rootfs at zstd-19 while also holding the base image, past what `remove-unwanted-software` can free on `/`. The fix, mirrored from Bazzite's workflow, is to back podman's storage with a compressed BTRFS loopback on the runner's ~70 GB ephemeral `/mnt` SSD:

```yaml
- name: Mount container storage on a BTRFS loopback
  run: |
    sudo truncate -s 80G /mnt/podman-storage.img
    sudo mkfs.btrfs -f /mnt/podman-storage.img
    sudo podman system reset --force || true
    sudo systemctl stop podman.service podman.socket 2>/dev/null || true
    sudo mount -o compress-force=zstd:2 /mnt/podman-storage.img /var/lib/containers/storage
```
*`margine-image/.github/workflows/build-disk.yml:371-383` (trimmed)*

The file is sparse (`truncate -s 80G` on a 70 GB disk is fine until actually filled) and `compress-force=zstd:2` makes OS payloads occupy roughly half their nominal size, an 80 G logical budget on the cheap.

## 9.7 Artifact egress pain → Internet Archive

GitHub will happily store a 9 GB ISO as a workflow artifact, and then serve it to a residential connection at ~1–1.5 MB/s (2–4 hours for 8 GB, per the header of `publish-titanoboa-test-iso.yml`). GHA artifacts are a job-to-job handoff mechanism, not a distribution channel. Margine's answer is the Internet Archive:

```yaml
- name: Upload to Internet Archive (torrent-first distribution)
  # IA auto-generates a BitTorrent .torrent + magnet + 3 HTTP
  # mirrors for everything we upload, and seeds it forever. This
  # is the same pattern Bluefin/Bazzite use to avoid Cloudflare
  # TOS (no large binary content served from origin) and to keep
  # our home-server upload bandwidth free.
  run: |
    ia --config-file "$IA_CONFIG_FILE" --debug upload "$IDENTIFIER" \
      "$ARTIFACT" "$OUTDIR/SHA256SUMS" \
      --retries 5 \
      --sleep 60 \
      --metadata="mediatype:software" \
      --metadata="collection:opensource" \
      ...
```
*`margine-image/.github/workflows/build-disk.yml:558-611` (trimmed)*

`publish_ia` is a separate job downstream of `build_disk` (artifact handoff over GHA's fast internal CAS) for the same rerun-economics reason as `sign`: IA's S3 ingest is the flaky, slow step, when it fails, `gh run rerun --failed` redoes the upload in minutes instead of the 15–17 min BIB build. Its timeout is 350 minutes, bumped from 180 after a real run was killed mid-upload of a 9 GB ISO. After upload, the job polls up to 25 minutes for IA's derive process to produce the `.torrent`, regenerates `SHA256SUMS` for IA's flat published layout (files are siblings at the item root, not under `bootiso/`), and emits a static `index.html` with torrent/HTTP/IA links.

Two satellites complete the release loop:

- **`bump_site`**: opens (and auto-squash-merges) a PR against the website repo bumping a single `LATEST_ISO_DATE` constant, which drives all four download URLs on the site. A fine-grained PAT (`SITE_BUMP_TOKEN`) scoped to that one repo; if absent, the job no-ops with a warning instead of failing the release.
- **`publish-titanoboa-test-iso.yml`**: pushes throwaway validation ISOs to IA's `test_collection`, which auto-expires items after ~30 days, fast downloads for hardware testing, zero cleanup.

## 9.8 Alternatives & other distros

**Build platform**
- **GitHub Actions, hosted runners** (Margine, Bluefin, Bazzite, Aurora, most ublue customs): zero ops, free for public repos, KVM available; pain is the 14 GiB disk (hence `remove-unwanted-software` / BTRFS loopback) and 6 h job cap.
- **ublue-os main-org patterns**: reusable/callable workflows + large matrices (image × flavor × Fedora version), org-wide cosign keys, `just` recipes so CI == laptop; the right model once you maintain >3 images, Margine's single-image repo inlines everything instead.
- **Self-hosted runners**: unlimited disk/CPU, cache persistence, at the cost of patching, runner-token security on public repos (PR code execution!), and your hypervisor becoming a dependency; Margine's PVE builder took the whole host down with it (ZFS spacemap corruption) and was retired.
- **GitLab CI** (used by Fedora project infra and many corporates): built-in registry, DAG via `needs:`, but shared SaaS runners lack KVM, a QEMU smoke gate needs self-hosted runners, recreating the babysitting problem.
- **Distro-scale build systems**: Fedora Koji/Pungi + OSBuild (Silverblue stock), openSUSE OBS (MicroOS/Aeon), NixOS Hydra, reproducible, multi-arch, audited; massive operational footprint, wrong size for a one-person distro.
- **Vanilla OS**: Vib build recipes on GitHub Actions producing ABRoot OCI images, same GHA+GHCR shape, different image format.

**Gating before release**
- **Margine**: file validators in-build + QEMU serial-grep smoke boot, promotion by `skopeo copy --preserve-digests`. Cheap, catches "does it boot".
- **ublue-os**: `bootc container lint` + image-level checks; Bazzite adds a large community of `:testing`-channel users as the de-facto smoke test.
- **Fedora**: openQA, full GUI-driven install/boot test matrix; the gold standard, and a service to run, not a workflow step.
- **NixOS**: NixOS test framework (declarative QEMU VM tests in Nix, gating Hydra channels), the most rigorous; requires buying into Nix wholesale.
- **ChimeraOS**: GitHub Releases + staged update channels; users are the gate.

**Tag/promotion models**
- **candidate → tested → stable retag** (Margine): one build, promotion is metadata. ublue equivalents: `:testing`/`:latest`/`:gts` channels (Bluefin), date-pinned tags everywhere.
- **Rebuild-per-channel** (some templates): simpler workflows, but the stable artifact is *not* the tested artifact, avoid.
- **NixOS channels**: an entire package-set generation advances atomically when Hydra tests pass; same philosophy, different granularity.

**Heavy-artifact distribution**
- **Internet Archive, torrent-first** (Margine): free, permanent, auto-mirrored; ingest is slow and occasionally 503s (hence retries + 350-min timeout).
- **CDN / object storage** (Bazzite, Bluefin ISO endpoints; Cloudflare R2 / B2): fast and branded; egress cost or TOS exposure for multi-GB binaries.
- **GitHub Releases** (ChimeraOS, Vanilla OS): simple, 2 GiB-per-file limit forces split archives for full ISOs.
- **GHA artifacts**: job handoff only, throttled egress makes them unusable as a download channel.


---

## 9.9 The /status freshness dashboard

The website's `/status` page answers one question, "is the Margine you'd install today current with upstream, or stale/broken?", from a single JSON document the CI produces. `build-status-json.sh` emits a `schemaVersion: 2` doc describing the whole **Fedora → Bluefin → Margine** chain: it reads `skopeo inspect` of both `bluefin-dx:stable` and `margine:stable` (version/date/digest/labels) and the latest _meaningful_ run conclusion via `gh api`.

```bash
# margine-image/.github/scripts/build-status-json.sh (shape)
skopeo inspect docker://ghcr.io/ublue-os/bluefin-dx:stable   # version/date/digest/labels
skopeo inspect docker://ghcr.io/daniel-g-carrasco/margine:stable
gh api .../actions/runs --jq 'first conclusion in success|failure|timed_out'
```

Two subtleties make it honest rather than merely green:

- **Meaningful runs only.** `cancel-in-progress` (§9.2) leaves a trail of `cancelled`/`skipped` runs; if the latest run is one of those the page reads "Unknown". The script walks back to the latest run whose conclusion is `success`, `failure`, or `timed_out` and reports _that_.
- **A `health()` map** normalises raw conclusions to the page's vocabulary. The Margine layer is `unknown` when the image can't be inspected at all (a registry blip must never let the page assert green), `behind` when its `org.opencontainers.image.base.digest` label ≠ the _current_ `bluefin-dx:stable` digest, and `failed` on a failed/timed-out build or smoke.

A guard aborts the producer if **both** skopeo inspects come back empty, so a transient registry outage can't overwrite the last-good document with an all-`unknown` one. `publish-status-json.sh` then pushes the JSON straight to the website repo's `main` (see §9.12 for why no PR), rebasing on a push race, **preserving the curated `kernel` value** already published, and skipping the commit when only the timestamp would change (no churn). `status-json.yml` runs the pair after every build/smoke/ISO (`workflow_run`), daily, and on demand.

To make the `behind` check possible, `build.yml` stamps the image with the Bluefin digest it was built **from**, best-effort, so a lookup failure never fails a build:

```yaml
# margine-image/.github/workflows/build.yml (base-digest label step)
- name: Resolve base image digest (best-effort)
  continue-on-error: true
  run: |
    DIGEST="$(skopeo inspect --no-tags --format '{{.Digest}}' \
      docker://ghcr.io/ublue-os/bluefin-dx:stable)"
    echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
# → label org.opencontainers.image.base.digest=<digest>
```

## 9.10 GHCR retention: pruning the tag-move orphans

Every daily run moves `:stable`/`:candidate` (and their dated siblings) to a fresh digest. The _old_ digest doesn't vanish, it becomes an **untagged orphan version** GHCR keeps forever. `ghcr-cleanup.yml` (the SHA-pinned `dataaxiom/ghcr-cleanup-action`) prunes them:

```yaml
# margine-image/.github/workflows/ghcr-cleanup.yml (trimmed)
with:
  keep-n-untagged: 3
  exclude-tags: "stable,latest,candidate,stable.*,candidate.*,pr-*,2*"
  validate: true
  dry-run: ${{ github.event_name == 'workflow_dispatch' && inputs.dry_run || false }}
```

`exclude-tags` covers the named, dated (`2*`), and `pr-*` tags so only genuine orphans are eligible; `validate: true` re-checks the manifest list before deletion. The daily cron does the real prune; manual `workflow_dispatch` defaults to **dry-run** so you can read the kill list before arming it. The first real run reaped ~315 orphaned versions.

The gotcha that bit us: in that action `delete-untagged` and `keep-n-untagged` are **mutually exclusive**, set both and it errors out before doing anything. Use `keep-n-untagged` (which retains a small rollback window of recent orphans) and drop `delete-untagged`.

## 9.11 Pin + ref automation

The supply-chain pins (§8) are kept honest by CI, not by human memory (o-tiling once sat at 2.8.8 right through the 2.8.11 GNOME-50 fix because nothing watched it):

- **o-tiling release pin.** Renovate tracks the GitHub-release version through a `customManager` matching the `OTILING_VERSION` constant. Hosted Renovate can't hash a release zip, so a companion `otiling-pin-sha.yml` recomputes the `sha256` _on Renovate's own branch_ and commits it back, the bot opens the version bump, the workflow fills in the hash.
- **EGO + fork pins.** `check-upstream-pins.yml` watches the EGO-hosted extension `version_tag` pins (hide-cursor, smile) and the Titanoboa fork, opening an issue when upstream moves.

Separately, `validate-flatpak-refs.yml` runs `validate-flatpak-refs.sh`, the pure-Flatpak analog to gaming-native's rpm depsolve dry-run:

```bash
# margine-image/.github/scripts/validate-flatpak-refs.sh (shape)
# parse every app ID out of the recipes' `flatpak install` lines …
for id in "${IDS[@]}"; do
  curl -fsS "https://flathub.org/api/v2/appstream/$id" >/dev/null \
    || fail "$id no longer on Flathub (renamed/delisted?)"
done
```

It checks every Flatpak the recipes install, the AI layer's `com.jeffser.Alpaca` (+ its `Plugins.AMD` ROCm extension) and the gaming set, against the Flathub API on recipe PRs and weekly, so a renamed or delisted app is caught _in CI_ instead of at the user's `ujust margine-ai` / `margine-gaming`, where it would fail at install time.

## 9.12 Cross-repo bumps that actually land

The website repo is **private on a free plan**: no branch protection, and "Allow auto-merge" is OFF. That collided with the original `bump-site-iso-date.sh`, which after each IA ISO publish opened a PR and ran `gh pr merge --auto`. With auto-merge disabled that command _errors_, so the one-line date bump sat as an open PR every release while the live site kept advertising the **previous** ISO. The failure surfaced only as a `::warning::` on an otherwise-green job, so it went unnoticed for several releases.

The fix: stop round-tripping a PR nothing can merge. Commit the one-line bump and push **straight to `main`** with a rebase-retry, and `exit 1` (red job) on real failure so it can't fail silently again.

```bash
# margine-image/.github/scripts/bump-site-iso-date.sh (shape)
sed -i "s/LATEST_ISO_DATE = .*/LATEST_ISO_DATE = \"$NEW_DATE\";/" "$SITE_INDEX"
git commit -aqm "chore(release): bump LATEST_ISO_DATE to $NEW_DATE"
for attempt in 1 2 3; do
  git push origin HEAD:main && exit 0
  git fetch origin main && git rebase origin/main || git rebase --abort
done
echo "::error::could not push the site bump"; exit 1
```

`publish-status-json.sh` (§9.9) reuses the same direct-push pattern.

**Lesson, match the merge mechanism to the repo.** For a private/free repo with no branch protection and no auto-merge, a deterministic bot bump should push to `main`, not open a PR that nothing on the plan can merge. A PR is for review you'll actually do; a date bump is neither reviewed nor mergeable here, so the PR is pure latency that silently rots, and a `::warning::` on a green job is invisible. Make the genuine failure path red.


# 10. Getting the image onto metal: installers and ISOs

A bootc image is an OCI artifact. Registries deliver upgrades; they do not deliver the *first* install. Something has to partition a disk, lay down an ostree deployment from the container, and wire the bootloader. Margine's ISO history runs through two pipelines:

- **Path A, bootc-image-builder (BIB) `anaconda-iso`** *(retired, ADR-0008 Phase 5/7)*: the image is embedded in the ISO; Anaconda installs it offline; a kickstart `%post` stack repoints the origin, tunes the filesystem, stages MOK enrollment, and rsyncs baked Flatpaks. This was the published ISO until June 2026; it is documented below as history. BIB itself is still used, but only to emit the `qcow2` the QEMU smoke gate boots (chapter 9), never an ISO.
- **Path B, Titanoboa live ISO** (ADR-0008): the official and only published ISO. A real live GNOME session whose squashfs *is* a `margine-live` OCI layer, with Anaconda WebUI installing `margine:stable` from the registry.

Both satisfy the same install-time invariants: registry origin = `ghcr.io/.../margine:stable`, btrfs + `compress=zstd:1`, two-tier MOK enrollment, ~38 BAKE Flatpaks present at first login.

## 10.1 Path A — bootc-image-builder Anaconda ISO (retired / historical)

> **Status:** the Anaconda-ISO path was retired per ADR-0008 (Phase 5 made Titanoboa the default, Phase 7 removed BIB's ISO matrix). It no longer produces a published artifact; BIB now emits only the `qcow2` used by the smoke gate. This section is kept as a record of *how it used to work*, the kickstart logic it pioneered was ported nearly verbatim into the Titanoboa path (§10.2).

BIB consumes a bootc image plus a TOML config and emits `qcow2`, `raw`, `vmdk`, or `anaconda-iso`. The qcow2 path (the one still in use, it feeds the QEMU smoke gate, chapter 9) needs almost nothing:

```toml
[[customizations.filesystem]]
mountpoint = "/"
minsize = "20 GiB"
```
*`margine-image/disk_config/disk.toml` (entire file).* The qcow2 exists to boot in CI; 4 lines suffice.

The ISO config is 304 lines, nearly all of it an embedded kickstart under `[customizations.installer.kickstart] contents = """..."""`.

### The installer-image trick (BAKE Flatpaks at OCI build time)

BIB's ISO packs the input image's rootfs as the *installer environment*. Margine exploits that: instead of feeding `margine:stable` to BIB directly, CI first builds a transient `margine-installer` image that is `margine:stable` + ~29 Flatpaks pre-installed into `/var/lib/flatpak`:

```dockerfile
ARG BASE_IMAGE=ghcr.io/daniel-g-carrasco/margine:stable
ARG FLATPAK_LIST_FILE=flatpaks-base

FROM ${BASE_IMAGE}
ARG FLATPAK_LIST_FILE

RUN --mount=type=bind,source=.,target=/src,rw \
    FLATPAK_LIST_FILE="${FLATPAK_LIST_FILE}" /src/build.sh

RUN bootc container lint
```
*`margine-image/installer/Containerfile`.* This image is never published as a `:stable` tag, it exists only as `margine-installer:run-<run_id>` to be BIB's input. The bind mount keeps the list/script out of the final layers.

`installer/build.sh` needs two odd lines before `flatpak install` works inside `podman build`:

```bash
mkdir -p "$(realpath /root)"
mount -o remount,rw /proc/sys
```
*`margine-image/installer/build.sh:29-30`.* flatpak's `apply_extra` (Reaper, Steam, openh264 binary blobs) runs under bwrap, which needs a real `/root` and writable `/proc/sys/user/max_user_namespaces`. The build itself must run with `--cap-add sys_admin --security-opt label=disable` (see the CI snippet below).

A subtle parsing bug lives here too: the list file allows inline comments, and an un-stripped `com.github.tchx84.Flatseal  # Flatpak permissions GUI` passes `#` as a literal Flatpak ID, `flatpak install` fails with `Invalid id #: Name can't start with #` (build #27075455521). The fix is a sed strip of trailing comments before word-splitting (`installer/build.sh:52-54`).

### Kickstart: %pre disk autodetect + partitioning

```text
%include /tmp/part-include.ks
zerombr
clearpart --all --initlabel --disklabel=gpt
part /boot/efi --fstype=efi --size=4096 --label=ESP
part / --fstype=btrfs --grow --label=margine_root
bootloader --timeout=1
```
*Historical: this lived in the deleted `disk_config/iso-gnome.toml`; the `%pre` autodetect survives in `live-env/src/anaconda/interactive-defaults.ks` (the WebUI path drops the explicit `clearpart`/`part`).* A `%pre` script enumerates `/sys/block/*`, filters out `loop*|ram*|zram*|sr*|fd*|md*|dm-*`, read-only, and removable devices, and — if exactly one candidate remains — writes `ignoredisk --only-use=<dev>` into `/tmp/part-include.ks`. Single-disk machines install without a disk-selection click; multi-disk machines fall back to explicit Anaconda selection. The 4 GiB ESP is deliberate headroom for future UKI/sealed-boot work (ADR-0007).

### %post stack — the four jobs

**1. Repoint the origin (`--erroronfail`).** BIB installs from the *embedded* image snapshot; without this, `bootc upgrade` would forever poll a URI that never updates:

```text
%post --erroronfail
bootc switch --mutate-in-place --transport registry ghcr.io/daniel-g-carrasco/margine:stable
%end
```
*Historical (deleted `iso-gnome.toml`); now `live-env/src/anaconda/post-scripts/bootc-switch.ks`.* `--mutate-in-place` edits the just-installed deployment's origin file instead of staging a new deployment. This is the only `%post` allowed to fail the install, a wrong upgrade origin is a real defect.

**2. Stage MOK enrollment before the first reboot (`--nochroot`).** Margine ships a CachyOS kernel signed with its own MOK (chapter 5); `mokutil --import` writes a pending request into EFI variables so shim opens MokManager on the very first post-install reboot:

```text
log "Setting MokManager timeout to direct entry"
mokutil --timeout -1 || log "WARN: failed to set MokTimeout; continuing"

log "Importing Margine MOK request"
if printf '%s\n%s\n' 'margine-os' 'margine-os' | mokutil --import "$MOK_CERT"; then
  log "MOK import request submitted — shim should launch MokManager on the next boot"
else
  log "WARN: mokutil import failed — first-boot mok-enroll.service remains fallback"
fi
```
*Historical (deleted `iso-gnome.toml`); now `live-env/src/anaconda/post-scripts/secureboot-enroll-key.ks`.* `--timeout -1` disables shim's 10 s auto-continue. The cert is located inside the target deployment (`/mnt/sysimage/ostree/deploy/default/deploy/*.0/usr/share/cert/MOK.der`). Every exit path is soft: `mok-enroll.service` in the image re-stages the request at first boot if the user misses MokManager (two-tier enrollment, PR #88).

**3. zstd compression.** Anaconda's btrfs default has *no* compression. Two layers because they cover different windows: `btrfs property set / compression zstd` affects all new writes immediately; a python3 inline patch appends `compress=zstd:1` to the `/` btrfs line in `/etc/fstab` for durability (python3 instead of sed, backslash escaping inside TOML triple-quoted strings is misery). Already-installed `/usr` content is not recompressed; the win is `/var` and `/home` growth (lines 139-218, not `--erroronfail`: QoL, not install-critical).

**4. Flatpak rsync (`--nochroot`).** ostree+bootc reset `/var` per deployment, so the installer's pre-baked `/var/lib/flatpak` must be copied into the target deployment:

```text
DEPLOY_DIR=$(ls -d /mnt/sysimage/ostree/deploy/default/deploy/*.0 2>/dev/null | head -1)
...
rsync -aAXUHK --open-noatime /var/lib/flatpak "$DEPLOY_DIR/var/lib/"
```
*Historical (deleted `iso-gnome.toml`); now `live-env/src/anaconda/post-scripts/install-flatpaks.ks`.* Belt-and-suspenders: every BAKE app is also listed in `/usr/share/flatpak/preinstall.d/margine-defaults.preinstall`, so a silent rsync failure degrades to a first-boot download via `flatpak-preinstall.service`, not missing apps.

> **Lesson, install-time `flatpak install` silently OOMs.**
> *Symptom:* the 2026-06-04 fresh install completed "successfully" but first boot had no Flatpaks.
> *Root cause:* the earlier `%post --nochroot` did `flatpak install --system` of the ~5 GB BAKE set *at install time*, inside the installer environment's small tmpfs `/tmp`, it died quietly (`--noninteractive` returns 0 on partial failure).
> *Fix:* the Bazzite installer-image pattern (2026-06-05): downloads move to OCI build time on a CI runner with real disk; install time is reduced to an rsync. The post-mortem was documented inline in the BIB kickstart (since deleted); the live-ISO path keeps the same build-time-bake / install-time-rsync split in `live-env`.

### Trimming Anaconda modules

```toml
[customizations.installer.modules]
enable = [
  "org.fedoraproject.Anaconda.Modules.Storage",
  "org.fedoraproject.Anaconda.Modules.Runtime",
  "org.fedoraproject.Anaconda.Modules.Network"
]
disable = [
  "org.fedoraproject.Anaconda.Modules.Security",
  "org.fedoraproject.Anaconda.Modules.Services",
  "org.fedoraproject.Anaconda.Modules.Users",
  "org.fedoraproject.Anaconda.Modules.Subscription",
  "org.fedoraproject.Anaconda.Modules.Timezone"
]
```
*Historical (deleted `iso-gnome.toml`): a BIB-only `[customizations.installer.modules]` block with no direct Titanoboa equivalent, the live ISO trims spokes through Anaconda's profile instead (§10.2).* Users/timezone/services come from Margine's own first-login bootstrap (`ujust margine-bootstrap`), so their installer spokes are dead weight. Network stays enabled: on a laptop the user needs the Wi-Fi picker (wired DHCP auto-configures without it).

### CI invocation (historical)

This was the matrix-conditional BIB invocation while the `anaconda-iso` entry still existed; today the `build_disk` job only runs the `qcow2` branch, so it passes `./disk_config/disk.toml` unconditionally:

```yaml
- name: Build disk image
  uses: osbuild/bootc-image-builder-action@019bb59c5100ecec4e78c9e94e18a840110f7a0b  # v0.0.2
  with:
    builder-image: ${{ env.BIB_IMAGE }}
    # was: matrix.disk-type == 'anaconda-iso' && './disk_config/iso-gnome.toml' || ...
    config-file: './disk_config/disk.toml'
    image: ${{ format('{0}/{1}:{2}', env.IMAGE_REGISTRY, env.IMAGE_NAME, env.DEFAULT_TAG) }}
    rootfs: btrfs
    types: ${{ matrix.disk-type }}
```
*`margine-image/.github/workflows/build-disk.yml` (`build_disk` job).* One trap still encoded here: `rootfs: btrfs` is mandatory because Bluefin DX doesn't set the `containers.bootc.rootfs` OCI label, without it BIB dies with `DefaultRootFs missing`. (In the retired ISO branch, the build also consumed the *installer* tag, not `:stable`.)

### Why Path A was replaced

The `iso-gnome.toml` kickstart hit BIB's architectural ceiling: 300+ lines of kickstart inside a TOML string, BIB upstream in maintenance mode (Universal Blue retired it in March 2025, ublue-os/main#468), no live "try before install" session, the Anaconda GTK spoke not pre-selecting single disks, and a MokManager that never appeared on a Framework 13 where Bluefin's ISO showed it. Hence ADR-0008, and `iso-gnome.toml` was subsequently deleted; its four kickstart jobs now live as the `.ks` fragments described in §10.2.

## 10.2 Path B — Titanoboa live ISO (the published ISO)

Titanoboa (`ublue-os/titanoboa`) is a ~150-line bash ISO assembler implementing the Container-native ISO contract v0.1.0 (`ondrejbudai/bootc-isos`). It does almost nothing: `mksquashfs /rootfs → /LiveOS/squashfs.img`, copy `/rootfs/usr/lib/modules/*/{vmlinuz,initramfs.img}` to `/images/pxeboot/`, copy the EFI tree, generate `grub.cfg` from `/usr/lib/bootc-image-builder/iso.yaml` (hard-required, exits 1 if absent), build a FAT32 `uefi.img`, `xorriso -as mkisofs`. **All** customization must already be inside the input image.

### The post-#138 contract: two inputs, one output

Since PR #138 (2026-05-19, "Only use container images as the only source of truth") the action has exactly `image-ref` (required) and `iso-dest` (optional) as inputs, and `iso-dest` as output. The previous 12-input API (`flatpaks-list`, `hook-post-rootfs`, `kargs`, ...) was **silently dropped**, consumers passing the old inputs get a `##[warning]Unexpected input(s)` and a broken ISO. Bluefin's CI ran red for 3+ weeks because of this. Margine pins by SHA, Renovate-disabled:

```yaml
- name: Build Live ISO (Titanoboa)
  id: titanoboa
  # Pinned to env.TITANOBOA_REF (a personal margine-pins fork).
  uses: daniel-g-carrasco/titanoboa@cce73fc476e97fed626283afb6c518e0882a12d7
  with:
    image-ref: ${{ steps.live.outputs.live_tag }}
    iso-dest: ${{ github.workspace }}/margine-live.iso
```
*`margine-image/.github/workflows/build-disk.yml` (`build_iso_titanoboa` job).* The pin is a personal fork, `daniel-g-carrasco/titanoboa` (branch `margine-pins`, SHA-pinned via the `TITANOBOA_REF` env, the snippet above shows the current SHA): upstream's post-#138 HEAD plus the margine patch set, upstream PR #147's `mksquashfs -e` ordering fix (the gzip-fallback Lesson below), the raw `extra_cfg` grub fragment (proposed upstream as #148), and a grub.cfg directory-glob fix so plain files at the ESP root (`EFI/MOK.der`) don't break the build. `image-ref` is a transient `margine-live:ci-run-<run_id>` tag pushed just before, Titanoboa issue #141 (open) hardcodes `podman pull` of the ref, so a local-only tag is not enough. Pin bumps require an explicit follow-up ADR.

### iso.yaml — label, kargs, and the initrd rename

```yaml
label: "Margine-Live"
grub2:
  default: 0
  timeout: 5
  entries:
    - name: "Install Margine"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=Margine-Live enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
```
*`margine-image/live-env/src/iso.yaml:19-26`.* Three load-bearing details: (1) `rd.live.image` + `root=live:CDLABEL=<label>` are mandatory or dmsquash-live cannot find `/LiveOS/squashfs.img` and the boot panics; `CDLABEL` must match `label` exactly. (2) The initrd path is `initrd.img`, **not** `initramfs.img`, Titanoboa renames `/usr/lib/modules/*/initramfs.img` to `/images/pxeboot/initrd.img` on copy. (3) `enforcing=0` is live-session-only convenience; the installed system is enforcing.

### live-env: Containerfile + build.sh

```dockerfile
ARG BASE_IMAGE=ghcr.io/daniel-g-carrasco/margine:stable
FROM ${BASE_IMAGE}
RUN --mount=type=bind,source=src,target=/src,rw \
    /src/build.sh
```
*`margine-image/live-env/Containerfile` (trimmed).* Built with `--cap-add sys_admin --security-opt label=disable` (dracut + flatpak/bwrap). The squashfs of the produced ISO *is* this image's rootfs, try-before-install is literally the distro.

`build.sh` runs in three phases (one git commit per phase, mapping ADR-0008 §6):

**Phase 1, bootable.** First, the single-kernel invariant: Titanoboa copies `/usr/lib/modules/*/...` with "behaviour unspecified" for multiple kernels, and a `dnf install` later in the script could pull a second one. So `assert_single_kernel` runs at the start *and* at the very end. Margine deliberately keeps the CachyOS kernel in the live env (no Bazzite-style vanilla-kernel swap), the accepted cost is that live boot under Secure Boot needs SB disabled until the MOK is enrolled.

Then dracut-live:

```bash
dnf install -y --setopt=install_weak_deps=False \
  dracut-live livesys-scripts grub2-efi-x64-cdboot

DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
  --add "dmsquash-live dmsquash-live-autooverlay" \
  "/usr/lib/modules/${KERNEL}/initramfs.img" "${KERNEL}"
```
*`margine-image/live-env/src/build.sh:72-82`.* `--no-hostonly` is mandatory: Fedora defaults to `hostonly=yes`, which strips dmsquash-live, and the live ISO kernel-panics looking for a real root. `dmsquash-live-autooverlay` gives the session a writable overlay.

livesys session + EFI assembly:

```bash
echo "livesys_session=gnome" > /etc/sysconfig/livesys      # (sed if file exists)
systemctl enable livesys.service livesys-late.service

mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
test -d /boot/efi/EFI/fedora || { echo "ERROR: EFI tree not assembled..." >&2; exit 1; }
cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi
```
*`margine-image/live-env/src/build.sh:87-112` (condensed).* bootc images keep EFI binaries under `/usr/lib/efi/`; Titanoboa looks under `/boot/efi/EFI`, the copy bridges the two layouts. The glob guard fails the build loudly instead of producing a cryptic failure deep in `build_iso.sh`. `fbx64.efi` is the removable-media fallback the firmware loads when no NVRAM boot entry exists (the USB-stick case).

`/var/tmp` sizing: in a booted live ISO, `/` is an overlayfs whose upperdir sits on a small tmpfs under `/run`. Anaconda's ostree install needs gigabytes of scratch in `/var/tmp`, so build.sh installs a `var-tmp.mount` unit with `Options=size=50%%,nr_inodes=1m` (`%%` because `%` is a systemd specifier) mounting a half-of-RAM tmpfs there (lines 118-133). Finally `iso.yaml` is copied to `/usr/lib/bootc-image-builder/iso.yaml`, the path Titanoboa hard-requires.

> **Lesson, the BIOS `[ -f ]` guard: the "hybrid" ISO that isn't.**
> *Symptom:* build logs claimed "BIOS hybrid boot: /usr/lib/grub/i386-pc present", implying a BIOS-bootable ISO. It is UEFI-only.
> *Root cause:* Titanoboa `build_iso.sh:32` tests the i386-pc *directory* with `[ -f ]`, always false, so the GRUB BIOS modules are never copied, and its xorriso call has no El Torito BIOS image (`-b`) anyway. Found in the 2026-06-09 full build-log scan.
> *Fix:* log the truth instead of a comforting lie (BIOS stays non-gating per ADR-0008 §4, all reference hardware is UEFI):
> ```bash
> if [[ -d /usr/lib/grub/i386-pc ]]; then
>   echo "NOTE: /usr/lib/grub/i386-pc present, but current Titanoboa produces a UEFI-only ISO (no BIOS El Torito; upstream build_iso.sh:32 -f-vs-directory bug)"
> ```
> *`margine-image/live-env/src/build.sh:61-65`.*

> **Lesson, mksquashfs silently falls back to gzip.**
> *Symptom:* the squashfs was larger and faster-built than zstd-19 should produce; the requested compression never applied.
> *Root cause:* in Titanoboa, `-comp zstd -Xcompression-level 19` is placed *after* `-e` on the mksquashfs command line, mksquashfs swallows everything after `-e` as exclude names and silently falls back to its gzip default. Same 2026-06-09 build-log scan; this class of bug is invisible unless you read the tool's own banner output.
> *Fix:* upstream PR `ublue-os/titanoboa#147` reorders the flags; Margine carries it directly by pinning `TITANOBOA_REF` at the personal fork `daniel-g-carrasco/titanoboa`, whose patch set carries exactly that fix, so the shipped ISO is zstd-compressed, not gzip.

**Phase 2, BAKE Flatpaks.** Same bwrap prep and comment-stripping as `installer/build.sh`, then `flatpak install --system --noninteractive --or-update flathub $APPS` from `live-env/src/flatpaks` (lines 145-171). Then the live session is defended against the user:

```bash
cat >/etc/systemd/system/var-lib-flatpak.mount <<'EOF'
[Mount]
What=/var/lib/flatpak
Where=/var/lib/flatpak
Type=none
Options=bind,ro
EOF
systemctl enable var-lib-flatpak.mount
```
*`margine-image/live-env/src/build.sh:175-188` (trimmed).* A read-only bind of `/var/lib/flatpak` over itself: the user can poke around the live desktop but cannot taint the baked set before it is rsync'd into the install target.

**Phase 3, Anaconda WebUI.** `dnf install firefox anaconda-live anaconda-webui libblockdev-{btrfs,lvm,dm}`, `mkdir /var/lib/rpm-state` (WebUI requires it), install the profile, copy `post-scripts/*.ks`, and *append* (not replace) Margine's fragment to the `interactive-defaults.ks` that anaconda-live ships, the base carries liveinst integration that must be preserved. Then a defensive loop disables units that are meaningless or harmful in a throwaway live session (`uupd.timer`, `flatpak-preinstall.service`, `brew-*`, `tailscaled`, `bazaar.service`, ...), checking each unit exists first so a renamed unit never fails the build (lines 227-252).

### profile.d detection and storage defaults

```ini
[Profile]
profile_id = margine

[Profile Detection]
os_id = fedora
variant_id = margine

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
webui_web_engine = slitherer
```
*`margine-image/live-env/src/anaconda/profile.d/margine.conf` (trimmed).* Margine keeps `ID=fedora` in os-release (Bluefin inheritance), so `os_id` alone would collide with stock Fedora, `variant_id=margine` must also match, and both must hold for the profile to activate. `slitherer` is the WebUI engine Bluefin/Bazzite ship in production; falling back to GTK Anaconda is a one-line change (`webui_web_engine = none`).

> **Lesson, explicit `part` crashes Anaconda WebUI 68.**
> *Symptom:* WebUI dies at startup with "Reading information about the computer failed" (DBus `InvalidArgs`).
> *Root cause:* any kickstart `part`/`clearpart` directive makes Anaconda select the CUSTOM partitioning method, which never publishes the `Storage.Partitioning.Automatic` DBus interface, and anaconda-webui 44-68 (Fedora 44 ships 68) queries that interface unconditionally. Fixed upstream in anaconda-webui 69 (commit `135c87881`, 2026-03-18), not yet in F44.
> *Fix (PR #92):* drop explicit partitioning entirely; let the profile's `[Storage] default_partitioning` drive the AUTOMATIC flow (exactly like Aurora/Bazzite). The `%pre` autodetect is kept, it only emits `ignoredisk --only-use=<dev>`, which does *not* select CUSTOM, so it is WebUI-safe. Cost: the ESP stays at Anaconda's hardcoded ~600 MiB (no profile key can enlarge it on the AUTOMATIC path); the 4 GiB ESP from Path A is deferred until F44 ships anaconda-webui ≥ 69. ~600 MiB still holds several UKIs. Documented in the `interactive-defaults.ks` header (lines 6-22).

### interactive-defaults.ks: ostreecontainer + %include chain

```text
%include /tmp/part-include.ks

ostreecontainer --url=ghcr.io/daniel-g-carrasco/margine:stable --transport=registry --no-signature-verification

%include /usr/share/anaconda/post-scripts/bootc-switch.ks
%include /usr/share/anaconda/post-scripts/zstd-compress.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
```
*`margine-image/live-env/src/anaconda/interactive-defaults.ks:64-84` (comments trimmed).* `ostreecontainer --transport=registry` pulls `margine:stable` from GHCR at install time, chosen over pre-pulling into the ISO's containers-storage (`--transport=containers-storage`), which would add ~5-6 GB and break the 10 GB ISO budget. Consequence: installs now need network (the retired Path A was offline-capable), the standing #1 revisit item since cutover. The 300-line TOML monolith of the old Path A became four self-documenting `.ks` fragments, same four jobs, ported nearly verbatim. Order matters: switch origin, tune fs, stage MOK, bake apps.

One deliberate delta in the Flatpak rsync: Path B uses Bluefin's production incantation `rsync -aAXUHKP --filter='-x security.selinux'` (`post-scripts/install-flatpaks.ks:39`), preserve POSIX xattrs/ACLs, strip SELinux labels and let ostree-finalize relabel. Wrong labels mean baked Flatpaks fail to launch with AVC denials.

### CI wiring for Path B

The Titanoboa job (`build_iso_titanoboa` in `build-disk.yml`) is the ISO build since the Phase 5 cutover (2026-06-11); the old BIB `anaconda-iso` matrix entry is gone. Notable plumbing: ubuntu-24.04 runners have ~14 GB free on `/`, but the zstd squashfs of a ~14 GB rootfs + the base image in storage + the ISO need far more, so rootful podman storage is remounted onto an 80 GB btrfs loopback on the ephemeral `/mnt` SSD with `compress-force=zstd:2` (lines 371-384, mirroring Bazzite). After the build, a prune step keeps only the newest 3 `margine-live` GHCR tags. Test ISOs are pushed to the Internet Archive's auto-expiring `test_collection` (`publish-titanoboa-test-iso.yml`) because GHA artifact egress to residential connections crawls at ~1-1.5 MB/s, 2-4 h for an 8 GB ISO.

## 10.3 Escape hatch: plain `bootc install to-disk`

No custom ISO required: boot any stock Fedora live USB, then

```
sudo podman run --rm --privileged --pid=host \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  ghcr.io/daniel-g-carrasco/margine:stable \
  bootc install to-disk --wipe /dev/nvme0n1
```

The image installs *itself*, bootc ships the installer logic in every image. You lose everything the kickstarts do (MOK staging, zstd fstab patch, Flatpak bake, guided partitioning), so first boot is slower and Secure Boot needs manual `mokutil`. Useful for headless boxes, VMs, and recovery; not the documented end-user path.

## 10.4 Alternatives & other distros

- **Titanoboa**, Universal Blue's direction. **Bazzite**: only production-grade post-#138 consumer, but pins `Zeglius/titanoboa@revamp-pr` (the #138 author's fork). **Bluefin** (`projectbluefin/iso`): pins `@main` while still passing pre-#138 inputs, red since 2026-05-19; reference for content, not workflow. **Aurora** (`get-aurora-dev/iso`): green, but pinned *pre*-#138 (`840217d9`, 2026-01-04), old 12-input API. Margine: a personal post-#138 fork (`daniel-g-carrasco/titanoboa`) pinned by SHA, upstream HEAD plus PR #147, Margine's official ISO path. Trade-off across all: minimal assembler, everything lives in your image; you inherit its bugs until your next pin bump.
- **bootc-image-builder `anaconda-iso`**, Fedora/CentOS bootc's documented path; Margine's *former* published ISO (retired per ADR-0008, maintenance-mode upstream, no live session, kickstart-in-TOML scales badly). BIB is still used to emit the smoke-gate qcow2, just not an ISO.
- **lorax / livemedia-creator**, how Fedora builds official **Silverblue/Kinoite** ISOs (Anaconda + ostree remote); full Fedora release engineering machinery, heavyweight to self-host.
- **Anaconda `bootc` kickstart verb** (Fedora, Dec 2025), the long-term BIB successor; too new for Margine v1, new partitioning model to learn.
- **kiwi**, **openSUSE MicroOS/Aeon** image/ISO builder; mature multi-format, XML descriptions, not container-native (their atomic model is btrfs-snapshot, not OCI).
- **mkosi**, systemd's image builder (**ParticleOS**); first-class UKI/sealed-boot, builds from package lists rather than consuming an OCI image.
- **Readymade** (FyraLabs; **Ultramarine**, tauOS), bootc support merged 2025-04; Bluefin evaluating (titanoboa#66); not production-ready as of 2026-06. Candidate ADR-0010 for Margine post-Phase 7.
- **Calamares**, distro-independent GUI installer (Manjaro, KDE neon); no bootc/ostree integration, rejected for phase 1.
- **Agama**, openSUSE's web-based installer; SUSE-ecosystem-shaped.
- **Vanilla OS**, own first-setup installer over **ABRoot** A/B partitions; bespoke, not reusable.
- **NixOS**, `nixos-install` from any live medium + a flake; declarative but a different universe (no OCI delivery).
- **ChimeraOS**, `frzr` deploys read-only btrfs images from GitHub releases; simplest possible "installer", no Anaconda at all.
- **`bootc install to-disk` from a stock Fedora USB**, zero pipeline cost, zero polish (§10.3).

The pattern worth stealing regardless of tool: keep install-time logic in small, individually testable kickstart fragments shipped *inside the image* (`/usr/share/anaconda/post-scripts/*.ks`), make exactly one of them fatal (`bootc switch --erroronfail`), and let everything else degrade to a first-boot fallback.


---

# 11. Shipping and day-2 operations

A bootc distro has two delivery products: the OCI image (the thing installed systems track daily) and the install media (the thing new users download once). They have different bandwidth profiles, different trust models, and different failure modes, Margine ships them through two different channels: GHCR for the image, Internet Archive for the ISO. Day-2 is everything after: upgrade orchestration, staged deployments, rollback, /etc drift.

## 11.1 GHCR tag strategy

Margine publishes exactly one image name with a small, rigid tag grammar:

| Tag | Written by | Meaning |
|---|---|---|
| `:candidate` | `build.yml` on every main push / weekly cron | Built, statically validated, **not yet boot-tested** |
| `:candidate.YYYYMMDD` | `build.yml` | Dated candidate, for forensics |
| `:pr-N` | `build.yml` on PRs labeled `vm-test` | Transient; rebase a lab VM onto it, GC'd later |
| `:stable` | `smoke-boot.yml` promotion step | The only tag clients track |
| `:stable.YYYYMMDD`, `:YYYYMMDD` | `smoke-boot.yml` | Dated stable aliases for pinning/rollback by date |

There is deliberately no `:latest`. `:latest` conflates "most recently built" with "recommended"; on an OS image those must differ, because the recommendation gate (a real boot) runs *after* the build. The tags are emitted by `docker/metadata-action`:

```yaml
# margine-image/.github/workflows/build.yml
tags: |
  type=raw,value=${{ env.CANDIDATE_TAG }},enable=${{ github.event_name != 'pull_request' }}
  type=raw,value=${{ env.CANDIDATE_TAG }}.{{date 'YYYYMMDD'}},enable=${{ github.event_name != 'pull_request' }}
  type=ref,event=pr,prefix=pr-,enable=${{ github.event_name == 'pull_request' }}
```

Pushes capture the manifest digest once and reuse it, all tags point at the same manifest, and cosign signs by digest, never by tag (tag-based signing is racy: the tag can move between sign and verify):

```yaml
# margine-image/.github/workflows/build.yml — "Push rechunked image to GHCR"
for tag in ${{ steps.metadata.outputs.tags }}; do
  sudo skopeo copy --retry-times 3 \
    --dest-creds="${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}" \
    --digestfile=/tmp/digest.txt \
    "${{ steps.rechunk.outputs.ref }}" \
    "docker://${IMG_FULL}:${tag}"
  if [[ -z "$DIGEST" ]]; then
    DIGEST="$(cat /tmp/digest.txt)"
  fi
done
echo "image_ref=${IMG_FULL}@${DIGEST}" >> "$GITHUB_OUTPUT"
```

`--digestfile` is the load-bearing flag: the `sign` job receives `${IMG_FULL}@sha256:...` and never resolves a tag.

### Promotion: digest-preserving copy, gated on a real boot

`smoke-boot.yml` resolves `:candidate` to an immutable digest once (the "Resolve image ref to digest" step → `${PINNED}`), boots *that* qcow2 in QEMU (chapter 9), and only then promotes the exact digest it booted:

```yaml
# margine-image/.github/workflows/smoke-boot.yml — "Promote candidate → stable"
- name: Promote candidate → stable (only if boot passed)
  if: success() && steps.boot.outputs.passed == 'true'
  run: |
    DATE_TAG="$(date -u +%Y%m%d)"
    for promo_tag in stable "stable.${DATE_TAG}" "${DATE_TAG}"; do
      sudo skopeo copy --retry-times 3 --preserve-digests \
        "docker://${PINNED}" \
        "docker://${REGISTRY_IMAGE}:${promo_tag}"
    done
```

`--preserve-digests` guarantees `:stable` is bit-identical to the manifest that actually booted, no rebuild, no re-rechunk between test and release. The promotion is a registry-side pointer move. Pinning to `${PINNED}` (rather than re-resolving the moving `:candidate` tag) closed a void-gate window where a build finishing mid-smoke could get the never-booted digest promoted; a `concurrency: group: smoke-boot` (queue, don't cancel) keeps two promotions from splitting the stable tags across digests.

### Digest pins on the client

A client can freeze on a known-good build with either form:

```sh
sudo bootc switch ghcr.io/daniel-g-carrasco/margine:stable.20260608   # dated alias
sudo bootc switch ghcr.io/daniel-g-carrasco/margine@sha256:<digest>   # hard pin
```

A hard digest pin disables `bootc upgrade` progress by definition (the ref never changes); dated aliases are the practical middle ground. Margine also ships a client-side watchdog so a *silent* pipeline failure doesn't leave users unknowingly frozen:

```python
# margine-image/build_files/system_files/usr/libexec/margine-staleness-check
r = run(["skopeo", "inspect", "--no-tags", f"docker://{image_ref}"])
created = json.loads(r.stdout)["Created"]  # ISO 8601
age_days = (time.time() - created_ts) / 86400
if age_days < WARN_AGE_DAYS:  # 7 days, critical at 14
    sys.exit(0)
```

A user systemd timer (every 12 h, installed via `/etc/skel`) runs `skopeo inspect` against the booted image ref and raises a desktop notification when `:stable` is older than 7 days, "either the build pipeline is broken, or upstream has genuinely paused; either way the user should know."

## 11.2 ISO distribution: torrent-first via Internet Archive

The ISO is ~5-9 GB and the origin server is a home box behind Cloudflare Free. The distribution model (from `docs/spec/19-iso-distribution.md`):

```
build-disk.yml
  ├──▶ Internet Archive (`ia upload`)
  │        ↓ IA derives torrent + 3 HTTP mirrors, seeds forever
  └──▶ rsync to edge VM (files.the-empty.place)
           ↓ index.html (magnet + IA mirror links), SHA256SUMS, 7-day .iso fallback
```

Rationale, condensed: Cloudflare Free TOS discourages serving large binaries from the proxy; an ADSL-class uplink dies under one concurrent ISO download; and the home server should not be a single point of failure for *past* releases. IA solves all three: it auto-derives a `.torrent` + magnet + HTTP mirrors for every upload and hosts them indefinitely, while the origin serves only HTML and checksums.

The upload runs in a **separate job** (`publish_ia`) downstream of `build_disk`, connected by a GHA artifact. This split exists purely for rerun isolation: when the IA upload fails (it does, S3 ingest 503s under load), `gh run rerun --failed <run-id>` redoes only the upload, not the 15-17 min bootc-image-builder run.

```yaml
# margine-image/.github/workflows/build-disk.yml — publish_ia
ia --config-file "$IA_CONFIG_FILE" --debug upload "$IDENTIFIER" \
  "$ARTIFACT" "$OUTDIR/SHA256SUMS" \
  --retries 5 \
  --sleep 60 \
  --metadata="mediatype:software" \
  --metadata="collection:opensource" \
  --metadata="title:${TITLE}" \
  ...
```

Hard-won `ia` 5.x CLI facts encoded in the workflow comments: `ia upload --verbose` does not exist (run #26787945599 failed on it); top-level `-l` is a flag, not `-l info` (run #26789968571 — argparse ate `info` as the positional command); `--debug` is the actual progress knob. `--retries 5 --sleep 60` because IA's S3 endpoint 503s routinely on multi-GB multipart uploads. After upload, a 25-minute poll loop waits for `*_archive.torrent` to appear (`ia list "$IDENTIFIER" | grep '_archive\.torrent$'`) before generating the index page, degrading to HTTP-only links with a warning if derive is slow.

> **Lesson, SHA256SUMS paths must match the published layout.**
> *Symptom:* run #26789024483's `publish_ia` failed `sha256sum -c SHA256SUMS` on the downloaded artifact.
> *Root cause:* the build side wrote SHA256SUMS with build-side paths (`bootiso/install.iso`); after artifact transit and on IA, where the file is served at the item root, those paths resolve nowhere. Two layouts, one checksum file.
> *Fix:* generate relative to the artifact dir at build time, then **regenerate for the published layout** before upload:
> ```bash
> # build-disk.yml, "Locate ISO + verify integrity"
> (cd "$OUTDIR" && sha256sum -c SHA256SUMS)          # verify artifact transit
> ( cd "$(dirname "$ARTIFACT")" && sha256sum "$BASE" ) > "$OUTDIR/SHA256SUMS"  # rewrite: basename only
> ```
> End-user UX contract: download `install.iso` + `SHA256SUMS` as siblings from IA, run `sha256sum -c SHA256SUMS`, done.

> **Lesson, size your timeouts to the slow third party, not your build.**
> *Symptom:* run #27166954601's `publish_ia` was cancelled at the 180-minute job cap mid-upload.
> *Root cause:* IA's S3 ingest for a ~9 GB ISO ran past 3 h during a degraded window.
> *Fix:* `timeout-minutes: 350` (GHA hard cap is 6 h) and rely on the job split for retries. The comment in the file documents the incident inline, workflows are the changelog.

## 11.3 The website pipeline is part of the product

The download page is not hand-maintained. The site (`margine-os-1084ca72`, served at `margine.dev`) hardcodes four release URLs (IA details page, `.torrent`, direct HTTP, SHA256SUMS) derived from a single constant `LATEST_ISO_DATE` in `src/routes/index.tsx`. After `publish_ia` succeeds, a `bump_site` job in the same workflow opens, and auto-merges, a PR against the site repo:

```bash
# margine-image/.github/workflows/build-disk.yml — bump_site
sed -i "s|LATEST_ISO_DATE = \"$OLD_DATE\"|LATEST_ISO_DATE = \"$NEW_DATE\"|" src/routes/index.tsx
...
gh pr create --repo daniel-g-carrasco/margine-os-1084ca72 \
  --base main --head "$BRANCH" \
  --title "chore(release): bump LATEST_ISO_DATE to ${NEW_DATE}" ...
gh pr merge ... --squash --auto --delete-branch \
  || echo "::warning::bump PR auto-merge failed — falls back to manual squash-merge"
```

A webhook deploy picks the merge up in ~2-3 minutes; the maintainer does nothing per-release. The cross-repo write uses a fine-grained PAT (`SITE_BUMP_TOKEN`, Contents+PR write scoped to the site repo only) and the job **no-ops with a warning** when the secret is absent instead of failing the release. Idempotency guards: skip if the constant already equals today's date; skip if a PR for the same date branch is already open.

One UX detail preserved in the comments: the Hero used to expose a `magnet:?` button composed from the torrent's btih, retired 2026-06-07 because Fragments (the preinstalled torrent client) rejected valid magnets with arbitrary tracker lists, the button now links to the `.torrent` file, which `LATEST_ISO_TORRENT` derives from the same date constant. Release automation shrank to a single-variable bump.

## 11.4 Client side: bootc upgrade + uupd orchestration

Margine maintains **no update orchestrator of its own**. The declaration is explicit:

```yaml
# build_files/40-spec-scripts/declarations/margine-atomic.yaml
updates:
  orchestrator: bluefin-uupd
  system:
    engine: bootc
    transport: ostree-image-signed
    image_ref: ghcr.io/daniel-g-carrasco/margine:stable
    require_reboot_judgment: true
```

Bluefin DX ships uupd (Universal Updater) with `uupd.timer` enabled; Margine inherits the unit unchanged. Per `docs/01-architecture.md`, one daily pass orders:

1. `bootc upgrade` (or `rpm-ostree upgrade` on layered installs);
2. `flatpak update` (system + user);
3. `brew update && brew upgrade` if Homebrew is present;
4. `distrobox upgrade --all`;
5. reboot indication via `notify-send` when a new deployment is staged (see "Update visibility and the extra-data watchdog" below for how Margine implements this and what guards the pass when a step wedges).

The ordering in step 1 is load-bearing: the OS image moves BEFORE the app steps, so even a run that later wedges on a flatpak has already staged the OS/security update. Two real incidents (2026-06-28 and 2026-07-08) proved both halves of this design: an extra-data flatpak froze step 2 for days, and the affected machine kept staging OS updates the whole time.

Host image, Flatpaks, brew, and distrobox containers move in one pass with one failure surface, the practical reason to prefer an orchestrator over N independent timers. The history matters here: Margine's earlier `scripts/update-all` (an rpm-ostree-first orchestrator with pre/post validators) and its Topgrade accessory profile were retired when the project moved onto Bluefin (ADR 0004 superseded by 0005). The Topgrade config survives as documentation of the boundary it enforced:

```toml
# docs/spec/config/topgrade.toml
[misc]
disable = [ "system", "firmware" ]
[linux]
rpm_ostree = false
bootc = false
```

Even when a generic updater *can* drive the base OS, don't let it: a base update stages a kernel, interacts with Secure Boot and rollback, and deserves a tool that understands deployments. The validators (`validate-atomic-layout`, `validate-cachyos-kernel`, ...) are deliberately **on-demand health checks, not update hooks**, they never block or gate uupd.

Context-awareness corollary: environments where updating is wrong must opt out. The live ISO disables the whole update surface at build time:

```bash
# margine-image/live-env/src/build.sh — units that must not run in a live session
for unit in \
  rpm-ostree-countme.service rpm-ostreed-automatic.timer bootloader-update.service \
  flatpak-preinstall.service brew-setup.service brew-upgrade.timer brew-update.timer \
  uupd.timer ublue-system-setup.service tailscaled.service; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl disable "$unit"
  fi
done
```

Defensive `list-unit-files` guard (Bazzite pattern): a renamed upstream unit never fails the ISO build.

### Staged deployment and reboot

`bootc upgrade` pulls the new manifest, checks out a new deployment under `/ostree/deploy/`, and **stages** it. Nothing visible changes until reboot; BLS bootloader entries are written by `ostree-finalize-staged.service` *during shutdown*, not at stage time. This is observable and worth teaching, because it confuses everyone once, `validate-staged-deployment` distinguishes the two states explicitly:

```bash
# build_files/40-spec-scripts/scripts/validate-staged-deployment
if [[ "$IS_STAGED" == "true" ]]; then
  info "Deployment is STAGED (bootc switch flow). BLS entries are not"
  info "rewritten now — ostree-finalize-staged.service does that at the"
  info "next shutdown, so GRUB sees the new entry on the boot AFTER."
  ok "BLS entry update is correctly deferred (this is normal)"
else
  # rpm-ostree rebase / non-staged path: entry must already exist.
  BLS_ENTRY=$("${SUDO[@]}" grep -lr "${STAGED_HASH:0:32}" /boot/loader/entries/ ...)
```

`rpm-ostree rebase` writes BLS entries immediately ("pending"); `bootc switch`/`upgrade` defers them ("staged"). A validator that asserts "entry must exist" fails spuriously on the bootc path unless it knows the difference.

After the reboot, a login-time oneshot compares the booted digest against the last recorded one and tells the user what just happened (`/usr/libexec/margine-upgrade-notify`, a vendor-enabled user unit in `graphical-session.target.wants`): "Now running: stable.20260608 / Digest: sha256:ab12...". Reboots that silently apply OS updates erode trust; a one-line toast fixes that. Two lessons are baked into it (2026-07-10): the unit must bind to `graphical-session.target`, not `default.target`, or the toast fires before the session's notification daemon exists; and the state file must advance only after `notify-send` succeeds, or a lost toast is lost forever.

### Update visibility and the extra-data watchdog

Staging is silent by design, so Margine makes the states visible instead of hoping the user checks:

- **`margine-staged-update-notify`** (user timer): one toast when a new deployment first appears staged ("reboot whenever it suits you"), a daily low-urgency nag once it has waited 2+ days, and a one-time notice when the watchdog excludes an app (below). The timer fires on the wall clock (`OnCalendar` + `Persistent=true`): a monotonic `OnUnitActiveSec` interval freezes across suspend and never fires on a laptop that mostly sleeps.
- **`margine-status`** shows the booted deployment (selected with `booted==true`, NOT `deployments[0]`, which is the staged one when an update is pending), a `Staged` line when a reboot would apply something, the last unattended-run health, and any watchdog-excluded apps.

The hang class that motivated the watchdog: EXTRA-DATA flatpaks (Reaper was the repeat offender) download their real payload from the vendor at update time, and flatpak's extra-data fetch has no timeout. When the vendor CDN drops the connection, the update process wedges forever holding the system flatpak lock: Bazaar and every flatpak operation block, and the nightly retry wedges again on the same app. Containment is layered:

1. a `TimeoutStartSec=30min` drop-in on `uupd.service` kills a wedged run (note: systemd timeouts count monotonic time, which stops during suspend, so one cycle can span days of calendar time on a laptop);
2. the drop-in's `OnFailure=` fires **`margine-update-watchdog`**: on a timeout it identifies the in-flight app from the journal, verifies it is extra-data, and records a strike; at 2 strikes in 7 days it `flatpak mask`s the app so unattended runs complete again;
3. the exclusion is surfaced (session toast + `margine-status`) with the recovery command: **`ujust margine-update-unblock`** unmasks, updates in the foreground where a stall is visible and Ctrl+C-able, and re-includes the app on success.

Policy consequence: no extra-data apps in the preinstall set (Reaper was removed 2026-07-10; it stays one click away in Bazaar).

## 11.5 Rollback, pinning, /etc merge and drift

**Rollback.** bootc keeps the previous deployment on disk. `sudo bootc rollback` flips the boot order so the previous deployment boots next; the GRUB menu offers the same choice interactively. Because `/etc` is per-deployment and `/var` is shared, rolling back reverts OS content and config defaults but not user data.

**Pinning.** Deployments are garbage-collected as new ones land (only current + previous are kept). Before a risky change, pin:

```sh
# docs/spec/02-install-lab.md — before the CachyOS kernel experiment
rpm-ostree status
sudo ostree admin pin 0
rpm-ostree status
```

A pinned deployment survives any number of upgrades as a boot-menu fallback, this is the documented prerequisite in Margine's lab runbook before kernel swaps. Unpin with `ostree admin pin --unpin <index>`.

**/etc merge rules.** On every deployment, ostree performs a 3-way merge of `/etc`: the *factory* defaults shipped in the image (`/usr/etc`), the *previous* defaults, and your *current* `/etc`. Files you never touched track the image; files you modified keep your version, even when the image's default changes underneath. Audit the drift with:

```sh
sudo ostree admin config-diff   # M = locally modified vs factory, A = locally added
```

That "local wins forever" rule is the main day-2 footgun: a stale local edit can mask an upstream fix indefinitely. Margine's mitigation is structural, ship configuration in `/usr` (gschema overrides, dconf db, systemd units in `/usr/lib`) and keep `/etc` for machine-local state, so the merge has nothing contentious to do.

> **Lesson, your packaging pipeline can eat /etc.**
> *Symptom:* fresh-VM rebase boots with a 1-entry `/etc/passwd`; Layer A in CI had verified 65 entries at the end of buildah (Bug 6 v2, 2026-05-31).
> *Root cause:* rechunk re-commits the image as an ostree-canonical tree and strips `/etc/passwd` + `/etc/group` from `/usr/etc`, so the factory side of the 3-way merge is empty on first deploy. The image you tested in CI is not byte-for-byte the tree the client checks out.
> *Fix:* a boot-time idempotent seed that merges `/usr/lib/passwd` (the systemd factory copy, which rechunk does preserve) into `/etc`, gated on the stripped state:
> ```bash
> # margine-image/build_files/system_files/usr/libexec/margine-seed-etc-passwd
> # Runs only if /etc/passwd has fewer than 20 entries (the post-rebase stripped state).
> factory = by_name(load(f"/usr/lib/{kind}"))
> merged = dict(factory); merged.update(local)   # local entries win
> os.replace(tmp, f"/etc/{kind}")
> ```

> **Lesson, early-boot units and ordering cycles.**
> *Symptom:* boot hangs and times out into `emergency.target` (incident 2026-06-01).
> *Root cause:* the seed unit declared `After=local-fs.target`, creating a cycle through `systemd-tmpfiles-setup-dev.service`; systemd broke the cycle by dropping tmpfiles-setup-dev, so `/dev/disk/by-uuid/*` never populated and mounts timed out.
> *Fix:* order against the *minimum* you need, `/usr` is part of the immutable commit and available from the start:
> ```ini
> # /usr/lib/systemd/system/margine-seed-etc-passwd.service
> DefaultDependencies=no
> After=local-fs-pre.target
> Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
> ConditionFileNotEmpty=/usr/lib/passwd
> ```

## 11.6 The rebase path from Bluefin DX

Margine's recommended install today is not the ISO, it is a rebase from a vanilla Bluefin DX install:

```sh
# margine-image/README.md — Option A
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

The `ostree-image-signed:` transport (vs plain `ostree-image:` / `ostree-unverified-registry:`) makes rpm-ostree verify the container signature against the policy in `/etc/containers/policy.json` before checkout, this is where the cosign key published at `margine-image/cosign.pub` plugs into the client trust chain (the 2026-06-05 audit lists all three verification paths: signed-transport rebase, direct `cosign verify --key cosign.pub`, and `sha256sum -c` on the ISO). After the first Margine boot: one MOK-enrollment reboot (`mok-enroll.service` submits the import; MokManager confirms it, chapter on Secure Boot), then `ujust margine-bootstrap` for user-state.

The rebase is also where `validate-staged-deployment` earns its keep: run *after* the rebase, *before* the reboot, it inspects the staged tree from the still-working current OS, OS identity actually says Margine, initramfs exists at the bootc-canonical path and is >50 MB (not host-only), and:

```bash
# build_files/40-spec-scripts/scripts/validate-staged-deployment
# THE check that motivated Bug 5: ostree-prepare-root must be inside
# the initramfs, otherwise switch-root cannot pivot /sysroot ...
if grep -q 'usr/lib/ostree/ostree-prepare-root' "$LS_OUT"; then
  ok "initramfs contains ostree-prepare-root (--add ostree fix applied)"
else
  bad "initramfs MISSING ostree-prepare-root — this WILL panic at switch-root"
fi
```

Every check in that script encodes a defect that previously landed a VM in a dracut emergency shell, where copy-pasting diagnostics doesn't work. Catching them pre-reboot, in a terminal that has a clipboard, is the entire design. On failure: `rpm-ostree rollback` abandons the staged deployment without ever booting it.

## 11.7 Alternatives & other distros

**Image tags / channels**
- Universal Blue (Bluefin/Bazzite/Aurora): `:stable` + `:latest` + `:stable-daily` + versioned `:gts`/`:41` tags, multi-arch manifests, richer grammar, more surface to test. Margine: candidate→stable promotion only.
- Fedora bootc / CoreOS: stream refs (`stable`, `testing`, `next`) with automated promotion windows, same idea as candidate/stable, calendar-driven instead of boot-test-driven.
- SteamOS: OTA channels (`stable`/`beta`/`preview`) over an A/B partition scheme, not OCI, channel switch in the UI; rollback = boot the other slot. ChimeraOS does the same with `frzr` deploying read-only btrfs subvolume images.
- Hard digest pinning in fleets: bootc + a GitOps repo that bumps `@sha256:` refs (the bootc-fleet pattern; also what Kubernetes folks do with policy-controller), maximal reproducibility, you own the cadence.

**Install media distribution**
- Universal Blue: ISOs on a CDN bucket (R2/S3) with SHA256 checksums on the download page, simpler, costs money at scale.
- Fedora: mirror network + torrents via fedoraproject mirrormanager, heavyweight, needs an org. Margine's IA approach is the zero-infra approximation (IA seeds the torrent, keeps every release forever).
- Vanilla OS, NixOS: ISO on GitHub Releases, free, capped at 2 GiB per file, which a Flatpak-baked ISO blows through.

**Update orchestration**
- uupd (Bluefin/Bazzite/Aurora, inherited by Margine): Go rewrite superseding `ublue-update`, which was a Topgrade wrapper, the history Margine recapitulated in miniature (custom `update-all` + topgrade.toml → deleted in favor of uupd).
- Plain `rpm-ostree upgrade` + `rpm-ostreed-automatic.timer` (stock Silverblue/Kinoite): base OS only; Flatpaks update via GNOME Software, two cadences, no distrobox/brew coverage.
- `bootc-fetch-apply-updates.timer` (Fedora bootc minimal): fetch, apply, *auto-reboot*, right for servers/appliances, wrong for desktops.
- openSUSE MicroOS/Aeon: `transactional-update.timer` + health-checker, btrfs snapshot per update, rollback via snapper, equivalent guarantees, filesystem-level instead of image-level.
- Vanilla OS ABRoot: A/B root partitions, update applied to the inactive slot, simple mental model, 2× root disk cost.
- NixOS: `nixos-rebuild switch --upgrade` + generations in the bootloader, config-driven rather than image-driven; rollback selects a generation.
- Fleet management: Fleek (Nix-based home/host config sync) or plain Ansible/FluxCD bumping bootc refs; at enterprise scale, RH's image mode + Insights. Margine's fleet is one person, so the "fleet tooling" is ntfy pushes + the staleness watchdog.

**Rollback / pinning**
- bootc/ostree (Margine): previous deployment + `ostree admin pin`, O(1) disk via hardlinks.
- MicroOS: snapper rollback across N snapshots, finer-grained history, btrfs-only.
- SteamOS/ChimeraOS: A/B slots, exactly one fallback, zero knobs.
- NixOS: arbitrary generations until GC'd, best history, biggest disk bill.


---

# 12. Trust but verify: validators, diagnostics, and the lesson catalog

An atomic distro's promise, "the image you tested is the image you run", is only as good as the testing. Margine validates at three altitudes: **build time** (CI file checks inside the candidate image, chapter 9), **boot time** (QEMU smoke gate before `:stable` promotion, chapter 9), and **runtime** (the `margine-validate-*` suite on the deployed system). This chapter covers the runtime layer, the diagnostics bundle, the manual QEMU/ISO workflow, and the catalog of real bugs the project hit, each reduced to symptom → root cause → fix → generalized rule.

## 12.1 The margine-validate-* suite

### Design principles

The validators live in `build_files/40-spec-scripts/scripts/` and are baked into the image as `/usr/bin/margine-validate-*`. Three deliberate constraints:

- **Read-only.** A validator never mutates state. Repair is the job of `configure-*` scripts and `ujust` recipes.
- **On-demand, not hooks.** They are not pre/post-update hooks (`updates.validators_on_demand` in `margine-atomic.yaml`). An update gate that can wedge updates is worse than drift.
- **`warn` vs `fail` discipline.** Only hard contract violations `fail` (exit 1); environment-dependent findings `warn` and keep exit 0. `set -u; set -o pipefail` but no `set -e`, a probe returning non-zero is data, not a crash.

```bash
warn() {
  warnings=$((warnings + 1))
  printf 'WARN: %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1"
}
```
*`build_files/40-spec-scripts/scripts/validate-atomic-layout:16-24`, shared counter pattern across the whole suite; the summary section exits 1 only if `failures > 0`.*

### How they get into the image

The build installs them from the vendored `build_files/40-spec-scripts/scripts/` under a `margine-` prefix:

```bash
for s in \
    ... \
    validate-atomic-layout \
    validate-cachyos-kernel \
    validate-hardware-media-stack \
    validate-gaming-runtime \
    validate-margine-system \
    validate-declared-state \
    collect-diagnostics ; do
  install -Dm0755 "/ctx/40-spec-scripts/scripts/${s}" "/usr/bin/margine-${s}"
done
```
*`margine-image/build_files/40-spec-scripts/install.sh:37-57`, preceded by a preflight `curl --head` against the repo: a 404 fails the build loudly instead of shipping an image with silently-missing tooling.*

### validate-atomic-layout

Checks the ostree/bootc contract: `rpm-ostree status` works, `/` is mounted `ro`, `/home → /var/home`, btrfs backs the layout, Secure Boot state, LUKS2/TPM2 enrollment in `/etc/crypttab`. One subtlety worth stealing, on composefs systems `/usr` has no separate mountpoint, and a naive "is /usr ro?" check false-positives:

```bash
# On Silverblue with composefs (Fedora 39+), /usr is embedded in the root
# overlay and has no separate mountpoint. This is expected and correct.
if findmnt /usr >/dev/null 2>&1; then
  ...
else
  root_fstype_inner=$(mount_field FSTYPE /)
  if [[ "$root_fstype_inner" == "overlay" ]]; then
    ok "/usr is embedded in the composefs root overlay (expected on Silverblue)"
```
*`build_files/40-spec-scripts/scripts/validate-atomic-layout:111-122`*

### validate-cachyos-kernel

Confirms the kernel replacement (chapter 3) actually took: `uname -a` matches `cachy`, CachyOS RPMs present, COPR repo file installed, and, the check that catches half-applied deployments, stock Fedora kernel packages still visible are a `warn`:

```bash
if printf '%s\n' "$kernel" | grep -Eiq 'cachy|cachyos'; then
  ok "running kernel appears to be CachyOS"
else
  fail "running kernel does not appear to be CachyOS"
fi
```
*`build_files/40-spec-scripts/scripts/validate-cachyos-kernel:34-38`*

The signature/MOK side lives in `validate-margine-system` §4, which goes beyond `--sb-state` to verify the actual trust anchor:

```bash
if [[ "$SB_STATE" =~ enabled ]]; then
  ok "Secure Boot is enabled"
  if "${SUDO[@]}" mokutil --list-enrolled 2>/dev/null | grep -qiE 'margine|daniel'; then
    ok "Margine MOK is enrolled"
  else
    bad "Margine MOK NOT enrolled — CachyOS kernel will not load on next boot if SB stays on"
  fi
else
  warn "Secure Boot is disabled — running unsigned kernel without verification"
fi
```
*`build_files/40-spec-scripts/scripts/validate-margine-system:214-222`, "SB on but MOK missing" is the one state that bricks the next boot, hence the only `bad`.*

### validate-hardware-media-stack

The codec/GPU chapter (10-hardware-media-stack.md) made claims; this validator proves them per-machine: PipeWire/WirePlumber user services active, `glxinfo -B`, `vulkaninfo --summary`, `vainfo`, `ffmpeg -hwaccels`, `gst-inspect-1.0 va`, `clinfo`/`rocminfo`, and an application-level probe (`darktable-cltest` must report "OpenCL AVAILABLE and ENABLED", testing the consumer, not just the ICD). Everything is `warn`-only: hardware varies, so the script is a structured report, not a gate. The `run_if_present` helper prints the exact command before running it, so the output doubles as a reproduction script.

### validate-gaming-runtime

Checks the opt-in gaming layer: Flatpak launchers (`flatpak info` per app-id), host helpers (`gamescope`, `mangohud`, `vkbasalt`, `gamemoded`), Vulkan layer files in all three search paths, Steam's sandbox permissions (`flatpak info --show-permissions`), controller udev packages, and a policy check that persistent `kernel.split_lock_mitigate=0` hasn't been smuggled into `/etc/sysctl.d` (`validate-gaming-runtime:161-168`).

### validate-declared-state — making the YAML load-bearing

The drift detector compares `declarations/margine-atomic.yaml` against the running system: every declared host package `rpm -q --whatprovides`-resolvable, every declared Flatpak in `flatpak list --system`, every declared extension UUID present in the system or user extension dir. Spec lookup order makes the same script work in dev tree, CI, and on-host:

```python
def find_spec() -> Path:
    env = os.environ.get("MARGINE_SPEC")
    ...
    candidates = [
        Path("/usr/declarations/margine-atomic.yaml"),
        Path("/usr/share/margine/declarations.yaml"),
        Path(__file__).resolve().parent.parent / "declarations" / "margine-atomic.yaml",
    ]
```
*`build_files/40-spec-scripts/scripts/validate-declared-state:105-127`, the `/usr/declarations` symlink is created by `40-spec-scripts/install.sh:72-73` because six of seven configure-* scripts resolve the YAML relative to `__file__`, which from `/usr/bin/` lands there.*

Flatpak absences are `warn`, not `fail`, Margine's DEFER queue (chapter 6) means a declared app may legitimately not be installed yet. Direction matters in a drift detector: "spec says X, system lacks X" and "system has X, spec never mentioned it" are different bugs; this tool currently surfaces the first.

### validate-margine-system

The comprehensive runtime acceptance test: identity (`VARIANT_ID=margine`), kernel, MOK, branding assets, GNOME settings *as actually applied* ("photograph the current state", GDM/Shell can shadow dconf defaults in ways file checks never see), Flatpaks, failed units. Expected values are hardcoded at the top with a comment ordering them "keep in sync with declarations/margine-atomic.yaml and build.sh", see Lesson 10 for why that sync discipline is load-bearing.

## 12.2 margine-collect-diagnostics

When a validator fails on someone else's machine, you want one command that produces an attachable artifact. The collector runs ~60 captures into a timestamped directory and tars it:

```bash
capture() {
  local name=$1
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n\n'
    "$@"
  } >"${out_dir}/${name}" 2>&1 || true
}

capture rpm-ostree-status-json.txt rpm-ostree status --json
capture journal-warnings.txt journalctl -b -p warning..alert --no-pager
```
*`build_files/40-spec-scripts/scripts/collect-diagnostics:14-23,39,52` — every file begins with the exact command that produced it; `|| true` because a failing probe is itself a finding.*

Coverage mirrors the validators (mounts, crypttab, MOK, media stack, gaming, GNOME interface keys, fonts, repo files, btrfs subvolumes) so a bundle can answer any validator's question offline. `umask 077` and an explicit trailer warn that the archive contains hostnames, usernames, and journal excerpts, say this *in the tool*, not in docs nobody reads.

## 12.3 QEMU validation workflow for ISOs

CI's smoke gate (chapter 9) answers "does the qcow2 boot to GDM". Installer ISOs need a human: Anaconda flow, partitioning, MOK staging, first-boot UX. The lab workflow (`docs/02b-lab-vm-setup.md`) uses libvirt with real Secure Boot and a software TPM:

```sh
virt-install \
    --connect qemu:///system \
    --name margine-smoketest \
    --memory 8192 \
    --vcpus 4 \
    --disk size=64,format=qcow2 \
    --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,loader.secure=yes \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
    --cdrom ~/data/inbox/10-downloads/bluefin-stable-x86_64.iso \
    --graphics spice \
    --network network=default \
    --noautoconsole
```
*`docs/spec/02b-lab-vm-setup.md:117-129`, OVMF secboot firmware + swtpm CRB device gives the full enrollment path: install → reboot → MokManager → enroll with the documented passphrase → CachyOS kernel boots under SB. `virt-viewer --connect qemu:///system margine-smoketest` opens the console.*

Two session gotchas the doc captures: `virsh` defaults to `qemu:///session` (per-user) while the NAT `default` network lives in `qemu:///system`, so either export `LIBVIRT_DEFAULT_URI=qemu:///system` or pass `--connect` everywhere; and the snapshot ladder (`margine-stable-<date>` after each verified milestone) makes rollback the recovery default instead of reinstalling. Test ISOs reach the lab via Internet Archive `test_collection` items (auto-expire ~30 days, `publish-titanoboa-test-iso.yml`) because GHA artifact egress to residential lines runs at ~1-1.5 MB/s, an 8 GB ISO would take hours.

For the automated half, the smoke gate's hard-won detail is *what to grep for*. "Reached target multi-user.target" is not reliably emitted on serial consoles on recent systemd:

```bash
# Multi-marker approach (2026-06-01): systemd recent does NOT
# always emit "Reached target multi-user.target" verbatim on
# the serial console (seen on Fedora 44 with CachyOS kernel ...)
for i in $(seq 1 1200); do
  if grep -qE "Started.*gdm\.service|Reached target graphical\.target|margine login:" serial.log; then
    echo "✓ Boot reached usable state at second $i"
```
*`margine-image/.github/workflows/smoke-boot.yml:176-188`, accept any of three equivalent "userspace is up" signals; a single-marker gate produced false boot failures.*

## 12.4 Lesson catalog

Every entry below is a real Margine incident with the fix in-tree. The generalized rules are the transferable part.

### Lesson 1 — mksquashfs: everything after `-e` is an exclude

> **Symptom:** Live ISOs larger and slower to boot than projected; the build log says `Creating 4.0 filesystem ... gzip compressed` despite `-comp zstd -Xcompression-level 19` being passed.
> **Root cause:** `mksquashfs` treats *every* argument after the first `-e` as an exclude name. The invocation put the exclude list before the compressor flags, so `-comp`, `zstd`, `-Xcompression-level`, `19` were silently consumed as bogus excludes and the default gzip applied.
> **Fix** (upstreamed; recorded in the commit message):
> ```
> fix: pass mksquashfs exclude list last so -comp zstd is honored
>
> Moving the compressor options before -e (and passing both excludes to
> a single -e, which has to be the last option per the man page) fixes
> it. Tested with squashfs-tools 4.6.1: zstd is applied and sysroot and
> ostree are still excluded.
> ```
> *`margine-image` commit `32afa48` (2026-06-10): "every consumer is currently shipping gzip instead of the intended zstd-19."*
> **Rule:** Greedy/positional CLI options invalidate "the flags are present, therefore they applied" reasoning. Assert *outcomes* in build logs (the compressor line, the final size), not invocations.

### Lesson 2 — `[ -f ]` on a directory: the hybrid ISO that wasn't

> **Symptom:** ISOs advertised as hybrid BIOS+UEFI never boot on BIOS; nothing in the build fails.
> **Root cause:** Titanoboa's `build_iso.sh:32` guards the BIOS GRUB module copy with `[ -f ]` against `/usr/lib/grub/i386-pc`, a *directory*, so the test is always false and the copy never runs; its `xorriso` call also lacks an El Torito `-b` image. Found by a build-log scan, not by a failure.
> **Fix:** Margine ships the truth instead of the claim:
> ```bash
> if [[ -d /usr/lib/grub/i386-pc ]]; then
>   echo "NOTE: /usr/lib/grub/i386-pc present, but current Titanoboa produces a UEFI-only ISO (no BIOS El Torito; upstream build_iso.sh:32 -f-vs-directory bug)"
> ```
> *`margine-image/live-env/src/build.sh:61-62`, BIOS stays non-gating per ADR-0008 §4 (all reference hardware is UEFI).*
> **Rule:** A wrong file-test operator fails *silently* in guard position. Read your vendored dependencies' build logs once, end to end; every claim a pipeline makes ("hybrid", "compressed", "signed") needs one observable check.

### Lesson 3 — ccache poisoning container builds

> **Symptom:** Compiling wayland-scroll-factor inside the image build dies on every TU with `ccache: error: File exists`.
> **Root cause:** The Bluefin base puts `/usr/lib64/ccache` first in `PATH`, so `cc` is a ccache shim; in the build container ccache's cache dir isn't writable and every compile aborts.
> **Fix:**
> ```bash
> # Margine's PATH puts /usr/lib64/ccache first; in the build container
> # ccache's cache dir isn't writable and every compile dies with
> # "ccache: error: File exists" ... Compile without it, a one-shot
> # build gains nothing from a compiler cache anyway.
> export CCACHE_DISABLE=1
> ```
> *`margine-image/build_files/45-wsf/install.sh:36-41`*
> **Rule:** Deriving from an opinionated base image means inheriting its developer-experience knobs in a context they were never tested in. Neutralize host-oriented toolchain shims (`ccache`, `sccache`, interactive `PATH` injection) in build sections; a one-shot layer build gains nothing from them.

### Lesson 4 — SELinux xattrs vs rsync in kickstart `%post`

> **Symptom:** BAKE Flatpaks present on disk after install but fail to launch, AVC denials in the journal.
> **Root cause:** ostree/bootc reset `/var` per deployment, so baked Flatpaks must be rsync'd from the installer rootfs into the target (`%post --nochroot`). A naive `rsync -a` drops POSIX xattrs; copying SELinux labels verbatim from the installer context is also wrong, because the target's labels belong to `ostree-finalize`.
> **Fix:** the original BIB kickstart preserved xattrs/ACLs/hardlinks:
> ```bash
> rsync -aAXUHK --open-noatime /var/lib/flatpak "$DEPLOY_DIR/var/lib/"
> ```
> (That BIB kickstart, `iso-gnome.toml`, has since been deleted.) The Titanoboa migration then pinned the production-verified refinement as the standing invariant in `live-env/src/anaconda/post-scripts/install-flatpaks.ks`: `rsync -aAXUHKP --filter='-x security.selinux'`, "preserves POSIX xattrs but strips SELinux labels which ostree-finalize restores. Flatpak directories have `system_data_t`/`flatpak_t` labels; if dropped or wrong, Flatpaks fail to launch with AVC denials" (*ADR-0008 §4*). Belt-and-suspenders: every BAKE app is also in `/usr/share/flatpak/preinstall.d/margine-defaults.preinstall`, so a silently failed rsync still self-heals at first boot.
> **Rule:** On SELinux systems "copied the bytes" ≠ "copied the file". Decide explicitly, per metadata class, whether to preserve or strip, and let the component that owns labeling (ostree-finalize, `restorecon`) do its job. Always pair an install-time copy with a first-boot fallback.

### Lesson 5 — Clutter 18 unrealize assert: hide before detach

> **Symptom:** Launching an app from the search-light overlay SIGABRTs the entire gnome-shell, on Wayland the session dies, and GNOME's crash protection then sets `disable-user-extensions=true`, knocking out *all* extensions.
> **Root cause:** `extension.js` `_release_ui()` calls `remove_child()` on the entry while the overlay is still mapped; Clutter 18's stricter unrealize path asserts `!clutter_actor_is_mapped(self)` and aborts. Verified by coredump + journal on the reference host; upstream had open reports and no fix.
> **Fix:** build-time patch of the baked extension, unmap before detaching:
> ```python
> new = """  _release_ui() {
>     if (this._entry) {
>       if (this._entry.get_parent()) {
>         this._entry.hide(); // margine: unmap before detach (Clutter 18 unrealize assert)
>         this._entry.get_parent().remove_child(this._entry);"""
> ```
> *`margine-image/build_files/build-margine-extensions.sh:203-220`, applied via exact-match string replace, idempotent (greps for its own marker first), and soft-fail: if upstream's code changes the patch logs a WARN instead of failing the build, because a mitigation must not become load-bearing.*
> **Rule:** Shell extensions are in-process patches to a moving target; when you bake them, you own their crashes. Detach-while-mapped is the canonical GNOME-major-bump breakage: hide/unmap actors before `remove_child()`. Build-time source patches beat forks for one-liners, but make them idempotent and soft-failing.

### Lesson 6 — dconf list replacement shadows distro keybindings

> **Symptom:** `Super+period` (Smile emoji picker) works on a fresh install, then goes dead forever after the first `ujust margine-bootstrap`.
> **Root cause:** The image ships the binding at the *distro* dconf layer (`/etc/dconf/db/distro.d/07-margine-custom-keybindings`). `configure-gnome-keybindings` then writes the `custom-keybindings` **path list** at the *user* layer, and dconf lists replace, they don't merge. The user-layer list, which didn't contain the smile slot, shadowed the distro entry wholesale:
> ```python
> def apply_custom(custom_list: list[dict], dry: bool) -> None:
>     paths = [f"{CUSTOM_BASE_PATH}{c['name']}/" for c in custom_list]
>     run(["gsettings", "set", CUSTOM_LIST_SCHEMA, "custom-keybindings",
>          gvariant_strings(paths)], dry)
> ```
> *`build_files/40-spec-scripts/scripts/configure-gnome-keybindings:275-287`, REPLACES the whole list.*
> **Fix:** declare the slot in the spec so bootstrap recreates it (commit `4ce4722`):
> ```yaml
> - name: smile
>   # NB: bootstrap REPLACES the whole custom-keybindings path list,
>   # which used to shadow the distro-level margine-smile entry ...
>   binding: '<Super>period'
>   command: 'flatpak run it.mijorus.smile'
> ```
> *`build_files/40-spec-scripts/declarations/margine-atomic.yaml` (keybindings.custom)*
> **Rule:** dconf layering is per-key, and a list is one key. Any tool that writes a list key at the user layer silently shadows every distro-layer element not in its input. Either own the full list in one place (Margine's choice: the spec) or read-merge-write, never blind-set.

### Lesson 7 — dynamic workspaces make move-to-workspace-N a silent no-op

> **Symptom:** `SUPER+SHIFT+N` (move window to workspace N) "feels broken", sometimes works, usually does nothing, no error anywhere.
> **Root cause:** With GNOME *dynamic* workspaces, the native `move-to-workspace-N` and `switch-to-workspace-N` bindings only act on workspaces that already exist; they do not create workspace N the way Hyprland does. Margine binds Super+1..0 for Hyprland muscle memory, so most targets didn't exist yet.
> **Fix:** static workspace model, pre-created (commit `4ce4722`, count later tuned 10→5 in `32afa48`):
> ```yaml
> workspaces:
>   dynamic: false
>   # 5, not 10: static workspaces are all pre-created and always visible
>   # in the overview/pager, and a permanent wall of 10 felt like clutter.
>   # SUPER+[SHIFT+]6..0 bindings stay declared, harmless no-ops until
>   # the count is raised again.
>   count: 5
>   names: ['1', '2', '3', '4', '5']
> ```
> *`build_files/40-spec-scripts/declarations/margine-atomic.yaml:795-803`*, and `validate-margine-system:470-481` asserts both `num-workspaces` and `dynamic-workspaces=false` ("SUPER+1..0 binds will misbehave").
> **Rule:** Porting keybindings between WMs ports the keys, not the semantics. GNOME's numbered-workspace bindings presuppose static workspaces; flip `org.gnome.mutter dynamic-workspaces` off whenever you ship direct-jump binds, and validate the *pair* of settings, since either alone breaks the UX.

### Lesson 8 — Flatpak portal single-file export breaks relative links

> **Symptom:** Offline docs open in the (Flatpak) default browser; the page renders, but every link to a sibling page is dead.
> **Root cause:** When a Flatpak app receives a `file://` URI outside its permissions, the document portal exports *only that single file* into the sandbox (`/run/user/.../doc/...`). The HTML arrives; its relative CSS/links point at siblings that were never exported. Worse, Flatpak *reserves* `/usr`, no override can ever expose the immutable seed copy.
> **Fix:** serve from a `/var` mirror the sandbox is granted read access to:
> ```bash
> # Why ALWAYS the /var copy and never the /usr seed directly: the
> # default browser is a Flatpak (Zen). For a file:// URI outside its
> # permissions the portal exports ONLY that single file, the page
> # renders but every relative link to sibling pages is dead. ...
> # Flatpak reserves /usr so no override can ever expose the seed.
> if [[ -f "${VAR_DIR}/docs/index.html" ]]; then
>   exec xdg-open "file://${VAR_DIR}/docs/index.html"
> ```
> *`margine-image/build_files/system_files/usr/libexec/margine/docs-open:9-27`*, paired with `docs-refresh:66`: `flatpak override --system --filesystem="${DOCS_DIR}:ro"` (global, not per-app, so a browser switch keeps working). Corollary in the same component: refreshing the mirror by directory-swap broke already-running sandboxes (they bind-mount the dir at app start and end up staring at the emptied old inode), `docs-refresh`'s `sync_in()` rsyncs files in place instead (`docs-refresh:38-51`, commit `b9208eb`).
> **Rule:** `xdg-open file://...` toward sandboxed apps exports one file, not a tree. Multi-file local content must live on a path the sandbox holds a `--filesystem` grant for, which excludes `/usr` by design, and must be updated file-wise, never by replacing the granted directory.

### Lesson 9 — journald is the first victim of a host I/O stall

> **Symptom:** Post-incident analysis of a build-host freeze finds the previous boot's journal *ends 23 hours before the stall*, zero hung-task, nvme, or zfs errors persisted. The postmortem cannot prove its own trigger hypothesis. Meanwhile HTTP uptime checks stayed green because the reverse proxy kept serving from page cache.
> **Root cause:** journald persists through the same I/O path that is stalling. It blocks (`D` state) or dies before the interesting kernel messages are written; everything after that exists only in a ring buffer that the power-cycle erases. Evidence collection and failure share a single point of failure.
> **Fix/follow-ups** from the incident note: ship kernel messages off-box (`netconsole` or remote syslog, "so the nvme/zfs messages survive the next stall; without it, every postmortem stays incomplete") and replace HTTP uptime checks with a write+fsync heartbeat probe (cron touches the pool and pings ntfy; silence = alarm).
> *`proxmox-pve1/docs/notes/2026-06-11-pve1-io-stall-power-cycle.md`, fourth storage incident in a month on the DRAM-less single-NVMe ZFS host; the same class of failure that earlier killed Margine's self-hosted runner (chapter 9).*
> **Rule:** Telemetry that shares a failure domain with the thing it observes will be lost exactly when you need it. For storage incidents: off-box kernel logging, and probes that exercise the *write* path (fsync), not the cached read path.

### Lesson 10 — validator sentinels must track shipped defaults

> **Symptom:** CI run 27297409457 fails the first-boot asset validator right after a *correct* fix landed: the search-light `border-radius` default was repaired from 30 to 7 (the key is an index 0-7 into a px table `[0,16,18,20,22,24,28,32]`, not pixels, 30 hit `rads[30] = undefined` and the rounding was silently skipped), but the validator still asserted the old value.
> **Root cause:** The sentinel encodes a copy of the shipped default. Two copies of one fact, changed in one place.
> **Fix:** update the sentinel in lock-step (commit `b4e8680`), and make it carry its own rationale:
> ```yaml
> # search-light rounded-corners daniel default: border-radius=7.0
> # (the value is an INDEX 0-7 into the extension's px table, not
> # pixels, 7 = 32px max rounding; the old 30 was out of range and
> # silently ignored. See #94.)
> grep -qE "^border-radius=7" "$DCONF_DIR/02-margine-search-light" || { echo "::error::A.3.bis search-light border-radius!=7 — daniel default lost"; fail=1; }
> ```
> *`margine-image/.github/workflows/build.yml` (A.3.bis section)*
> **Rule:** A sentinel's failure mode is blocking *good* builds, not missing bad ones, budget for that. Default and sentinel must change in the same commit (grep CI for the old value before merging any default change), and each sentinel should cite why the value is what it is, so the next person edits it instead of deleting it. The underlying extension bug carries its own rule: schema types lie; read the consumer of a key before assuming units.

## 12.5 Alternatives & other distros

**Runtime validation / drift detection**
- **Margine**: bespoke read-only `validate-*` bash/python suite + YAML drift detector, cheap, transparent, zero dependencies beyond PyYAML.
- **Bluefin/Bazzite (ublue)**: minimal on-host validation; rely on `bootc container lint` at build, huge `:testing` user base as the de-facto detector, and `ujust` doctor-style recipes. Less machinery, more community.
- **NixOS**: the configuration *is* the system closure, drift between declaration and system is impossible by construction (only mutable state can drift); the validator equivalent is `nixos-rebuild dry-activate` + the module test framework.
- **openSUSE MicroOS/Aeon**: `transactional-update` + health-checker run real boot-health checks and *auto-rollback* the snapshot on failure, stronger than Margine's report-only model, at the cost of surprise rollbacks.
- **Vanilla OS (ABRoot)**: A/B partition integrity checks before switching; drift detection scoped to the image diff.
- **Fedora Silverblue stock**: `rpm-ostree status` + nothing, the deployment digest is the validation.

**Diagnostics bundles**
- **Margine `collect-diagnostics`**: flat tarball of command outputs, command-as-header convention.
- **sos report** (Fedora/RHEL): the industrial version, plugins, obfuscation profiles; heavyweight but standard for filing distro bugs.
- **Bazzite**: `ujust device-info` / system info exporters tuned for Discord-based support.

**Boot/ISO validation**
- **Margine**: CI QEMU serial-grep gate (qcow2) + manual `virt-install` lab with OVMF-SB+swtpm for ISOs and the MOK flow.
- **Fedora**: openQA, screen-matching, full install matrices; the gold standard, and an entire service to operate.
- **NixOS**: declarative QEMU VM tests gating channel advancement, most rigorous, Nix-only.
- **ublue**: Titanoboa ISO pipelines smoke-tested mostly by maintainers + community; ADR-0008's research found Bluefin's ISO CI red for 3+ weeks from a silent action-input change, the cautionary tale for gateless pipelines.

**Lessons-learned practice**
- **Margine**: dated `docs/lessons-learned/*.md` + ADRs + fix-carrying commit messages (the catalog above is assembled from them); validators grow a sentinel per regression.
- Most small distros keep this in Discord/issue threads, unsearchable and unciteable. If a bug cost you a day, the write-up costs ten minutes and is the only artifact that compounds.

The meta-rule of the whole chapter: every lesson above was converted into either a validator check, a CI sentinel, or a comment at the exact line where the trap is, the knowledge lives where the next mistake would happen, not in a wiki.


---

# Appendix — Lesson index

One line per production lesson; see the chapter's Lesson box for the full story.

- Ch. 1: legacy units assume a remountable root (Bug 8)
- Ch. 1: /etc/passwd vanished after rebase (Bug 6)
- Ch. 1: early-boot unit ordering deadlocked the boot (incident 2026-06-01)
- Ch. 1: os-release symlink vs composefs timing (Fix A wind-down)
- Ch. 2: os-release symlink vs switch-root
- Ch. 2: rechunk strips the `/etc` factory
- Ch. 3: persistent build caches poison dnf
- Ch. 3: `--kver` + `--regenerate-all` are mutually exclusive, and `|| true` ate the proof
- Ch. 3: host-only initramfs of the wrong "host"
- Ch. 3: dracut writes to `/boot/`; ostree reads `/usr/lib/modules/<kver>/`
- Ch. 3: the `ostree` dracut module is never auto-included
- Ch. 4: ISO MOK enrollment timing (PR #88, 2026-06-08)
- Ch. 4: passphrase rotation (2026-06-06)
- Ch. 5: the index-vs-pixels bug (search-light `border-radius`)
- Ch. 5: transient `dnf` installs in build scripts cascade
- Ch. 5: search-light unrealize-while-mapped shell crash
- Ch. 5: a `script` theme has NO built-in LUKS prompt (`SetDisplayPasswordFunction` is REQUIRED)
- Ch. 5: the initramfs runs in the C locale; multi-byte UTF-8 breaks text rendering
- Ch. 6: inline comments become Flatpak IDs
- Ch. 6: install-time downloads of a 5 GB set are fragile
- Ch. 6: copy POSIX xattrs, strip SELinux labels
- Ch. 6: GNOME 50+ skips autostart entries with `X-GNOME-Autostart-Phase`
- Ch. 6: never swap a directory a Flatpak sandbox has bind-mounted
- Ch. 10: install-time `flatpak install` silently OOMs
- Ch. 10: the BIOS `[ -f ]` guard: the "hybrid" ISO that isn't
- Ch. 10: mksquashfs silently falls back to gzip
- Ch. 10: explicit `part` crashes Anaconda WebUI 68
- Ch. 11: SHA256SUMS paths must match the published layout
- Ch. 11: size your timeouts to the slow third party, not your build
- Ch. 11: your packaging pipeline can eat /etc
- Ch. 11: early-boot units and ordering cycles
