#!/bin/bash
# Renders every deliverable into renders/. Run from anywhere.
set -e
cd "$(dirname "$0")/.."
tools/render-main.sh orbit renders/be-the-man-thread-sting.mp4
tools/render-transparent.sh orbit renders/be-the-man-thread-sting-transparent
tools/render-main.sh wrap renders/option-wrap.mp4
tools/render-main.sh gantry renders/option-gantry.mp4
node tools/make-audio.mjs orbit assets/btm-sfx.wav >/dev/null   # leave the project on the main cut's sound
ls -la renders
