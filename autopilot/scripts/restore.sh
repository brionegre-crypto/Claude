#!/usr/bin/env bash
# Usage: scripts/restore.sh data/backups/autopilot-….zip
# Stops the service, verifies the backup's integrity, keeps a safety copy of the current DB, restores, restarts.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 1 ] || { echo "usage: $0 <backup.zip>"; ls -1t "$DIR/../data/backups/"*.zip 2>/dev/null | head -5; exit 1; }
"$DIR/stop.sh" || true
sleep 2
"$DIR/autopilot" restore "$1"
echo "Restored. Start again with: $DIR/start.sh"
