#!/bin/bash
# Renders every deliverable. Run from the project root.
set -e
R="npx hyperframes render -f 60 -q delivery --crf 10 -w 4"
trim() { ffmpeg -y -loglevel error -i "$1" -t 6 -c copy -movflags +faststart "$2"; rm "$1"; }
node tools/make-audio.mjs lasso assets/btm-sfx.wav
$R -o renders/_a.mp4 >/dev/null 2>&1 && trim renders/_a.mp4 renders/be-the-man-logo-sting.mp4
npx hyperframes render -f 60 -w 4 --format mov  --variables '{"transparent":true}' -o renders/_b.mov  >/dev/null 2>&1 && trim renders/_b.mov renders/be-the-man-logo-sting-transparent.mov
npx hyperframes render -f 60 -w 4 --format webm --variables '{"transparent":true}' -o renders/_c.webm >/dev/null 2>&1 && trim renders/_c.webm renders/be-the-man-logo-sting-transparent.webm
for v in horizon swirl; do
  d=$(tools/build-variant.sh $v | tail -1)
  (cd $d && $R -o /home/user/Claude/loop-logo/renders/_$v.mp4 >/dev/null 2>&1) && trim renders/_$v.mp4 renders/option-$v.mp4
done
ls -la renders
