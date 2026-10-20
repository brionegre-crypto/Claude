#!/bin/bash
# usage: render-transparent.sh <variant> <out-base>   -> <out-base>.mov (ProRes 4444 + alpha) and <out-base>.webm (VP9 + alpha), 6.000 s, with sound
set -e
v="${1:-orbit}"; base="${2:-renders/be-the-man-thread-sting-transparent}"
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
node tools/make-audio.mjs "$v" assets/btm-sfx.wav >/dev/null
npx --yes hyperframes@0.8.181 render -f 60 -w 4 --format mov  --variables "{\"variant\":\"$v\",\"transparent\":true}" -o renders/_tm-$v.mov  >/dev/null 2>&1
ffmpeg -y -loglevel error -i renders/_tm-$v.mov -t 6 -c copy "$base.mov"; rm -f renders/_tm-$v.mov
npx --yes hyperframes@0.8.181 render -f 60 -w 4 --format webm --variables "{\"variant\":\"$v\",\"transparent\":true}" -o renders/_tw-$v.webm >/dev/null 2>&1
ffmpeg -y -loglevel error -i renders/_tw-$v.webm -t 6 -c copy "$base.webm"; rm -f renders/_tw-$v.webm
