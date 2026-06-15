#!/usr/bin/env bash
# Validate that every Flathub app ID our ujust recipes install still resolves
# on Flathub.
#
# Why this exists: the AI layer (`ujust margine-ai` -> Alpaca) and the gaming
# layer are pure-Flatpak, so there's no rpm depsolve to dry-run the way
# gaming-native-packages.txt is validated. The equivalent rot for a Flatpak
# layer is an app being renamed or delisted upstream — which makes the recipe's
# `flatpak install` fail at runtime, with nothing in CI to catch it. This
# scans the recipes for the app IDs they install and checks each against the
# Flathub API.
#
#   usage: validate-flatpak-refs.sh [recipe-file ...]   (default: 60-custom.just)
set -euo pipefail

FILES=("$@")
if [ "${#FILES[@]}" -eq 0 ]; then
  FILES=("build_files/60-custom.just")
fi

API="https://flathub.org/api/v2/appstream"

mapfile -t IDS < <(
  python3 - "${FILES[@]}" <<'PY'
import re, sys

ids = set()
# Reverse-DNS app ID: 3+ dot-separated segments (e.g. com.jeffser.Alpaca,
# com.github.Matoking.protontricks).
appid = re.compile(r"^[A-Za-z][\w-]*(?:\.[A-Za-z0-9][\w-]*){2,}$")
SKIP = {"flatpak", "install", "flathub", "uninstall", "run", "--system", "--user"}

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    # Join shell line-continuations so a multi-line `flatpak install ... \`
    # block collapses to one logical line we can tokenise.
    text = re.sub(r"\\\n", " ", text)
    for line in text.splitlines():
        if "flatpak install" not in line:
            continue
        for tok in line.split():
            if tok.startswith("-") or tok in SKIP:
                continue
            if appid.match(tok):
                ids.add(tok)

for i in sorted(ids):
    print(i)
PY
)

if [ "${#IDS[@]}" -eq 0 ]; then
  echo "::warning::no Flatpak app IDs found in ${FILES[*]} — the parser may need updating"
  exit 0
fi

echo "Validating ${#IDS[@]} Flatpak ref(s) against Flathub:"
fail=0
for id in "${IDS[@]}"; do
  code="$(curl -fsS -o /dev/null -w '%{http_code}' --retry 3 --retry-delay 2 \
    "$API/$id" 2>/dev/null || echo 000)"
  if [ "$code" = "200" ]; then
    echo "  ok   $id"
  else
    echo "  MISS $id  (Flathub returned $code)"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "::error::one or more Flatpak refs no longer resolve on Flathub — a ujust recipe would fail at install time. Update the recipe (renamed/delisted app)."
  exit 1
fi
echo "All Flatpak refs resolve on Flathub."
