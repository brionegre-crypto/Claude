#!/bin/bash
# usage: build-variant.sh <lasso|horizon|swirl>   -> /tmp/claude-0/proj-<variant> ready to render
v="$1"; src="$(cd "$(dirname "$0")/.." && pwd)"; dst="/tmp/claude-0/proj-$v"
rm -rf "$dst"; mkdir -p "$dst"
cp -r "$src"/{index.html,motion.js,fonts,vendor,hyperframes.json,meta.json,package.json,assets} "$dst"/ 2>/dev/null
sed -i "s/\"default\":\"lasso\"/\"default\":\"$v\"/" "$dst/index.html"
node "$src/tools/make-audio.mjs" "$v" "$dst/assets/btm-sfx.wav"
echo "$dst"
