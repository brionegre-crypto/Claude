#!/usr/bin/env bash
# One-time install: virtualenv + free dependencies, then the interactive wizard.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PY="${PYTHON:-}"
for c in python3.13 python3.12 python3.11 python3; do
  if [ -z "$PY" ] && command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(sys.version_info < (3,11))'; then PY="$c"; fi
done
[ -n "$PY" ] || { echo "Python 3.11+ is required (macOS: brew install python@3.12)"; exit 1; }
echo "Using $PY"
[ -d .venv ] || "$PY" -m venv .venv
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt
chmod +x scripts/*.sh scripts/autopilot
# Free tools the tests and Reels need: ffmpeg (video) and cloudflared (Instagram image hand-off)
MISSING=""
command -v ffmpeg >/dev/null || MISSING="$MISSING ffmpeg"
command -v cloudflared >/dev/null || MISSING="$MISSING cloudflared"
if [ -n "$MISSING" ]; then
  if command -v brew >/dev/null; then echo "Installing$MISSING with Homebrew (free)…"; brew install $MISSING
  else echo "Please install:$MISSING (macOS: https://brew.sh then: brew install$MISSING)"; exit 1; fi
fi
.venv/bin/python -m autopilot init
echo
echo "Running the test suite (simulation only, nothing is published)…"
.venv/bin/python -m pytest -q tests || { echo "Tests failed — see output above"; exit 1; }
echo
if [ "${1:-}" != "--no-wizard" ]; then exec scripts/autopilot wizard; fi
