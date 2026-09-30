#!/usr/bin/env bash
# Re-renders the org profile banners from banner.html.
#
# banner.html is self-contained: the official wordmark and S-chevron are inline
# SVG paths (copied from Stealth_Labs_Design_System/brand/) and the Archivo and
# JetBrains Mono subsets are embedded, so renders are offline and repeatable.
# GitHub strips webfonts from SVGs in READMEs, which is why we ship PNGs.
#
# To change the copy, edit the query strings below; '|' breaks the headline.
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

members="h1=Every%20person%7Cships%20code.&k=Members%20%2F%20Start%20here&fs=80"

shot 1280,440 banner-dark.png   "theme=dark"
shot 1280,440 banner-light.png  "theme=light"
shot 1280,440 members-dark.png  "theme=dark&$members"
shot 1280,440 members-light.png "theme=light&$members"
shot 1280,640 social-card.png   "theme=dark&card=1"

echo "Rendered to $out"
