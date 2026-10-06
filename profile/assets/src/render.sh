#!/usr/bin/env bash
# Re-renders the org profile banners from banner.html.
#
# banner.html is self-contained: the official wordmark and S-chevron are inline
# SVG paths (copied from Stealth_Labs_Design_System/brand/) and the Archivo and
# JetBrains Mono subsets are embedded, so renders are offline and repeatable.
# GitHub strips webfonts from SVGs in READMEs, which is why we ship PNGs.
#
# To change the copy, edit the query strings below: k= sets the kicker, h1= the
# headline ('|' breaks a line), big=1 swaps the headline for an oversized wordmark.
#
# Usage: profile/assets/src/render.sh   (needs Google Chrome)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(cd "$here/.." && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

shot() { # <width,height> <output.png> <query string>
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size="$1" --virtual-time-budget=8000 \
    --screenshot="$out/$2" "file://$here/banner.html?$3" >/dev/null 2>&1
}

members="k=Members%20%2F%20Start%20here"

# Org page banners lead with the wordmark (big=1); the social card keeps the headline
shot 1280,440 banner-dark.png   "theme=dark&big=1"
shot 1280,440 banner-light.png  "theme=light&big=1"
shot 1280,440 members-dark.png  "theme=dark&big=1&$members"
shot 1280,440 members-light.png "theme=light&big=1&$members"
shot 1280,640 social-card.png   "theme=dark&card=1"

# Banner for this repo's own README
repo="k=Shared%20CI%2FCD%20%2F%20Org%20defaults"
shot 1280,440 repo-dark.png     "theme=dark&big=1&$repo"
shot 1280,440 repo-light.png    "theme=light&big=1&$repo"

echo "Rendered to $out"
