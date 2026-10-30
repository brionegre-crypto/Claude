#!/bin/bash
# usage: render.sh <out.mp4>   (60 fps straight render; the page sets its own frame times; voice + music muxed from code-made audio)
set -e
out="${1:-renders/be-the-man-journey.mp4}"
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"


dur=$(node -e "console.log(Math.ceil(require('./script.js').DUR*60)/60)")
sed -i "s/data-duration=\"[0-9.]*\"/data-duration=\"$dur\"/" index.html
rm -f renders/_v.mp4
npx --yes hyperframes@0.8.181 render -f 60 -q delivery --crf 10 -w 4 -o renders/_v.mp4 >/dev/null 2>&1
ffmpeg -y -loglevel error -i renders/_v.mp4 -i assets/walkthrough-audio.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -t "$dur" -movflags +faststart "$out"
rm -f renders/_v.mp4
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,nb_frames,duration -of compact "$out"
