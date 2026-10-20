#!/bin/bash
# usage: qa-alpha.sh <transparent.mov|webm> <outdir>   composites 6 frames over a mid-blue and a light grey ground; checks alpha really is empty outside the logo
f="$1"; d="$2"; mkdir -p "$d"
echo "== format"; ffprobe -v error -show_entries stream=codec_type,codec_name,pix_fmt,width,height,r_frame_rate,nb_frames,duration:stream_tags=alpha_mode:format=duration -of compact "$f"
for t in 0.5 1.6 3.3 4.45 5.5; do
  for bg in 3b5870 d8d8d4; do
    ffmpeg -y -loglevel error -c:v libvpx-vp9 -ss $t -i "$f" -f lavfi -i "color=c=0x$bg:s=1920x1080" -filter_complex "[1:v][0:v]overlay=shortest=1,format=rgb24" -frames:v 1 "$d/a_${t}_$bg.png" 2>/dev/null || \
    ffmpeg -y -loglevel error -ss $t -i "$f" -f lavfi -i "color=c=0x$bg:s=1920x1080" -filter_complex "[1:v][0:v]overlay=shortest=1,format=rgb24" -frames:v 1 "$d/a_${t}_$bg.png"
  done
done
python3 - "$d" <<'PY'
import sys,glob
from PIL import Image
d=sys.argv[1]
names=['a_0.5','a_1.6','a_3.3','a_4.45','a_5.5']
W,H=640,360
sheet=Image.new('RGB',(W*5,H*2))
for i,n in enumerate(names):
    for j,bg in enumerate(['3b5870','d8d8d4']):
        sheet.paste(Image.open(f'{d}/{n}_{bg}.png').convert('RGB').resize((W,H),Image.LANCZOS),(i*W,j*H))
sheet.save(f'{d}/alpha-sheet.jpg',quality=88); print('wrote',f'{d}/alpha-sheet.jpg')
PY
