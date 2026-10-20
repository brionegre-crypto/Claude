#!/bin/bash
# usage: sheet.sh <out.jpg> <variant> <t1> <t2> ...   quick labelled contact sheet from standalone stills (3 columns)
out="$1"; v="$2"; shift 2
d="$(cd "$(dirname "$0")" && pwd)"; tmp=$(mktemp -d)
i=0; for t in "$@"; do echo "$t $(printf %02d $i)"; i=$((i+1)); done | xargs -P 3 -L 1 bash -c "$d/still.sh \$0 $tmp/f-\$1.png $v"
n=$#; files=""; filt=""; k=0
for t in "$@"; do
  files="$files -i $tmp/f-$(printf %02d $k).png"
  filt="$filt[$k:v]crop=1920:990:0:0,scale=640:330,drawtext=text='${t}s':x=10:y=8:fontsize=24:fontcolor=0x000000:box=1:boxcolor=0xffffffbb:boxborderw=5[v$k];"
  k=$((k+1))
done
rows=$(( (n+2)/3 )); lay=""; for j in $(seq 0 $((n-1))); do lay="$lay$(( (j%3)*640 ))_$(( (j/3)*330 ))|"; done; lay=${lay%|}
ins=""; for j in $(seq 0 $((n-1))); do ins="$ins[v$j]"; done
ffmpeg -y -loglevel error $files -filter_complex "${filt}${ins}xstack=inputs=$n:layout=$lay[o]" -map "[o]" -frames:v 1 -q:v 3 "$out"
rm -rf "$tmp"
