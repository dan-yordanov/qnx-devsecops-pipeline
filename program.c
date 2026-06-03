/*
 * program.c  –  QNX Neutrino periodic-pulse demo  (SAFE version)
 *
 * Demonstrates:
 *   - _syspage_ptr  for CPU discovery
 *   - ChannelCreate / ConnectAttach / MsgReceivePulse  (IPC)
 *   - CLOCK_MONOTONIC timer firing SIGEV_PULSE at 500 ms
 *
 * Compile (cross):
 *   qcc -Vgcc_ntox86_64 -Wall -Wextra -fPIC -g -O0 -fno-builtin \
 *       -o build/program program.c
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/neutrino.h>
#include <sys/syspage.h>

#define PROGRAM_VERSION   "1.0.0"
#define PULSE_CODE_TIMER  _PULSE_CODE_MINAVAIL   /* = 0 */
#define TIMER_INTERVAL_MS 500
#define TICK_COUNT        5

/* ── helpers ──────────────────────────────────────────────────────────────── */

static void print_banner(void)
{
    printf("=== QNX Pulse Timer Demo v%s ===\n", PROGRAM_VERSION);
    printf("Interval : %d ms  |  Ticks : %d\n\n",
           TIMER_INTERVAL_MS, TICK_COUNT);
}

/* Safe string copy – always NUL-terminates, returns 0 on truncation */
static int safe_strncpy(char *dst, const char *src, size_t dstsz)
{
    if (!dst || !src || dstsz == 0) return -1;
    strncpy(dst, src, dstsz - 1);
    dst[dstsz - 1] = '\0';
    return (strlen(src) < dstsz) ? 0 : -1;   /* -1 = truncated */
}

/* ── main ─────────────────────────────────────────────────────────────────── */

int main(void)
{
    print_banner();

    /* ── 1. syspage: CPU count ─────────────────────────────────────────── */
    unsigned num_cpu = _syspage_ptr->num_cpu;
    printf("QNX system page reports %u CPU(s)\n\n", num_cpu);

    /* ── 2. IPC channel ────────────────────────────────────────────────── */
    int chid = ChannelCreate(0);
    if (chid == -1) {
        perror("ChannelCreate");
        return EXIT_FAILURE;
    }

    int coid = ConnectAttach(0, 0, chid, _NTO_SIDE_CHANNEL, 0);
    if (coid == -1) {
        perror("ConnectAttach");
        ChannelDestroy(chid);
        return EXIT_FAILURE;
    }

    /* ── 3. Periodic SIGEV_PULSE timer ─────────────────────────────────── */
    struct sigevent event;
    SIGEV_PULSE_INIT(&event, coid,
                     SIGEV_PULSE_PRIO_INHERIT, PULSE_CODE_TIMER, 0);

    timer_t timer_id;
    if (timer_create(CLOCK_MONOTONIC, &event, &timer_id) == -1) {
        perror("timer_create");
        ConnectDetach(coid);
        ChannelDestroy(chid);
        return EXIT_FAILURE;
    }

    struct itimerspec its = {
        .it_value    = { .tv_sec = 0,
                         .tv_nsec = (long)TIMER_INTERVAL_MS * 1000000L },
        .it_interval = { .tv_sec = 0,
                         .tv_nsec = (long)TIMER_INTERVAL_MS * 1000000L },
    };

    if (timer_settime(timer_id, 0, &its, NULL) == -1) {
        perror("timer_settime");
        timer_delete(timer_id);
        ConnectDetach(coid);
        ChannelDestroy(chid);
        return EXIT_FAILURE;
    }

    printf("Firing pulse every %d ms, %d times...\n",
           TIMER_INTERVAL_MS, TICK_COUNT);

    /* ── 4. Receive loop ────────────────────────────────────────────────── */
    char label[32];
    for (int i = 0; i < TICK_COUNT; i++) {
        struct _pulse pulse;
        if (MsgReceivePulse(chid, &pulse, sizeof(pulse), NULL) == -1) {
            perror("MsgReceivePulse");
            break;
        }

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);

        /* safe_strncpy: no unbounded copy */
        if (safe_strncpy(label, "TIMER", sizeof(label)) != 0)
            label[0] = '\0';

        printf("  Pulse %d [%s] at %ld.%03lds  (code=%d)\n",
               i + 1,
               label,
               now.tv_sec,
               now.tv_nsec / 1000000L,
               pulse.code);
    }

    /* ── 5. Cleanup ─────────────────────────────────────────────────────── */
    timer_delete(timer_id);
    ConnectDetach(coid);
    ChannelDestroy(chid);

    printf("\nDone.\n");
    return EXIT_SUCCESS;
}
