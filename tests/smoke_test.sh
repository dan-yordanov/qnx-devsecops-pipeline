#!/usr/bin/env bash
# tests/smoke_test.sh
# Fast sanity checks: binary runs, exits 0, output contains expected markers.
# Usage: smoke_test.sh <user> <ip> <pass> <remote_binary_path>

set -uo pipefail

QNX_USER="$1"
QNX_IP="$2"
QNX_PASS="$3"
BINARY="$4"

SSH="sshpass -p $QNX_PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $QNX_USER@$QNX_IP"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  ✓  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  ✗  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "╔══════════════════════════════════════╗"
echo "║         SMOKE TEST SUITE             ║"
echo "╚══════════════════════════════════════╝"

# ── T01: Binary is present and executable ──────────────────────────────────
echo ""
echo "T01 – Binary present on target"
if $SSH "test -f $BINARY" 2>/dev/null; then
    $SSH "chmod +x $BINARY"
    pass "Binary found at $BINARY"
else
    fail "Binary NOT found at $BINARY"
fi

# ── T02: Program exits with code 0 ─────────────────────────────────────────
echo ""
echo "T02 – Clean exit code"
RAW=$($SSH "$BINARY > /tmp/smoke_out.txt 2>&1; echo __EXIT__:\$?" 2>/dev/null || echo "__EXIT__:255")
EXIT_CODE=$(echo "$RAW" | grep '__EXIT__:' | cut -d: -f2 | tr -d '[:space:]')
if [ "$EXIT_CODE" = "0" ]; then
    pass "Exit code = 0"
else
    fail "Exit code = $EXIT_CODE (expected 0)"
fi

# ── Grab output for remaining checks ───────────────────────────────────────
OUTPUT=$($SSH "cat /tmp/smoke_out.txt" 2>/dev/null || echo "")
echo ""
echo "  ── program output ──"
echo "$OUTPUT" | sed 's/^/  | /'
echo "  ────────────────────"

# ── T03: CPU info line present ─────────────────────────────────────────────
echo ""
echo "T03 – CPU info line"
if echo "$OUTPUT" | grep -qi "cpu"; then
    pass "CPU info present"
else
    fail "CPU info missing"
fi

# ── T04: All 5 pulses reported ─────────────────────────────────────────────
echo ""
echo "T04 – Pulse output (5 lines)"
PULSE_LINES=$(echo "$OUTPUT" | grep -cE "Pulse [0-9]+" || true)
if [ "$PULSE_LINES" -eq 5 ]; then
    pass "5 pulse lines found"
else
    fail "Expected 5 pulse lines, got $PULSE_LINES"
fi

# ── T05: Program printed 'Done' ────────────────────────────────────────────
echo ""
echo "T05 – Completion marker 'Done'"
if echo "$OUTPUT" | grep -q "Done"; then
    pass "'Done' marker present"
else
    fail "'Done' marker missing"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  Smoke tests:  $PASS_COUNT passed  |  $FAIL_COUNT failed"
echo "══════════════════════════════════════════"

[ "$FAIL_COUNT" -eq 0 ] || exit 1
