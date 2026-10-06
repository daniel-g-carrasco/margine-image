#!/usr/bin/env python3
"""Security scan of a built Margine image, compared with a reviewed baseline.

    sudo scan-image-security.py --rootfs DIR --owned FILE --baseline DIR
                                [--write-baseline DIR] [--report FILE]

DIR is the image's root filesystem (a `podman mount`), FILE the list of
paths owned by RPM packages (`rpm -qa --qf '[%{FILENAMES}\\n]'` run in the
image). Exit status: 0 clean, 1 baseline drift, 2 secrets found (secrets
never have a baseline: they must not ship, whatever the event).

Why (2026-10-07): the holes found in the first week of October were all
"present but nobody looked": a root adb private key baked into every
image, build residue in /run, a reversed SELinux home mapping inherited
from the base. Each category below turns one of those into a diff that a
person has to approve.

Categories
  secrets      private keys / tokens in files no package owns, or anywhere
               under etc, var, root, usr/local; ssh host keys; a set
               machine-id. Fatal.
  privileged   setuid / setgid files and files with capabilities.
  writable     world-writable files and non-sticky dirs under usr and etc.
  residue      anything left in run, tmp, var/tmp, var/home, var/roothome,
               root (build leftovers; installed systems never see them,
               but they leak build state and move layers).
  units        enabled systemd units (wants/requires links) and presets.
  configs      the content of security-relevant configuration files.
"""
import argparse
import difflib
import fnmatch
import os
import re
import shutil
import stat
import sys

SECRET_RE = re.compile(
    rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----"
    rb"|\bgh[pousr]_[A-Za-z0-9]{36,}\b"
    rb"|\bgithub_pat_[A-Za-z0-9_]{60,}\b"
    rb"|\bAKIA[0-9A-Z]{16}\b"
    rb"|\bxox[abposr]-[A-Za-z0-9-]{10,}\b"
)
SECRET_SCAN_ALWAYS = ("etc/", "var/", "root/", "usr/local/")
SECRET_MAX_BYTES = 1 << 20

RESIDUE_DIRS = ("run", "tmp", "var/tmp", "var/home", "var/roothome", "root")
UNIT_DIRS = (
    "usr/lib/systemd/system", "usr/lib/systemd/user",
    "etc/systemd/system", "etc/systemd/user",
)
CONFIG_GLOBS = (
    "etc/containers/policy.json", "etc/containers/registries.d/*",
    "usr/lib/pki/containers/*", "etc/pki/containers/*",
    "etc/selinux/config", "etc/selinux/targeted/contexts/files/file_contexts.subs_dist",
    "etc/sudoers", "etc/sudoers.d/*",
    "etc/pam.d/*",
    "etc/polkit-1/rules.d/*", "usr/share/polkit-1/rules.d/*",
    "etc/ssh/sshd_config", "etc/ssh/sshd_config.d/*",
    "etc/security/*.conf",
    "etc/firewalld/firewalld.conf", "etc/crypttab",
    "usr/lib/systemd/system-preset/*", "usr/lib/systemd/user-preset/*",
)


def walk(root, top=""):
    base = os.path.join(root, top)
    # a top that is a symlink (root -> var/roothome) is walked through its
    # target already; following it would list the same files twice
    if top and os.path.islink(base):
        return
    for dirpath, dirnames, filenames in os.walk(base):
        rel = os.path.relpath(dirpath, root)
        rel = "" if rel == "." else rel + "/"
        # never cross into other mounts; skip pseudo filesystems if present
        dirnames[:] = [d for d in dirnames if not (rel == "" and d in ("proc", "sys", "dev"))]
        for name in dirnames + filenames:
            yield rel + name


def lstat(root, rel):
    try:
        return os.lstat(os.path.join(root, rel))
    except OSError:
        return None


def scan_secrets(root, owned):
    hits = []
    for rel in walk(root):
        st = lstat(root, rel)
        if not st or not stat.S_ISREG(st.st_mode) or st.st_size > SECRET_MAX_BYTES:
            continue
        if "/" + rel in owned and not rel.startswith(SECRET_SCAN_ALWAYS):
            continue
        try:
            with open(os.path.join(root, rel), "rb") as f:
                m = SECRET_RE.search(f.read())
        except OSError:
            continue
        if m:
            hits.append(f"{rel}: {m.group(0)[:40].decode(errors='replace')}")
    for rel in sorted(walk(root, "etc/ssh")) if os.path.isdir(os.path.join(root, "etc/ssh")) else []:
        if re.search(r"ssh_host_[a-z0-9]+_key$", rel):
            hits.append(f"{rel}: ssh host key baked into the image")
    mid = os.path.join(root, "etc/machine-id")
    if os.path.isfile(mid):
        content = open(mid).read().strip()
        if content and content != "uninitialized":
            hits.append("etc/machine-id: set in the image (every install would share it)")
    return sorted(hits)


