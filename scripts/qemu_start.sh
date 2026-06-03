#!/usr/bin/env bash
# scripts/qemu_start.sh
# Starts the QNX QEMU VM in daemon mode.
# Reads config from CI environment variables (set in .gitlab-ci.yml).

set -euo pipefail

QEMU_BASE="$HOME/${QNX_SDP_PATH:-qnx800}/images/qemu/qemu"
OUT="$QEMU_BASE/output"
MAC="${QNX_MAC:-52:54:00:91:01:ea}"

echo "[qemu_start] Base: $QEMU_BASE"

# Clean up any leftover PID file from a crashed previous run
if [ -f "$OUT/qemu.pid" ]; then
    OLD_PID=$(cat "$OUT/qemu.pid")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[qemu_start] Killing stale QEMU PID $OLD_PID"
        kill "$OLD_PID" || true
        sleep 2
    fi
    rm -f "$OUT/qemu.pid"
fi

rm -f "$OUT/serial.log"

qemu-system-x86_64 \
    --enable-kvm \
    -drive  file="$OUT/disk-qemu.vmdk",if=ide,id=drv0 \
    -netdev bridge,br=virbr0,id=net0 \
    -device virtio-net-pci,netdev=net0,mac="$MAC" \
    -pidfile "$OUT/qemu.pid" \
    -display none \
    -kernel  "$OUT/ifs.bin" \
    -serial  file:"$OUT/serial.log" \
    -monitor none \
    -object  rng-random,filename=/dev/urandom,id=rng0 \
    -device  virtio-rng-pci,rng=rng0 \
    -smp 8 \
    -m 16G \
    -cpu host,host-phys-bits-limit=40 \
    -daemonize

echo "[qemu_start] QEMU started (PID $(cat "$OUT/qemu.pid"))"
