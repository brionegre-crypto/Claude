#!/usr/bin/env bash
# Start the worker + dashboard: via the installed service if present, else in the background with nohup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.socialautopilot.plist"
if [ -f "$PLIST" ]; then launchctl load -w "$PLIST" 2>/dev/null || true; launchctl start com.socialautopilot; echo "started (launchd)"; exit 0; fi
if systemctl --user cat socialautopilot.service >/dev/null 2>&1; then systemctl --user start socialautopilot.service; echo "started (systemd)"; exit 0; fi
mkdir -p "$ROOT/data/logs"
cd "$ROOT"
nohup .venv/bin/python -m autopilot run >> data/logs/service.out.log 2>&1 &
echo $! > data/autopilot.pid
echo "started (pid $(cat data/autopilot.pid)); dashboard http://127.0.0.1:8765"
