#!/usr/bin/env python3
"""Upgrade smoke: boot an installed Margine (built from an OLD image), layer a
package, rebase it to a NEW image, reboot, and check the result over the
serial console. Standard library only; runs on a GitHub runner or any host
with qemu-system-x86_64, swtpm and OVMF.

  upgrade-smoke.py --disk disk.qcow2 --sb-vars sb-vars.fd --to <image ref>
                   [--layer htop] [--expect-id-like fedora] [--log serial.log]

The disk comes from bootc-image-builder with disk_config/disk-upgrade.toml:
user "probe" in wheel, password from UPGRADE_PASSWORD, console=ttyS0 on the
kernel command line (so a serial getty exists). Prints MARGINE-UPGRADE: PASS
or MARGINE-UPGRADE: FAIL <reasons> and exits 0 or 1.
"""
import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

PROMPT = "MPROMPT> "
# What the guest shell sends besides text: CSI sequences (colours, bracketed
# paste) and OSC sequences (Fedora's bash shell integration, OSC 3008, wraps
# every prompt and command). Both are stripped before matching.
ESCAPES = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\r")


class Serial:
    def __init__(self, path, log):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        for _ in range(100):
            try:
                self.sock.connect(path)
                break
            except OSError:
                time.sleep(0.2)
        else:
            raise SystemExit("serial socket never appeared")
        self.sock.settimeout(1.0)
        self.buf = ""
        self.log = open(log, "a", encoding="utf-8", errors="replace")

    def expect(self, pattern, timeout):
        """Wait until the regex matches the buffer; return the match. The
        buffer is cut after the match so the next expect starts fresh. A
        closed socket means QEMU is gone: say so, with its stderr."""
        rx = re.compile(pattern, re.S)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            m = rx.search(self.buf)
            if m:
                self.buf = self.buf[m.end():]
                return m
            try:
                data = self.sock.recv(65536)
            except socket.timeout:
                continue
            except OSError as e:
                err = open("qemu.err").read() if os.path.exists("qemu.err") else ""
                raise SystemExit(f"MARGINE-UPGRADE: FAIL serial connection lost ({e}); qemu said: {err.strip()[-400:]}")
            if not data:
                time.sleep(0.5)
                continue
            text = data.decode("utf-8", errors="replace")
            self.log.write(text)
            self.log.flush()
            self.buf = ESCAPES.sub("", self.buf + text)
            if len(self.buf) > 400000:
                self.buf = self.buf[-200000:]
        return None

    def send(self, text):
        self.sock.sendall(text.encode())

    def tail(self, n=40):
        return "\n".join(self.buf.splitlines()[-n:])


