#!/usr/bin/env bash
# scripts/qemu_stop.sh
# Gracefully terminates the QEMU VM started by qemu_start.sh.

set -uo pipefail

QEMU_BASE="$HOME/${QNX_SDP_PATH:-qnx800}/images/qemu/qemu"
PID_FILE="$QEMU_BASE/output/qemu.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "[qemu_stop] No PID file found – QEMU may already be stopped."
    exit 0
fi

PID=$(cat "$PID_FILE")

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    # Wait up to 10 s for clean exit
    for i in $(seq 1 10); do
        kill -0 "$PID" 2>/dev/null || { echo "[qemu_stop] QEMU PID $PID exited."; break; }
        sleep 1
    done
    # Force kill if still alive
    if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" || true
        echo "[qemu_stop] QEMU force-killed (SIGKILL)."
    fi
else
    echo "[qemu_stop] PID $PID not running (already dead)."
fi

rm -f "$PID_FILE"