def scan_privileged(root):
    out = []
    for rel in walk(root):
        st = lstat(root, rel)
        if not st or not stat.S_ISREG(st.st_mode):
            continue
        flags = []
        if st.st_mode & stat.S_ISUID:
            flags.append("setuid")
        if st.st_mode & stat.S_ISGID:
            flags.append("setgid")
        try:
            if os.getxattr(os.path.join(root, rel), "security.capability", follow_symlinks=False):
                flags.append("caps")
        except OSError:
            pass
        if flags:
            out.append(f"{rel} {','.join(flags)} {oct(st.st_mode & 0o7777)} {st.st_uid}:{st.st_gid}")
    return sorted(out)


def scan_writable(root):
    out = []
    for top in ("usr", "etc"):
        if not os.path.isdir(os.path.join(root, top)):
            continue
        for rel in walk(root, top):
            st = lstat(root, rel)
            if not st or stat.S_ISLNK(st.st_mode):
                continue
            if st.st_mode & stat.S_IWOTH:
                if stat.S_ISDIR(st.st_mode) and st.st_mode & stat.S_ISVTX:
                    continue
                out.append(f"{rel} {oct(st.st_mode & 0o7777)}")
    return sorted(out)


def scan_residue(root):
    out = []
    for top in RESIDUE_DIRS:
        if os.path.isdir(os.path.join(root, top)):
            out.extend(walk(root, top))
    return sorted(out)


def scan_units(root):
    out = []
    for top in UNIT_DIRS:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for entry in sorted(os.listdir(base)):
            if entry.endswith((".wants", ".requires", ".upholds")):
                for unit in sorted(os.listdir(os.path.join(base, entry))):
                    out.append(f"{top}/{entry}/{unit}")
    return sorted(out)


def scan_configs(root):
    found = {}
    for pattern in CONFIG_GLOBS:
        d = os.path.dirname(pattern)
        base = os.path.join(root, d)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            rel = f"{d}/{name}"
            if fnmatch.fnmatch(rel, pattern) and os.path.isfile(os.path.join(root, rel)):
                found[rel] = os.path.join(root, rel)
    return found


def read_list(path):
    try:
        with open(path) as f:
            return [line.rstrip("\n") for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rootfs", required=True)
    ap.add_argument("--owned", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--write-baseline")
    ap.add_argument("--report", default="/dev/stdout")
    a = ap.parse_args()

    owned = set(read_list(a.owned))
    current = {
        "privileged": scan_privileged(a.rootfs),
        "writable": scan_writable(a.rootfs),
        "residue": scan_residue(a.rootfs),
        "units": scan_units(a.rootfs),
    }
    configs = scan_configs(a.rootfs)
    secrets = scan_secrets(a.rootfs, owned)
    allow = read_list(os.path.join(a.baseline, "secrets-allow.txt"))
    secrets = [s for s in secrets if not any(fnmatch.fnmatch(s.split(":")[0], g) for g in allow)]

    if a.write_baseline:
        os.makedirs(a.write_baseline, exist_ok=True)
        for name, lines in current.items():
            with open(os.path.join(a.write_baseline, f"{name}.txt"), "w") as f:
                f.write("".join(line + "\n" for line in lines))
        cdir = os.path.join(a.write_baseline, "configs")
        shutil.rmtree(cdir, ignore_errors=True)
        for rel, src in configs.items():
            dst = os.path.join(cdir, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)

    report = []
    drift = False
    if secrets:
        report.append("## SECRETS (fatal: these must never ship)\n")
        report += [f"- `{s}`" for s in secrets]
        report.append("")
    for name, lines in current.items():
        base = read_list(os.path.join(a.baseline, f"{name}.txt"))
        added = sorted(set(lines) - set(base))
        removed = sorted(set(base) - set(lines))
        if added or removed:
            drift = True
            report.append(f"## {name}: {len(added)} new, {len(removed)} gone\n")
            report += [f"+ {x}" for x in added] + [f"- {x}" for x in removed]
            report.append("")
    cbase = os.path.join(a.baseline, "configs")
    base_configs = set()
    if os.path.isdir(cbase):
        for dirpath, _, files in os.walk(cbase):
            for fn in files:
                base_configs.add(os.path.relpath(os.path.join(dirpath, fn), cbase))
    for rel in sorted(set(configs) | base_configs):
        old = os.path.join(cbase, rel)
        old_lines = open(old, errors="replace").read().splitlines() if os.path.isfile(old) else []
        new_lines = open(configs[rel], errors="replace").read().splitlines() if rel in configs else []
        if old_lines != new_lines:
            drift = True
            report.append(f"## config {rel}\n")
            report.append("```diff")
            report += list(difflib.unified_diff(old_lines, new_lines, "baseline/" + rel, "image/" + rel, lineterm=""))
            report.append("```\n")

    with open(a.report, "w") as f:
        f.write("\n".join(report) + ("\n" if report else "no security drift, no secrets\n"))
    if secrets:
        return 2
    return 1 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
