#!/bin/bash
# usage: qa.sh <main.mp4> <outdir>
# Mechanical checks behind the critique rounds: format, sound present, last second still, exact centre, click frame.
v="$1"; d="$2"; mkdir -p "$d"
echo "== format"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,nb_frames,duration,sample_rate,channels -of compact "$v"
echo "== audio present: $(ffmpeg -hide_banner -i "$v" -map 0:a:0 -af volumedetect -f null - 2>&1 | grep -E 'mean_volume|max_volume' | tr '\n' ' ')"
echo "== last second still (max luma change between neighbouring frames, 5.0-6.0 s; encoder noise <=2 is invisible)"
ffmpeg -hide_banner -ss 5.0 -t 1 -i "$v" -vf "tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YMAX:file=-" -f null - 2>/dev/null | grep YMAX | awk -F= '{if($2>m)m=$2} END{print "max",m}'
echo "== contact sheets (every 0.25 s)"
"$(dirname "$0")/contact.sh" "$v" "$d" >/dev/null && ls "$d"/sheet*.jpg
ffmpeg -y -loglevel error -ss 5.95 -i "$v" -frames:v 1 "$d/final.png"
python3 - "$d/final.png" <<'EOF'
import sys
from PIL import Image
import numpy as np
im=np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int); m=im.max(axis=2)>90
sub=m[400:660,:]; ys,xs=np.where(sub); ys=ys+400
print('== centring: wordmark+full stop bbox centre = (%.1f, %.1f)  [frame centre 960, 540]'%((xs.min()+xs.max()+1)/2,(ys.min()+ys.max()+1)/2))
sub=m[660:900,:]; ys,xs=np.where(sub); print('   tagline centre x = %.1f'%((xs.min()+xs.max()+1)/2))
EOF
echo "== sound landing"
timeout 120 npx --yes hyperframes@0.8.181 audio "$v" --only onsets,moments,loudness --quality fast 2>&1 | head -6
