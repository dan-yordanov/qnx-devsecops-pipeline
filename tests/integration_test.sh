#!/usr/bin/env bash
# tests/integration_test.sh
# Deeper behavioural checks: timing accuracy, pulse count, IPC codes.
# Generates JUnit XML for GitLab test report widget.
# Usage: integration_test.sh <user> <ip> <pass> <remote_binary_path>

set -uo pipefail

QNX_USER="$1"
QNX_IP="$2"
QNX_PASS="$3"
BINARY="$4"

SSH="sshpass -p $QNX_PASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $QNX_USER@$QNX_IP"

mkdir -p test-results

PASS_COUNT=0
FAIL_COUNT=0
declare -A T_RESULT T_MSG

# ── helpers ───────────────────────────────────────────────────────────────

record_pass() {
    local id="$1" name="$2"
    T_RESULT[$id]="pass"
    T_MSG[$id]="$name"
    echo "  ✓  [$id] $name"
    PASS_COUNT=$((PASS_COUNT + 1))
}

record_fail() {
    local id="$1" name="$2" reason="$3"
    T_RESULT[$id]="fail"
    T_MSG[$id]="$name: $reason"
    echo "  ✗  [$id] $name → $reason"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "╔══════════════════════════════════════════╗"
echo "║       INTEGRATION TEST SUITE             ║"
echo "╚══════════════════════════════════════════╝"

# ── Run program once, capture output and wall-clock time ─────────────────
echo ""
echo "Running binary on QNX target …"
chmod +x "$BINARY" 2>/dev/null || true

T_START=$(date +%s)
$SSH "chmod +x $BINARY && $BINARY > /tmp/int_out.txt 2>&1" || true
T_END=$(date +%s)
ELAPSED=$((T_END - T_START))

OUTPUT=$($SSH "cat /tmp/int_out.txt" 2>/dev/null || echo "")
echo ""
echo "  ── program output ──"
echo "$OUTPUT" | sed 's/^/  | /'
echo "  ── elapsed: ${ELAPSED}s ──"
echo ""

# ── T01: Pulse count ─────────────────────────────────────────────────────
INTERVAL_MS=$(echo "$OUTPUT" | grep -oE 'at [0-9]+\.[0-9]+' \
  | awk '{print $2}' \
  | awk 'NR>1{diff=($1-prev)*1000; print int(diff+0.5)} {prev=$1}' \
  | awk '{sum+=$1; n++} END{if(n>0) print int(sum/n); else print 0}')
if [ "${INTERVAL_MS:-0}" -ge 450 ] && [ "${INTERVAL_MS:-0}" -le 550 ]; then
    record_pass "T01" "Average pulse interval ~500ms (got ${INTERVAL_MS}ms)"
else
    record_fail "T01" "Average pulse interval ~500ms" "got ${INTERVAL_MS}ms"
fi

# ── T02: Timing window (5 × 500 ms ≈ 2.5 s; allow 2–12 s for boot lag) ──
if [ "$ELAPSED" -ge 2 ] && [ "$ELAPSED" -le 12 ]; then
    record_pass "T02" "Elapsed time in [2s, 12s] window"
else
    record_fail "T02" "Elapsed time in [2s, 12s] window" "elapsed=${ELAPSED}s"
fi

# ── T03: Pulse code == 0 (_PULSE_CODE_MINAVAIL) ──────────────────────────
PULSE_CODE=$(echo "$OUTPUT" | grep -oE 'code=[0-9]+' | head -1 | cut -d= -f2 || echo "")
if [ "${PULSE_CODE:-x}" = "0" ]; then
    record_pass "T03" "Pulse code = 0 (_PULSE_CODE_MINAVAIL)"
else
    record_fail "T03" "Pulse code = 0 (_PULSE_CODE_MINAVAIL)" "got code='$PULSE_CODE'"
fi

# ── T04: CPU count > 0 ────────────────────────────────────────────────────
CPU_COUNT=$(echo "$OUTPUT" | grep -oE '[0-9]+ CPU' | grep -oE '[0-9]+' || echo "0")
if [ "${CPU_COUNT:-0}" -gt 0 ]; then
    record_pass "T04" "CPU count > 0 (syspage readable)"
else
    record_fail "T04" "CPU count > 0 (syspage readable)" "got '$CPU_COUNT'"
fi

# ── T05: No error/failure keywords in output ─────────────────────────────
if ! echo "$OUTPUT" | grep -qiE '\b(error|fail|errno|assert|abort)\b'; then
    record_pass "T05" "No error keywords in output"
else
    ERRORS=$(echo "$OUTPUT" | grep -iE '\b(error|fail|errno|assert|abort)\b')
    record_fail "T05" "No error keywords in output" "$ERRORS"
fi

# ── T06: Pulse timestamps are monotonically increasing ───────────────────
TIMES=$(echo "$OUTPUT" | grep -oE 'at [0-9]+\.[0-9]+' | awk '{print $2}')
PREV=""
MONO_OK=1
while IFS= read -r ts; do
    if [ -n "$PREV" ]; then
        # Compare as integers by stripping the dot
        A=$(echo "$PREV" | tr -d '.')
        B=$(echo "$ts"   | tr -d '.')
        if [ "$B" -le "$A" ]; then MONO_OK=0; break; fi
    fi
    PREV="$ts"
done <<< "$TIMES"

if [ "$MONO_OK" -eq 1 ] && [ -n "$PREV" ]; then
    record_pass "T06" "Timestamps monotonically increasing"
else
    record_fail "T06" "Timestamps monotonically increasing" "non-monotonic timestamps detected"
fi

# ── T07: 'Done' completion marker ────────────────────────────────────────
if echo "$OUTPUT" | grep -q "Done"; then
    record_pass "T07" "Completion marker 'Done' present"
else
    record_fail "T07" "Completion marker 'Done' present" "not found"
fi

# ── Write JUnit XML ───────────────────────────────────────────────────────
XML_FILE="test-results/integration.xml"
{
printf '<?xml version="1.0" encoding="UTF-8"?>\n'
printf '<testsuites>\n'
printf '  <testsuite name="QNX Integration Tests" tests="%d" failures="%d" time="%d">\n' \
       $((PASS_COUNT + FAIL_COUNT)) "$FAIL_COUNT" "$ELAPSED"

for id in T01 T02 T03 T04 T05 T06 T07; do
    name="${T_MSG[$id]:-$id}"
    if [ "${T_RESULT[$id]:-fail}" = "pass" ]; then
        printf '    <testcase classname="qnx.integration" name="%s"/>\n' "$name"
    else
        printf '    <testcase classname="qnx.integration" name="%s">\n' "$id"
        printf '      <failure message="%s"/>\n' "$name"
        printf '    </testcase>\n'
    fi
done

printf '  </testsuite>\n'
printf '</testsuites>\n'
} > "$XML_FILE"

echo ""
echo "JUnit XML → $XML_FILE"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  Integration tests:  $PASS_COUNT passed  |  $FAIL_COUNT failed"
echo "══════════════════════════════════════════════"

[ "$FAIL_COUNT" -eq 0 ] || exit 1
