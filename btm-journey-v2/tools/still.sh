#!/bin/bash
# usage: still.sh <t> <out.png>   quick standalone still of the composition (chromium)
t="$1"; out="$2"; d="$(cd "$(dirname "$0")/.." && pwd)"
/opt/pw-browsers/chromium-1194/chrome-linux/chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files --window-size=1920,1180 --virtual-time-budget=5000 \
  --screenshot="$out" "file://$d/index.html?still=$t" >/dev/null 2>&1
