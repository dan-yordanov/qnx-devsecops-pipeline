#!/usr/bin/env bash
# scripts/wait_for_ssh.sh
# Polls libvirt DHCP leases until the QNX target acquires an IP,
# then waits for SSH to be responsive.
# Prints the IP to stdout on success (all debug goes to stderr).
# Exit 1 on timeout.

set -euo pipefail

MAC="${QNX_MAC:-52:54:00:91:01:ea}"
QNX_USER="${QNX_USER:-qnxuser}"
QNX_PASS="${QNX_PASS:-qnxuser}"
MAX_ATTEMPTS=40       # 40 × 5 s = 200 s max
WAIT_INTERVAL=5

echo "[wait_for_ssh] Waiting for QNX target (MAC $MAC) …" >&2

for i in $(seq 1 "$MAX_ATTEMPTS"); do
    # Grab IP from libvirt DHCP lease table
    IP=$(virsh net-dhcp-leases default 2>/dev/null \
         | awk -v mac="$MAC" '$3 == mac { print $5 }' \
         | cut -d/ -f1 \
         | tail -1)

    if [ -n "$IP" ]; then
        # Try SSH handshake
        if sshpass -p "$QNX_PASS" \
               ssh -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o ConnectTimeout=5 \
                   -o BatchMode=no \
                   -o LogLevel=ERROR \
                   "$QNX_USER@$IP" "echo ok" 2>/dev/null | grep -q "ok"; then
            echo "[wait_for_ssh] Target ready at $IP (attempt $i)" >&2
            echo "$IP"   # ← captured by $() in the CI job
            exit 0
        else
            echo "[wait_for_ssh] $IP found but SSH not yet ready (attempt $i)" >&2
        fi
    else
        echo "[wait_for_ssh] No DHCP lease yet (attempt $i/$MAX_ATTEMPTS)" >&2
    fi

    sleep "$WAIT_INTERVAL"
done

echo "[wait_for_ssh] ERROR: QNX target not reachable after $((MAX_ATTEMPTS * WAIT_INTERVAL))s" >&2
echo "[wait_for_ssh] --- serial.log tail ---" >&2
tail -20 "$HOME/${QNX_SDP_PATH:-qnx800}/images/qemu/qemu" >&2 || true
exit 1
