# 19 — ISO distribution (torrent-first via Internet Archive)

## The model

```
GHA workflow build-disk.yml (on the self-hosted runner margine-builder)
  │
  │   bootc-image-builder pulls ghcr/margine:stable
  │   ↓ produces ISO (Anaconda) + qcow2 (raw VM disk)
  │
  ├──▶ Internet Archive (`ia upload`)
  │        ↓ IA derives torrent + 3 HTTP mirrors, seeds forever
  │
  └──▶ rsync to edge VM 110 (the-empty.place webserver)
           ↓ /var/www/files-margine/
           ↓ Caddy serves files.the-empty.place
           ↓   index.html (with magnet + IA mirror links)
           ↓   SHA256SUMS
           ↓   ISO + qcow2 (7-day local fallback)
```

`https://files.the-empty.place/` shows the index page. The big
binaries' authoritative copy lives at Internet Archive; the local
copy on edge is just a faster-near-by-network mirror for the first
few days after a release.

## Why this shape

| Constraint | Solution |
| --- | --- |
| Cloudflare Free TOS doesn't allow serving large non-HTML content from the proxy | Don't. The proxy serves only HTML + sha256 + a 7-day .iso fallback for fresh releases. The canonical store is IA, off-CF. |
| The home server's upstream is ADSL-class — saturating it with ISO downloads breaks everything else | IA seeds the bytes peer-to-peer + via its own mirrors. The home server uploads zero bytes for big artifacts. |
| Single point of failure (the home server) shouldn't kill availability of past releases | IA is a near-permanent archive. Even if the edge VM is offline, every release made so far stays reachable via IA. |
| Verify integrity end-to-end | BitTorrent has per-chunk SHA-1 built in. We also publish SHA256SUMS so a user with `sha256sum` can check the file. The IA also publishes its own SHA-1 for each upload. |

## What the user does

The user opens <https://files.the-empty.place/> and gets a short page
with, per published release:

- Download `.torrent` (recommended — resumable, P2P)
- Direct HTTP download (IA mirror)
- Link to the IA release page (all three IA mirror endpoints)
- The SHA256SUMS file for verification

## What the maintainer does

Nothing on a per-release basis — the workflow handles everything.
Initial setup, documented in
[`proxmox-pve1/docs/operations/iso-distribution.md`](https://github.com/daniel-g-carrasco/proxmox-pve1/blob/main/docs/operations/iso-distribution.md):

1. Add `IA_ACCESS_KEY` + `IA_SECRET_KEY` repo secrets (S3-style
   from `https://archive.org/account/s3.php`).
2. Add `NTFY_TOPIC_URL` repo secret for the build outcome push.
3. Ship the SSH key from the builder to the `edge-files-margine`
   user on edge (restricted via `authorized_keys` `restrict`).
4. Configure Caddy on edge to serve `/var/www/files-margine` at
   `files.the-empty.place` (DNS-01 TLS via Cloudflare API token).
5. Add the daily systemd timer that purges files older than 7 days
   from `/var/www/files-margine` (override default `90` via
   `MARGINE_FILES_RETENTION_DAYS=7` env in the unit drop-in).

Manual trigger of a new build:

```sh
gh workflow run build-disk.yml --repo daniel-g-carrasco/margine-image
```

Build time is ~30 min for qcow2 + ~40 min for ISO. Once the workflow
ends with success, both the IA listing
(`https://archive.org/details/margine-anaconda-iso-<date>`) and the
`files.the-empty.place` page are live and the user gets an ntfy push.

## Retention policy

| Where | How long | Why |
| --- | --- | --- |
| Internet Archive | "Forever" (no expiry) | Long-tail availability — old releases stay reproducible / installable |
| `edge:/var/www/files-margine/*.iso` | 7 days | Faster local fetch for the few days after a release; after that the user goes through IA anyway. Saves disk on the small edge VM. |
| `edge:/var/www/files-margine/index.html` + `SHA256SUMS` | overwritten by the next build | Always reflect the latest release |

## Why not host the ISO directly on edge with Caddy?

We tried first. Two problems came out:

1. **Cloudflare TOS** discourages large binary content over the free
   proxy. Setting "DNS only" sidesteps this but exposes the home IP.
2. **Home server upload bandwidth** — even with a 5 MB/s `qm set ...
   net0,rate=5` cap, a single concurrent ISO download saturates the
   useful upload of an ADSL line. With Cloudflare proxied, you could
   add CF caching but only for files under ~512 MB, which excludes
   our 5 GB ISOs.

IA + magnet links makes both go away: the home server uploads only
the small HTML, and CF can stay proxied for IP-privacy.
