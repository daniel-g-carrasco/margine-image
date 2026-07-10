#!/usr/bin/env python3
"""Fetch and rewrite the public docs pages for file:// offline use."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen


# Fallback route list — used only when the live site's machine-readable
# /routes.json (emitted by its prerender step since 2026-06-12) cannot
# be fetched or parsed. With routes.json available, a new docs page or
# handbook chapter reaches the offline mirror with zero edits here.
# (This hardcoded copy had already drifted: /docs/install-iso was
# missing, so the offline mirror never carried the install guide.)
ROUTES = [
    "/docs",
    "/docs/what-is-margine",
    "/docs/why-margine",
    "/docs/install-status",
    "/docs/install-iso",
    "/docs/first-boot",
    "/docs/install-apps",
    "/docs/your-home",
    "/docs/workflows",
    "/docs/gaming",
    "/docs/updates-and-rollback",
    "/docs/settings",
    "/docs/cpu-scheduler",
    "/docs/scroll-and-gestures",
    "/docs/audio",
    "/docs/troubleshooting",
    "/docs/faq",
    # Handbook (added 2026-06-12) — the same offline-first treatment as
    # the wiki. Chapter slugs mirror the site's generated manifest.
    "/handbook",
    "/handbook/atomic-model",
    "/handbook/repo-and-containerfile",
    "/handbook/kernel",
    "/handbook/secure-boot",
    "/handbook/desktop-payload",
    "/handbook/flatpaks-and-offline-docs",
    "/handbook/rechunk-and-oci-packaging",
    "/handbook/signing-supply-chain",
    "/handbook/ci-cd",
    "/handbook/installers-and-iso",
    "/handbook/distribution-and-updates",
    "/handbook/validation-and-lessons",
]

LINK_RE = re.compile(r"<link\b[^>]*>", re.IGNORECASE)
SCRIPT_RE = re.compile(r"<script\b[^>]*>.*?</script\s*>", re.IGNORECASE | re.DOTALL)
BASE_RE = re.compile(r"<base\b[^>]*>", re.IGNORECASE)
ATTR_RE_TEMPLATE = r"""\b{attr}\s*=\s*(['"])(.*?)\1"""
URL_ATTR_RE = re.compile(r"""\b(?P<attr>href|src)\s*=\s*(?P<quote>['"])(?P<url>.*?)(?P=quote)""", re.IGNORECASE)
# <img srcset> and <source srcset> — a comma-separated list of
# "url [descriptor]" candidates. Astro's <picture> serves avif/webp
# here with the <img src> as the fallback, so a mirror that ignores
# srcset shows nothing: the browser picks a (broken, remote) source
# before ever reaching the localized <img src>.
SRCSET_ATTR_RE = re.compile(r"""\bsrcset\s*=\s*(?P<quote>['"])(?P<val>.*?)(?P=quote)""", re.IGNORECASE | re.DOTALL)
CSS_URL_RE = re.compile(r"""url\(\s*(?P<quote>['"]?)(?P<url>/[^)'"]+)(?P=quote)\s*\)""", re.IGNORECASE)

# A URL is an asset to download (not a page to link) when its path ends
# in a media/font extension or lives under one of the site's asset dirs.
ASSET_EXT_RE = re.compile(
    r"\.(?:png|jpe?g|webp|avif|gif|svg|ico|bmp|woff2?|ttf|otf|eot|mp4|webm|ogg|oga|mp3|wav|pdf)(?:[?#]|$)",
    re.IGNORECASE,
)
ASSET_DIRS = ("/_astro/", "/assets/", "/screenshots/", "/fonts/", "/img/", "/images/", "/media/")

# abs_url -> mirror file path (str) once downloaded, or None if the fetch
# failed. Screenshots repeat across pages, so download each asset once.
_asset_cache: dict[str, str | None] = {}


def attr_value(tag: str, attr: str) -> str | None:
    match = re.search(ATTR_RE_TEMPLATE.format(attr=re.escape(attr)), tag, re.IGNORECASE)
    return match.group(2) if match else None


def fetch_bytes(url: str, retries: int = 5) -> bytes:
    last_error: Exception | None = None
    request = Request(url, headers={"User-Agent": "margine-image-offline-docs/1.0"})

    for attempt in range(1, retries + 1):
        try:
            with urlopen(request, timeout=30) as response:
                return response.read()
        except Exception as exc:  # noqa: BLE001 - build helper should retry broad network failures.
            last_error = exc
            if attempt == retries:
                break
            sleep_s = attempt * 10
            print(f"[offline-docs] fetch failed ({attempt}/{retries}) for {url}: {exc}; sleeping {sleep_s}s", file=sys.stderr)
            time.sleep(sleep_s)

    raise RuntimeError(f"failed to fetch {url}: {last_error}")


def fetch_text(url: str, retries: int = 5) -> str:
    return fetch_bytes(url, retries).decode("utf-8")


def output_path_for_route(output_dir: Path, route: str) -> Path:
    # /docs -> docs/index.html ; /handbook/kernel -> handbook/kernel/index.html
    slug = route.rstrip("/").strip("/")
    return output_dir / slug / "index.html"


# Sections mirrored offline; links to anything else stay absolute.
MIRRORED_PREFIXES = ("/docs", "/handbook")


def normalize_docs_path(path: str) -> str | None:
    clean = path.rstrip("/")
    # A routes.json entry like /docs/../../usr starts with /docs/ but must
    # never be treated as a mirrored route (it would write a page outside
    # the mirror). Reject any traversal segment up front.
    if ".." in clean.split("/"):
        return None
    for prefix in MIRRORED_PREFIXES:
        if clean == prefix or clean.startswith(prefix + "/"):
            return clean
    return None


def looks_like_asset(path: str) -> bool:
    return bool(ASSET_EXT_RE.search(path)) or path.startswith(ASSET_DIRS)


def _within(target: Path, root: Path) -> bool:
    """True only if target resolves inside root. This writer runs as root
    at image build and fetches paths from a remote site; a hostile or
    MITM'd origin could reference `/../../etc/x` (in a link, an <img>/CSS
    url, or a routes.json entry) to escape the mirror and plant a
    root-owned file anywhere. pathlib does NOT collapse `..`, so every
    write target is resolved and checked against this before it is used."""
    try:
        target.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def localize_asset(path: str, output_dir: Path, base_url: str, current_dir: Path) -> str | None:
    """Download a same-host asset into the mirror once, mirroring its
    server path (/screenshots/x.png -> <output_dir>/screenshots/x.png),
    and return the path relative to current_dir. Returns None if the
    fetch fails, so the caller keeps the original URL (page still works
    online, just that one asset is remote)."""
    clean = path.split("#", 1)[0].split("?", 1)[0]
    if not clean.startswith("/"):
        return None
    abs_url = base_url + clean
    if abs_url not in _asset_cache:
        dest = output_dir / clean.lstrip("/")
        if not _within(dest, output_dir):
            print(f"[offline-docs]   refusing out-of-tree asset path {clean}", file=sys.stderr)
            _asset_cache[abs_url] = None
        else:
            try:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(fetch_bytes(abs_url))
                _asset_cache[abs_url] = str(dest)
                print(f"[offline-docs]   asset {abs_url} -> {dest}")
            except Exception as exc:  # noqa: BLE001 - a missing asset must not fail the whole build.
                print(f"[offline-docs]   asset fetch failed for {abs_url}: {exc}", file=sys.stderr)
                _asset_cache[abs_url] = None
    dest_str = _asset_cache[abs_url]
    if dest_str is None:
        return None
    return os.path.relpath(dest_str, current_dir).replace(os.sep, "/")


def rewrite_css_urls(css: str, base_url: str, output_dir: Path, current_dir: Path) -> str:
    def replace(match: re.Match[str]) -> str:
        quote = match.group("quote") or ""
        url = match.group("url")
        local = localize_asset(url, output_dir, base_url, current_dir)
        target = local if local is not None else urljoin(base_url, url)
        return f"url({quote}{target}{quote})"

    return CSS_URL_RE.sub(replace, css)


def inline_or_remove_link(match: re.Match[str], base_url: str, output_dir: Path, current_dir: Path) -> str:
    tag = match.group(0)
    rel = (attr_value(tag, "rel") or "").lower()
    href = attr_value(tag, "href")

    if "stylesheet" in rel and href:
        css_url = urljoin(base_url, href)
        css = rewrite_css_urls(fetch_text(css_url), base_url, output_dir, current_dir)
        return f'<style data-margine-offline="stylesheet">\n{css}\n</style>'

    if "modulepreload" in rel or "preload" in rel or "prefetch" in rel or "preconnect" in rel:
        return ""

    if href and href.startswith("/assets/"):
        return ""

    # A <link rel="icon"/"apple-touch-icon"/…> points at a real image;
    # keep it and localize the file so the favicon works offline too.
    if href and looks_like_asset(href):
        local = localize_asset(urlsplit(urljoin(base_url, href)).path, output_dir, base_url, current_dir)
        if local is not None:
            return re.sub(ATTR_RE_TEMPLATE.format(attr="href"), f'href="{local}"', tag, count=1, flags=re.IGNORECASE)

    return tag


def rewrite_url(url: str, route: str, output_dir: Path, base_url: str, current_dir: Path, attr: str = "href") -> str:
    if not url or url.startswith("#") or url.startswith(("mailto:", "tel:", "data:", "blob:")):
        return url

    parsed = urlsplit(url)
    base_host = urlsplit(base_url).netloc
    if parsed.netloc and parsed.netloc != base_host:
        return url

    path = parsed.path if parsed.scheme or parsed.netloc else urlsplit(urljoin(base_url, url)).path

    # Same-host asset (image, font, media, PDF): download + link locally.
    # Checked before the docs-route branch so a hashed /_astro/*.png is
    # never mistaken for a page. src/srcset are always assets; an <a
    # href> only when it points at a file.
    if path.startswith("/") and (attr != "href" or looks_like_asset(path)):
        local = localize_asset(path, output_dir, base_url, current_dir)
        if local is not None:
            return local

    # Mirrored doc/handbook page -> local relative page.
    docs_route = normalize_docs_path(path)
    if docs_route:
        target = output_path_for_route(output_dir, docs_route)
        relative = os.path.relpath(target, current_dir).replace(os.sep, "/")
        if parsed.fragment:
            relative = f"{relative}#{parsed.fragment}"
        return relative

    # Site root -> the mirror's redirect index, so the logo/home link
    # lands on the offline docs instead of a dead absolute URL.
    if path in ("", "/"):
        target = output_dir / "index.html"
        return os.path.relpath(target, current_dir).replace(os.sep, "/")

    # Any other same-host page (e.g. /status) is not mirrored; it needs
    # the network by nature, so keep it absolute.
    if url.startswith("/"):
        return urljoin(base_url, url)

    return url


def rewrite_links(html_text: str, route: str, output_dir: Path, base_url: str, current_dir: Path) -> str:
    def replace(match: re.Match[str]) -> str:
        attr = match.group("attr")
        new_url = rewrite_url(match.group("url"), route, output_dir, base_url, current_dir, attr)
        return f"{attr}={match.group('quote')}{new_url}{match.group('quote')}"

    return URL_ATTR_RE.sub(replace, html_text)


def rewrite_srcset(html_text: str, route: str, output_dir: Path, base_url: str, current_dir: Path) -> str:
    def replace(match: re.Match[str]) -> str:
        candidates = []
        for part in match.group("val").split(","):
            part = part.strip()
            if not part:
                continue
            bits = part.split(None, 1)
            new_url = rewrite_url(bits[0], route, output_dir, base_url, current_dir, "src")
            candidates.append(f"{new_url} {bits[1]}" if len(bits) > 1 else new_url)
        return f"srcset={match.group('quote')}{', '.join(candidates)}{match.group('quote')}"

    return SRCSET_ATTR_RE.sub(replace, html_text)


def rewrite_html(html_text: str, route: str, output_dir: Path, base_url: str) -> str:
    current_dir = output_path_for_route(output_dir, route).parent
    html_text = BASE_RE.sub("", html_text)
    html_text = SCRIPT_RE.sub("", html_text)
    html_text = LINK_RE.sub(lambda match: inline_or_remove_link(match, base_url, output_dir, current_dir), html_text)
    html_text = rewrite_links(html_text, route, output_dir, base_url, current_dir)
    html_text = rewrite_srcset(html_text, route, output_dir, base_url, current_dir)
    return html_text


def write_redirect_index(output_dir: Path) -> None:
    index = output_dir / "index.html"
    index.write_text(
        """<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="refresh" content="0; url=docs/index.html">
    <title>Margine documentation</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: system-ui, sans-serif; background: #1d120d; color: #f5eee8; }
      a { color: #d97757; }
    </style>
  </head>
  <body>
    <p>Opening <a href="docs/index.html">Margine documentation</a>.</p>
  </body>
</html>
""",
        encoding="utf-8",
    )


def discover_routes(base_url: str) -> list[str]:
    """Prefer the site's own /routes.json; fall back to the static list.

    Only routes under MIRRORED_PREFIXES are mirrored (the home page and
    anything else stay online-only)."""
    try:
        raw = fetch_text(f"{base_url}/routes.json", retries=2)
        routes = json.loads(raw)
        mirrored = [
            r for r in routes
            if isinstance(r, str) and normalize_docs_path(r) is not None
        ]
        if len(mirrored) >= 10:
            print(f"[offline-docs] using {len(mirrored)} routes from {base_url}/routes.json")
            return mirrored
        print(
            f"[offline-docs] routes.json suspiciously small ({len(mirrored)}) — using static fallback",
            file=sys.stderr,
        )
    except Exception as exc:  # noqa: BLE001 - any fetch/parse problem means fallback.
        print(f"[offline-docs] routes.json unavailable ({exc}) — using static fallback", file=sys.stderr)
    return ROUTES


def build_offline_docs(output_dir: Path, base_url: str) -> None:
    base_url = base_url.rstrip("/")
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)
    _asset_cache.clear()

    routes = discover_routes(base_url)
    for route in routes:
        source_url = f"{base_url}{route}/"
        destination = output_path_for_route(output_dir, route)
        if not _within(destination, output_dir):
            print(f"[offline-docs] skipping out-of-tree route {route}", file=sys.stderr)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        print(f"[offline-docs] {source_url} -> {destination}")
        html_text = fetch_text(source_url)
        destination.write_text(rewrite_html(html_text, route, output_dir, base_url), encoding="utf-8")

    downloaded = sum(1 for v in _asset_cache.values() if v is not None)
    failed = sum(1 for v in _asset_cache.values() if v is None)
    print(f"[offline-docs] localized {downloaded} asset(s); {failed} failed")

    write_redirect_index(output_dir)
    (output_dir / "manifest.txt").write_text("\n".join(routes) + "\n", encoding="utf-8")
    # Freshness stamp consumed by docs-refresh to decide whether the /usr
    # seed (image build) is newer than the /var mirror (runtime refresh
    # by margine-docs-refresh.service). Epoch seconds.
    (output_dir / "stamp").write_text(f"{int(time.time())}\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="https://margine.dev")
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    build_offline_docs(args.output_dir, args.base_url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
