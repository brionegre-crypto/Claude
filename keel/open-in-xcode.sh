#!/usr/bin/env bash
# Generates Keel.xcodeproj from project.yml and opens it in Xcode. Run on your Mac:
#   cd keel && ./open-in-xcode.sh            (optionally: ./open-in-xcode.sh YOURTEAMID)
set -euo pipefail
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null; then
  echo "Xcode isn't installed. Install Xcode 26 or newer from the Mac App Store, open it once, then re-run." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    echo "Installing XcodeGen…"
    brew install xcodegen
  else
    echo "XcodeGen is needed. Install Homebrew from https://brew.sh, then re-run this script." >&2
    exit 1
  fi
fi

# Optional: pass your Apple Developer Team ID (Xcode → Settings → Accounts, or developer.apple.com → Membership).
if [[ "${1:-}" != "" ]]; then
  sed -i '' "s/DEVELOPMENT_TEAM: \"[^\"]*\"/DEVELOPMENT_TEAM: \"$1\"/" project.yml
  echo "Team ID set to $1"
fi

xcodegen generate
open Keel.xcodeproj
echo "Opened Keel.xcodeproj. Pick your iPhone as the run destination and press ⌘R."
