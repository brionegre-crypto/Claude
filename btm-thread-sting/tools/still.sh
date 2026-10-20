#!/bin/bash
# usage: still.sh <t> <out.png> [variant] [transparent]   quick standalone still of the composition (chromium)
t="$1"; out="$2"; v="${3:-orbit}"; tr="${4:-0}"
d="$(cd "$(dirname "$0")/.." && pwd)"
/opt/pw-browsers/chromium-1194/chrome-linux/chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files --window-size=1920,1080 --virtual-time-budget=4000 \
  --screenshot="$out" "file://$d/index.html?still=$t&variant=$v&transparent=$tr" >/dev/null 2>&1
