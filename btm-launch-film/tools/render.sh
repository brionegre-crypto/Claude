#!/bin/bash
# usage: render.sh <out.mp4>
# Renders at 240 fps (the page offsets time so each group of 4 frames is centred on its 60 fps frame time), blends 4 -> 1 for real motion blur,
# and muxes the code-made sound.  1920x1080, 60 fps, exactly 20 s.
set -e
out="${1:-renders/be-the-man-launch-film.mp4}"
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
node tools/make-audio.mjs assets/film-audio.wav >/dev/null
rm -f renders/_f240.mp4
npx --yes hyperframes@0.8.181 render -f 240 -q delivery --crf 8 -w 4 -o renders/_f240.mp4 >/dev/null 2>&1
ffmpeg -y -loglevel error -i renders/_f240.mp4 -i assets/film-audio.wav \
  -filter_complex "[0:v]tmix=frames=4,select='eq(mod(n\,4)\,3)',setpts=N/(60*TB)[v]" -map "[v]" -map 1:a \
  -r 60 -c:v libx264 -crf 12 -preset slow -pix_fmt yuv420p -c:a aac -b:a 256k -t 20 -movflags +faststart "$out"
rm -f renders/_f240.mp4
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,nb_frames,duration -of compact "$out"
