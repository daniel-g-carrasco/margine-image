# 18 — Observability

Three independent mechanisms keep the maintainer informed about the
state of the build pipeline and of any deployed Margine system. Each
covers a failure mode the others can't.

## 1 — ntfy push notifications (build outcome, smoke-boot, promotion)

Every CI step that has a "user actionable outcome" pushes to a
private ntfy.sh topic. The topic name is the access secret (long
random string), kept in the GH Actions secret `NTFY_TOPIC_URL` and
never committed. Daniel subscribes via the
[ntfy mobile app](https://ntfy.sh).

Events emitted:

- **`build.yml` end** — outcome (success / failure / cancelled) of the
  candidate build. Click opens the run on GitHub.
- **`smoke-boot.yml` end** — whether the QEMU boot reached a usable
  state; if yes, that `:stable` was just promoted; if no, the build
  is broken and should be investigated before any `bootc upgrade`.
- **`build-disk.yml` end** (per matrix job) — qcow2 / ISO upload to
  Internet Archive + publication of the HTML index. One push per
  artifact, so the maintainer knows when a new ISO is downloadable.

The same topic infrastructure is used by the dashboard and PVE host
to send adjacent alerts (Proxmox backup outcomes, Watchtower image
updates of containers on the network). See the runbook in the
companion `proxmox-pve1` repo for details.

## 2 — `margine-staleness.timer` (client side)

A `systemd --user` timer installed via `/etc/skel` (so every new
account picks it up on first login), runs every 12 hours and warns
the user if `ghcr.io/.../margine:stable` hasn't been refreshed in
more than 7 days. Implementation:
`/usr/libexec/margine-staleness-check`.

The point is to catch the **silent failure** mode where the user
expects their system to update but the build pipeline upstream has
been broken for days. The dashboard (on the builder VM) and the
ntfy pushes already catch this from the maintainer side; the
staleness check catches it from the deployed-system side, so a user
who only checks their phone for ntfy will still notice if their
laptop hasn't seen a fresh image in over a week.

The check uses `skopeo inspect docker://...:stable` (no auth needed,
public image) and compares `Created` to current time. Warning level
crosses to *critical* at >14 days.

## 3 — `margine-upgrade-notify.service` (client side)

A `systemd --user` one-shot wired to `default.target.wants` (so it
fires on every login). Compares the currently booted image digest
(`bootc status --json`) to the previous run's digest, cached at
`~/.cache/margine/last-booted-digest`. On a change, a `notify-send`
pops up: "Margine updated to vXXX".

Reassures the user that a reboot did pick up the new image — useful
because Margine relies on `bootc upgrade` daily, and after a normal
reboot it's not immediately obvious which deployment the system
booted into.

## How it all fits

```
CI side                                          Deployed Margine side
─────────                                        ─────────────────────
build.yml      → ntfy: "build OK"  →  📱        margine-staleness.timer
smoke-boot.yml → ntfy: "boot OK,                  → notify-send if
                 :stable promoted" →  📱            :stable >7 days old
build-disk.yml → ntfy: "ISO live"  →  📱
                                                  margine-upgrade-notify
                                                  → notify-send on each
                                                    deployment change
```

Together they make it hard for a Margine system to drift into
"thinks it's fresh but isn't" or "just updated but didn't notice".
