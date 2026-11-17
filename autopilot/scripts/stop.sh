#!/usr/bin/env bash
# Stop the service. Safe at any time: all state is in SQLite and in-flight publishes are reconciled on restart.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.socialautopilot.plist"
if [ -f "$PLIST" ]; then launchctl unload "$PLIST" 2>/dev/null; echo "stopped (launchd; restarts at next login unless you delete $PLIST)"; fi
if systemctl --user cat socialautopilot.service >/dev/null 2>&1; then systemctl --user stop socialautopilot.service; echo "stopped (systemd)"; fi
if [ -f "$ROOT/data/autopilot.pid" ]; then kill "$(cat "$ROOT/data/autopilot.pid")" 2>/dev/null && echo "stopped (pid)"; rm -f "$ROOT/data/autopilot.pid"; fi
