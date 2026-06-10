#!/usr/bin/env python3
"""Fetch and rewrite the public docs pages for file:// offline use."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import time
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen


ROUTES = [
    "/docs",
    "/docs/what-is-margine",
    "/docs/why-margine",
    "/docs/install-status",
    "/docs/first-boot",
    "/docs/install-apps",
    "/docs/your-home",
    "/docs/workflows",
    "/docs/gaming",
    "/docs/updates-and-rollback",
    "/docs/settings",
    "/docs/troubleshooting",
    "/docs/faq",
]

LINK_RE = re.compile(r"<link\b[^>]*>", re.IGNORECASE)
SCRIPT_RE = re.compile(r"<script\b[^>]*>.*?</script\s*>", re.IGNORECASE | re.DOTALL)
BASE_RE = re.compile(r"<base\b[^>]*>", re.IGNORECASE)
ATTR_RE_TEMPLATE = r"""\b{attr}\s*=\s*(['"])(.*?)\1"""
URL_ATTR_RE = re.compile(r"""\b(?P<attr>href|src)\s*=\s*(?P<quote>['"])(?P<url>.*?)(?P=quote)""", re.IGNORECASE)
CSS_URL_RE = re.compile(r"""url\(\s*(?P<quote>['"]?)(?P<url>/[^)'"]+)(?P=quote)\s*\)""", re.IGNORECASE)


def attr_value(tag: str, attr: str) -> str | None:
    match = re.search(ATTR_RE_TEMPLATE.format(attr=re.escape(attr)), tag, re.IGNORECASE)
    return match.group(2) if match else None


def fetch_text(url: str, retries: int = 5) -> str:
    last_error: Exception | None = None
    request = Request(url, headers={"User-Agent": "margine-image-offline-docs/1.0"})

    for attempt in range(1, retries + 1):
        try:
            with urlopen(request, timeout=30) as response:
                data = response.read()
            return data.decode("utf-8")
        except Exception as exc:  # noqa: BLE001 - build helper should retry broad network failures.
            last_error = exc
            if attempt == retries:
                break
            sleep_s = attempt * 10
            print(f"[offline-docs] fetch failed ({attempt}/{retries}) for {url}: {exc}; sleeping {sleep_s}s", file=sys.stderr)
            time.sleep(sleep_s)

    raise RuntimeError(f"failed to fetch {url}: {last_error}")


def output_path_for_route(output_dir: Path, route: str) -> Path:
    route = route.rstrip("/")
    slug = route.removeprefix("/docs").strip("/")
    if not slug:
        return output_dir / "docs" / "index.html"
    return output_dir / "docs" / slug / "index.html"


def normalize_docs_path(path: str) -> str | None:
    clean = path.rstrip("/")
    if clean == "/docs":
        return "/docs"
    if clean.startswith("/docs/"):
        return clean
    return None


def rewrite_css_urls(css: str, base_url: str) -> str:
    def replace(match: re.Match[str]) -> str:
        quote = match.group("quote") or ""
        url = match.group("url")
        return f"url({quote}{urljoin(base_url, url)}{quote})"

    return CSS_URL_RE.sub(replace, css)


def inline_or_remove_link(match: re.Match[str], base_url: str) -> str:
    tag = match.group(0)
    rel = (attr_value(tag, "rel") or "").lower()
    href = attr_value(tag, "href")

    if "stylesheet" in rel and href:
        css_url = urljoin(base_url, href)
        css = rewrite_css_urls(fetch_text(css_url), base_url)
        return f'<style data-margine-offline="stylesheet">\n{css}\n</style>'

    if "modulepreload" in rel or "preload" in rel or "prefetch" in rel or "preconnect" in rel:
        return ""

    if href and href.startswith("/assets/"):
        return ""

    return tag


def rewrite_url(url: str, route: str, output_dir: Path, base_url: str) -> str:
    if not url or url.startswith("#") or url.startswith(("mailto:", "tel:", "data:", "blob:")):
        return url

    parsed = urlsplit(url)
    base_host = urlsplit(base_url).netloc
    if parsed.netloc and parsed.netloc != base_host:
        return url

    path = parsed.path if parsed.scheme or parsed.netloc else urlsplit(urljoin(base_url, url)).path
    docs_route = normalize_docs_path(path)
    if docs_route:
        current = output_path_for_route(output_dir, route).parent
        target = output_path_for_route(output_dir, docs_route)
        relative = os.path.relpath(target, current).replace(os.sep, "/")
        if parsed.fragment:
            relative = f"{relative}#{parsed.fragment}"
        return relative

    if url.startswith("/"):
        return urljoin(base_url, url)

    return url


def rewrite_links(html_text: str, route: str, output_dir: Path, base_url: str) -> str:
    def replace(match: re.Match[str]) -> str:
        return f"{match.group('attr')}={match.group('quote')}{rewrite_url(match.group('url'), route, output_dir, base_url)}{match.group('quote')}"

    return URL_ATTR_RE.sub(replace, html_text)


def rewrite_html(html_text: str, route: str, output_dir: Path, base_url: str) -> str:
    html_text = BASE_RE.sub("", html_text)
    html_text = SCRIPT_RE.sub("", html_text)
    html_text = LINK_RE.sub(lambda match: inline_or_remove_link(match, base_url), html_text)
    html_text = rewrite_links(html_text, route, output_dir, base_url)
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


def build_offline_docs(output_dir: Path, base_url: str) -> None:
    base_url = base_url.rstrip("/")
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    for route in ROUTES:
        source_url = f"{base_url}{route}/"
        destination = output_path_for_route(output_dir, route)
        destination.parent.mkdir(parents=True, exist_ok=True)
        print(f"[offline-docs] {source_url} -> {destination}")
        html_text = fetch_text(source_url)
        destination.write_text(rewrite_html(html_text, route, output_dir, base_url), encoding="utf-8")

    write_redirect_index(output_dir)
    (output_dir / "manifest.txt").write_text("\n".join(ROUTES) + "\n", encoding="utf-8")
    # Freshness stamp consumed by docs-refresh to decide whether the /usr
    # seed (image build) is newer than the /var mirror (runtime refresh
    # by margine-docs-refresh.service). Epoch seconds.
    (output_dir / "stamp").write_text(f"{int(time.time())}\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="https://margine.the-empty.place")
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    build_offline_docs(args.output_dir, args.base_url)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