def start_vm(disk, sb_vars, mem, serial_path):
    """QEMU with the same shape as the smoke-boot gate: OVMF with Secure Boot
    enforcing, software TPM 2.0, user networking; reboots allowed."""
    code = None
    for c in ("/usr/share/OVMF/OVMF_CODE_4M.secboot.fd", "/usr/share/OVMF/OVMF_CODE.secboot.fd",
              "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd"):
        if os.path.exists(c):
            code = c
            break
    if not code:
        raise SystemExit("no Secure Boot OVMF code file found")
    shutil.copyfile(sb_vars, "ovmf_vars.fd")
    os.chmod("ovmf_vars.fd", 0o644)
    tpmdir = tempfile.mkdtemp(prefix="swtpm-")
    subprocess.run(["swtpm", "socket", "--tpm2", "--terminate", "--tpmstate", f"dir={tpmdir}",
                    "--ctrl", f"type=unixio,path={tpmdir}/sock", "--daemon"], check=True)
    cmd = ["qemu-system-x86_64", "-enable-kvm", "-m", str(mem), "-smp", "4",
           "-machine", "q35,smm=on,kernel-irqchip=split",
           "-global", "driver=cfi.pflash01,property=secure,value=on",
           "-chardev", f"socket,id=chrtpm,path={tpmdir}/sock", "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
           "-device", "tpm-tis,tpmdev=tpm0",
           "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
           "-drive", "if=pflash,format=raw,file=ovmf_vars.fd",
           "-drive", f"file={disk},format=qcow2,if=virtio",
           "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
           "-chardev", f"socket,id=ser0,path={serial_path},server=on,wait=off", "-serial", "chardev:ser0",
           "-display", "none"]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=open("qemu.err", "w"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--disk", required=True)
    ap.add_argument("--sb-vars", required=True)
    ap.add_argument("--to", required=True, help="image ref to rebase to (digest form preferred)")
    ap.add_argument("--layer", default="cowsay", help="package to layer before the rebase (one the image lacks); empty = none")
    ap.add_argument("--expect-id-like", default="fedora")
    ap.add_argument("--user", default="probe")
    ap.add_argument("--password", default=os.environ.get("UPGRADE_PASSWORD", ""))
    ap.add_argument("--log", default="serial.log")
    ap.add_argument("--mem", type=int, default=4096)
    a = ap.parse_args()
    if not a.password:
        raise SystemExit("UPGRADE_PASSWORD not set")

    serial_path = os.path.abspath("serial.sock")
    if os.path.exists(serial_path):
        os.unlink(serial_path)
    vm = start_vm(a.disk, a.sb_vars, a.mem, serial_path)
    s = Serial(serial_path, a.log)
    failures = []
    t0 = time.monotonic()

    def say(msg):
        print(f"[{int(time.monotonic() - t0):4d}s] {msg}", flush=True)

    def fail(msg):
        failures.append(msg)
        say("FAIL: " + msg)

    def login(timeout):
        if not s.expect(r"login: ?$", timeout):
            say(s.tail())
            raise SystemExit("MARGINE-UPGRADE: FAIL no login prompt within %ds" % timeout)
        s.send(a.user + "\n")
        if not s.expect(r"Password: ?", 60):
            raise SystemExit("MARGINE-UPGRADE: FAIL no password prompt")
        s.send(a.password + "\n")
        time.sleep(3)
        # A bare bash: no profile, so no shell integration and no colour
        # prompt; our own prompt marks the end of each command.
        s.send("exec bash --noprofile --norc\n")
        time.sleep(1)
        s.send(f"stty -echo; PS1='{PROMPT}'; unset HISTFILE PROMPT_COMMAND\n")
        if not s.expect(re.escape(PROMPT) + r"\s*$", 60):
            say(s.tail())
            raise SystemExit("MARGINE-UPGRADE: FAIL shell prompt not reached after login")

    def run(cmd, timeout=120):
        """Run a command, return (rc, output)."""
        s.send(cmd + '; echo "RC=$?"\n')
        m = s.expect(r"RC=(\d+)\s*\n.*?" + re.escape(PROMPT) + r"\s*$", timeout)
        if not m:
            return None, s.tail(60)
        return int(m.group(1)), None

    def capture(cmd, timeout=120):
        """Run a command whose output we want: wrap in markers."""
        s.send(f'echo __B__; {cmd}; echo "__E__ RC=$?"\n')
        m = s.expect(r"__B__\s*\n(.*?)__E__ RC=(\d+).*?" + re.escape(PROMPT) + r"\s*$", timeout)
        if not m:
            return None, s.tail(60)
        return int(m.group(2)), m.group(1)

    sudo = f"echo '{a.password}' | sudo -S -p '' "

    # ---- first boot: the OLD image ----------------------------------------
    say("waiting for the first login prompt (old image)")
    login(900)
    rc, out = capture("rpm-ostree status -b | head -6; source /etc/os-release; echo ID_LIKE=$ID_LIKE; mokutil --sb-state; ls /dev/tpm0", 120)
    say("old deployment:\n" + (out or ""))
    if out and "SecureBoot enabled" not in out:
        fail("old image not booted with Secure Boot enabled")
    if a.layer:
        say(f"layering {a.layer} on the old image")
        rc, out = capture(sudo + f"rpm-ostree install -y --idempotent {a.layer} 2>&1 | tail -5", 1200)
        if rc != 0:
            fail(f"layering {a.layer} failed: {out}")
        else:
            rc, out = capture("rpm-ostree status | grep -A1 -i LayeredPackages | head -3", 60)
            say("layered: " + (out or "").strip())
    say(f"rebasing to {a.to}")
    t_rebase = time.monotonic()
    rc, out = capture(sudo + f"rpm-ostree rebase ostree-image-signed:docker://{a.to} 2>&1 | tail -8", 2400)
    say(f"rebase took {int(time.monotonic() - t_rebase)}s, rc={rc}")
    if rc != 0:
        say(out or "")
        print("MARGINE-UPGRADE: FAIL rebase failed")
        s.send(sudo + "systemctl poweroff\n")
        vm.wait(timeout=120)
        return 1
    say("rebase done:\n" + (out or ""))
    rc, out = capture("rpm-ostree status | head -12", 60)
    say((out or "").strip())
    s.send(sudo + "systemctl reboot\n")

    # ---- second boot: the NEW image ----------------------------------------
    say("waiting for the login prompt after the reboot (new image)")
    login(900)
    rc, out = capture("rpm-ostree status -b | head -8", 120)
    say("booted deployment:\n" + (out or ""))
    digest = a.to.split("@")[-1] if "@" in a.to else ""
    if digest and (not out or digest[:20] not in out):
        fail("the booted deployment is not the target image")
    rc, out = capture("source /etc/os-release; echo ID_LIKE=$ID_LIKE; echo PRETTY=$PRETTY_NAME", 60)
    say((out or "").strip())
    if a.expect_id_like and (not out or f"ID_LIKE={a.expect_id_like}" not in out):
        fail(f"ID_LIKE is not {a.expect_id_like}")
    rc, out = capture("mokutil --sb-state", 60)
    if not out or "SecureBoot enabled" not in out:
        fail("Secure Boot not enabled after the upgrade")
    rc, out = capture("systemctl --failed --no-legend --plain", 60)
    if out and out.strip():
        fail("failed units after the upgrade: " + out.strip().replace("\n", " | "))
    else:
        say("no failed units")
    if a.layer:
        rc, out = capture(f"rpm -q {a.layer}", 60)
        if rc != 0:
            fail(f"layered package {a.layer} did not survive the rebase")
        else:
            say(f"layered package kept: {(out or '').strip()}")
    rc, out = capture("for u in rpm-ostreed-automatic.timer flatpak-system-update.timer flatpak-add-fedora-repos.service; do printf '%s=%s\\n' $u $(systemctl is-enabled $u 2>&1 | tail -1); done", 60)
    say("base units: " + (out or "").strip().replace("\n", " "))
    for u in ("rpm-ostreed-automatic.timer", "flatpak-system-update.timer", "flatpak-add-fedora-repos.service"):
        if out and f"{u}=masked" not in out:
            fail(f"{u} is not masked on the new deployment")
    rc, out = capture("flatpak remotes --system --columns=name", 60)
    names = (out or "").split()
    say("flatpak remotes: " + " ".join(names))
    if "flathub" not in names:
        fail("flathub remote missing")
    if "fedora" in names:
        fail("fedora flatpak remote present (Flathub only expected)")
    rc, out = capture("command -v uupd >/dev/null && systemctl is-enabled uupd.timer", 60)
    if rc != 0:
        fail("uupd or uupd.timer missing on the new deployment")
    rc, out = capture("ls /etc/systemd/system/default.target.wants/ /etc/systemd/system/multi-user.target.wants/ 2>/dev/null | grep -E 'bluefin|brew-setup|input-remapper|tailscaled|docker' || echo none", 60)
    say("old-base links in /etc: " + (out or "").strip())
    if out and "none" not in out:
        fail("enablement links of the old base survived the /etc merge: " + out.strip().replace("\n", " "))
    rc, out = capture("ostree admin config-diff 2>/dev/null | head -30", 60)
    say("/etc differences from the image (first 30):\n" + (out or ""))
    rc, out = capture("L=/usr/share/margine/gaming-native-packages.txt; if [ -r $L ]; then " + sudo +
                      "timeout 600 rpm-ostree install --dry-run $(grep -vE '^\\s*(#|$)' $L) 2>&1 | tail -4; else echo 'no gaming list'; fi", 900)
    say("gaming-native dry run: " + (out or "").strip().replace("\n", " | ")[-400:])
    if rc != 0:
        fail("the gaming-native layer does not resolve on the new deployment")
    rc, out = capture(sudo + "MARGINE_VALIDATE_CONTEXT=live margine-validate-margine-system 2>&1 | grep -E 'FAIL|PASSED|FAILED|WARN' | tail -25", 900)
    say("validator:\n" + (out or ""))
    if not out or "PASSED" not in out:
        fail("margine-validate-margine-system did not pass")
    rc, out = capture("journalctl -b -p err --no-pager 2>/dev/null | tail -15", 60)
    say("journal errors (this boot, last 15):\n" + (out or ""))
    rc, out = capture("df -h / | tail -1; rpm-ostree status | grep -c '^ *ostree-image' ", 60)
    say("disk and deployments: " + (out or "").strip().replace("\n", " | "))

    s.send(sudo + "systemctl poweroff\n")
    try:
        vm.wait(timeout=180)
    except subprocess.TimeoutExpired:
        vm.kill()
    if failures:
        print("MARGINE-UPGRADE: FAIL " + "; ".join(failures))
        return 1
    print("MARGINE-UPGRADE: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
