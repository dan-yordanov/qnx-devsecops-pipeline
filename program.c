/*
 * program.c  –  QNX Neutrino periodic-pulse demo  (VULNERABLE version)
 *
 * ⚠️  THIS FILE IS INTENTIONALLY INSECURE.
 *     It exists solely to demonstrate that the SAST / Secret-Detection
 *     security gates in the CI pipeline catch real issues BEFORE merge.
 *
 * Vulnerabilities introduced:
 *   [V1]  CWE-798  Hardcoded credentials                → gitleaks (AWS key pattern)
 *   [V2]  CWE-120  gets() unbounded buffer read         → Flawfinder Level 5
 *   [V3]  CWE-120  strcpy() without bounds check        → Flawfinder Level 4
 *   [V4]  CWE-134  printf(user_input) format string     → Flawfinder Level 4
 *   [V5]  CWE-78   system() OS-command injection risk   → Flawfinder Level 4
 *   [V6]  CWE-190  Integer overflow, safety-critical    → cppcheck (warning)
 *   [V7]  CWE-415  Double-free                          → cppcheck (error)
 *   [V8]  CWE-788  Out-of-bounds write                  → cppcheck (error)
 *   [V9]  CWE-476  NULL pointer dereference             → cppcheck (error)
 *
 * NOTE: All cppcheck-targeted functions (V7–V9) are NEVER called at runtime.
 *       They exist in unreachable static functions so that:
 *         - static analysis tools detect them (severity="error")
 *         - the binary does NOT crash during smoke/integration tests
 *
 * DO NOT ship, deploy, or merge this file into production code.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/neutrino.h>
#include <sys/syspage.h>

/* ── [V1] CWE-798: Hardcoded credentials ──────────────────────────────────
 * AWS Access Key ID (AKIA...) triggers gitleaks rule "aws-access-key-id".
 * AWS Secret triggers gitleaks rule "aws-secret-access-key".             */
#define AWS_ACCESS_KEY_ID     "AKIAIOSFODNN7EXAMPLE"                       /* VIOLATION */
#define AWS_SECRET_ACCESS_KEY "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  /* VIOLATION */

#define PULSE_CODE_TIMER  _PULSE_CODE_MINAVAIL
#define TIMER_INTERVAL_MS 500
#define TICK_COUNT        5

/* ── [V2] CWE-120: gets() – Flawfinder Level 5 ────────────────────────── */
static void read_device_name(void)
{
    char name[32];
    printf("Device name: ");
    gets(name);              /* VIOLATION – no bounds check */
    printf("Name: %s\n", name);
}

/* ── [V3] CWE-120: strcpy without bounds – Flawfinder Level 4 ──────────── */
static void copy_config(const char *src)
{
    char dest[16];
    strcpy(dest, src);       /* VIOLATION – src may exceed 16 bytes */
}

/* ── [V4] CWE-134: uncontrolled format string – Flawfinder Level 4 ──────── */
static void log_event(const char *fmt)
{
    printf(fmt);             /* VIOLATION – attacker-controlled format */
}

/* ── [V6] CWE-190: integer overflow – cppcheck warning ──────────────────── */
static uint32_t frame_buffer_size(uint32_t width, uint32_t height)
{
    return width * height * 4; /* VIOLATION – no overflow guard */
}

/* ── [V7] CWE-415: Double-free – cppcheck error ─────────────────────────
 * NEVER called at runtime. Static analysis traverses this path.          */
static void vuln_double_free(void)
{
    char *buf = malloc(64);
    if (!buf) return;
    free(buf);
    free(buf);               /* VIOLATION – double-free */
}

/* ── [V8] CWE-788: Out-of-bounds write – cppcheck error ─────────────────
 * NEVER called at runtime.                                               */
static void vuln_oob_write(void)
{
    char small_buf[4];
    small_buf[10] = 'X';     /* VIOLATION – index 10 out of bounds [0..3] */
    (void)small_buf;
}

/* ── [V9] CWE-476: NULL pointer dereference – cppcheck error ────────────
 * NEVER called at runtime.                                               */
static void vuln_null_deref(void)
{
    char *ptr = NULL;
    *ptr = 'A';              /* VIOLATION – NULL dereference */
}

/* ── main ─────────────────────────────────────────────────────────────────── */

int main(void)
{
    /* Suppress unused-function warnings – these are NEVER called */
    (void)read_device_name;
    (void)copy_config;
    (void)log_event;
    (void)frame_buffer_size;
    (void)vuln_double_free;
    (void)vuln_oob_write;
    (void)vuln_null_deref;

    /* ── syspage: CPU count ─────────────────────────────────────────────── */
    unsigned num_cpu = _syspage_ptr->num_cpu;
    printf("QNX system page reports %u CPU(s)\n\n", num_cpu);

    /* ── [V5] CWE-78: system() with hardcoded secret in command ────────────
     * Flawfinder Level 4 on both sprintf and system().
     * system() return value is intentionally ignored (vulnerability demo).
     * If 'logger' is unavailable on the target the call fails silently.   */
    char cmd[128];
    sprintf(cmd, "echo 'QNX boot key=%s' > /dev/null", AWS_ACCESS_KEY_ID); /* VIOLATION */
    system(cmd);             /* VIOLATION – return value ignored */

    /* ── IPC channel ────────────────────────────────────────────────────── */
    int chid = ChannelCreate(0);
    if (chid == -1) { perror("ChannelCreate"); return EXIT_FAILURE; }

    int coid = ConnectAttach(0, 0, chid, _NTO_SIDE_CHANNEL, 0);
    if (coid == -1) { perror("ConnectAttach"); ChannelDestroy(chid); return EXIT_FAILURE; }

    /* ── Periodic SIGEV_PULSE timer ─────────────────────────────────────── */
    struct sigevent event;
    SIGEV_PULSE_INIT(&event, coid, SIGEV_PULSE_PRIO_INHERIT, PULSE_CODE_TIMER, 0);

    timer_t timer_id;
    if (timer_create(CLOCK_MONOTONIC, &event, &timer_id) == -1) {
        perror("timer_create");
        ConnectDetach(coid);
        ChannelDestroy(chid);
        return EXIT_FAILURE;
    }

    struct itimerspec its = {
        .it_value    = { .tv_sec = 0, .tv_nsec = (long)TIMER_INTERVAL_MS * 1000000L },
        .it_interval = { .tv_sec = 0, .tv_nsec = (long)TIMER_INTERVAL_MS * 1000000L },
    };
    if (timer_settime(timer_id, 0, &its, NULL) == -1) {
        perror("timer_settime");
        timer_delete(timer_id);
        ConnectDetach(coid);
        ChannelDestroy(chid);
        return EXIT_FAILURE;
    }

    printf("Firing pulse every %d ms, %d times...\n", TIMER_INTERVAL_MS, TICK_COUNT);

    /* ── Receive loop ────────────────────────────────────────────────────── */
    for (int i = 0; i < TICK_COUNT; i++) {
        struct _pulse pulse;
        if (MsgReceivePulse(chid, &pulse, sizeof(pulse), NULL) == -1) {
            perror("MsgReceivePulse");
            break;
        }
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        printf("  Pulse %d at %ld.%03lds (code=%d)\n",
               i + 1, now.tv_sec, now.tv_nsec / 1000000L, pulse.code);
    }

    /* ── Cleanup ─────────────────────────────────────────────────────────── */
    timer_delete(timer_id);
    ConnectDetach(coid);
    ChannelDestroy(chid);

    printf("\nDone.\n");
    return EXIT_SUCCESS;
}