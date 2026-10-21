#!/bin/bash
# usage: halfsec.sh <video.mp4> <outdir>   one frame every half second (0.0 .. 19.98), 12 per labelled sheet
v="$1"; d="$2"; mkdir -p "$d"; rm -f "$d"/h-*.png "$d"/sheet*.jpg
for i in $(seq 0 40); do
  t=$(python3 -c "print(min($i*0.5,19.9833))")
  ffmpeg -y -loglevel error -ss "$t" -i "$v" -frames:v 1 "$d/h-$(printf %02d $i).png"
done
for s in 0 1 2 3; do
  files=""; filt=""; n=0
  for k in $(seq 0 11); do
    i=$((s*12+k)); [ $i -gt 40 ] && break
    t=$(python3 -c "print(f'{$i*0.5:.1f}s')")
    files="$files -i $d/h-$(printf %02d $i).png"
    filt="$filt[$n:v]scale=640:360,drawtext=text='$t':x=10:y=8:fontsize=24:fontcolor=0x000000:box=1:boxcolor=0xffffffbb:boxborderw=5[v$n];"
    n=$((n+1))
  done
  lay=""; ins=""; for k in $(seq 0 $((n-1))); do lay="$lay$(( (k%3)*640 ))_$(( (k/3)*360 ))|"; ins="$ins[v$k]"; done; lay=${lay%|}
  ffmpeg -y -loglevel error $files -filter_complex "${filt}${ins}xstack=inputs=$n:layout=$lay[o]" -map "[o]" -frames:v 1 -q:v 3 "$d/sheet$s.jpg"
done
ls "$d"/sheet*.jpg
