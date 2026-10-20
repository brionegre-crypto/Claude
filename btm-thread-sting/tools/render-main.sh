#!/bin/bash
# usage: render-main.sh <variant> <out.mp4>   delivery-quality opaque cut, exactly 6.000 s
set -e
v="${1:-orbit}"; out="${2:-renders/be-the-man-thread-sting.mp4}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
node tools/make-audio.mjs "$v" assets/btm-sfx.wav >/dev/null
npx --yes hyperframes@0.8.181 render -f 60 -q delivery --crf 5 -w 4 --variables "{\"variant\":\"$v\"}" -o renders/_tmp-$v.mp4 >/dev/null 2>&1
ffmpeg -y -loglevel error -i renders/_tmp-$v.mp4 -t 6 -c copy -movflags +faststart "$out"
rm -f renders/_tmp-$v.mp4
