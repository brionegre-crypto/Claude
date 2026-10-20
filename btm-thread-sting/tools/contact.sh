#!/bin/bash
# usage: contact.sh video outdir  -> frames every 0.25 s (+ final) and 5x5 contact sheets with timestamps
v="$1"; d="$2"; mkdir -p "$d"; rm -f "$d"/q-*.png "$d"/sheet*.jpg
for i in $(seq 0 24); do
  t=$(python3 -c "print(min(${i}*0.25,5.9833))")
  ffmpeg -y -loglevel error -ss "$t" -i "$v" -frames:v 1 "$d/q-$(printf %02d $i).png"
done
# sheets: 3 rows x 3 cols of 640x360 w/ labels, 9 frames per sheet
for s in 0 1 2; do
  files=""; filt=""; n=0
  for k in $(seq 0 8); do
    i=$((s*9+k)); [ $i -gt 24 ] && break
    t=$(python3 -c "print(f'{${i}*0.25:.2f}s')")
    files="$files -i $d/q-$(printf %02d $i).png"
    filt="$filt[$n:v]scale=640:360,drawtext=text='$t':x=12:y=10:fontsize=26:fontcolor=0x000000:box=1:boxcolor=0xffffff99:boxborderw=6[v$n];"
    n=$((n+1))
  done
  ins=""; for k in $(seq 0 $((n-1))); do ins="$ins[v$k]"; done
  ffmpeg -y -loglevel error $files -filter_complex "${filt}${ins}xstack=inputs=$n:layout=0_0|640_0|1280_0|0_360|640_360|1280_360|0_720|640_720|1280_720[o]" -map "[o]" -frames:v 1 "$d/sheet$s.jpg"
done
echo done
