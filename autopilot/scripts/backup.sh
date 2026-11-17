#!/usr/bin/env bash
# Usage: scripts/backup.sh [--assets]   → data/backups/autopilot-YYYYmmdd-HHMMSS.zip
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/autopilot" backup "$@"
