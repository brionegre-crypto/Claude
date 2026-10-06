#!/bin/bash
# Puts the Be The Man 12-week social media packs into your
# "Be The Man System" folder on the Desktop.
#
# Before running: download all the pack-XX_….zip files (and, optionally,
# POSTING-GUIDE.md, calendar.csv and Be-The-Man-content-calendar.ics) into Downloads.
# Run it in Terminal:  bash ~/Downloads/install-social-posts.command
set -euo pipefail
shopt -s nullglob nocaseglob

DL="$HOME/Downloads"

# Find the "Be The Man System" folder on the Desktop (any capitalization).
TARGET=""
for d in "$HOME/Desktop"/*/; do
  name="$(basename "$d")"
  if [ "$(echo "$name" | tr '[:upper:]' '[:lower:]')" = "be the man system" ]; then TARGET="${d%/}"; fi
done
if [ -z "$TARGET" ]; then
  echo "Couldn't find a folder named \"Be The Man System\" on your Desktop."
  echo "Check the name, then run this again."
  exit 1
fi

DEST="$TARGET/Social Media - Oct to Dec 2026"
mkdir -p "$DEST"

# Packs can be .zip files, or folders if Safari unzipped them automatically.
packs=("$DL"/pack-*.zip)
for d in "$DL"/pack-*/; do packs+=("${d%/}"); done
if [ ${#packs[@]} -eq 0 ]; then
  echo "No pack-XX files or folders found in $DL. Download them first, then run this again."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
count=0
for z in "${packs[@]}"; do
  base="$(basename "$z" .zip)"
  base="${base% (*)}"                          # "pack-02 (1)" -> "pack-02"
  pack="${base%_part*}"                       # part1/part2 go into the same folder
  part=""; [[ "$base" == *_part* ]] && part="-${base##*_}"
  pretty="$(echo "$pack" | sed -E 's/^pack-([0-9]+)_([0-9-]+)_to_([0-9-]+)$/Pack \1 (\2 to \3)/')"
  mkdir -p "$DEST/$pretty"
  rm -rf "$TMP/x"; mkdir -p "$TMP/x"
  if [ -d "$z" ]; then cp -R "$z"/. "$TMP/x/"; else unzip -q "$z" -d "$TMP/x"; fi
  [ -f "$TMP/x/POSTING-GUIDE.md" ] && mv "$TMP/x/POSTING-GUIDE.md" "$DEST/$pretty/POSTING-GUIDE$part.md"
  for f in "$TMP/x"/*/; do
    rm -rf "$DEST/$pretty/$(basename "$f")"
    mv "$f" "$DEST/$pretty/"
    count=$((count+1))
  done
  echo "✓ $pretty"
done

for extra in POSTING-GUIDE.md calendar.csv Be-The-Man-content-calendar.ics COMPUTER-CLAUDE-PROMPT.md; do
  [ -f "$DL/$extra" ] && cp "$DL/$extra" "$DEST/" && echo "✓ $extra"
done

echo
echo "Done: $count post folders are in"
echo "  $DEST"
open "$DEST"
