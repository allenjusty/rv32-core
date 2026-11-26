/* CoreMark port for the RV32IM core.
   Timing reads mcycle and minstret around the timed region, so the bench can report the
   CPI of exactly that region. Output goes through a memory-mapped character address
   that the simulation harness prints (PRINT_ADDR). */
#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

#define CLOCK_HZ 100000000u    /* nominal 100 MHz: only used to print "seconds" */

#ifdef NO_COUNTERS
/* Spike-compare build: counter values never match Spike (it also counts its boot ROM),
   and CoreMark stores them to memory, so this build does not read them. */
static inline ee_u32 rd_mcycle(void)   { return 0; }
static inline ee_u32 rd_minstret(void) { return 1; }
#else
static inline ee_u32 rd_mcycle(void)   { ee_u32 v; __asm__ volatile("csrr %0, mcycle"   : "=r"(v)); return v; }
static inline ee_u32 rd_minstret(void) { ee_u32 v; __asm__ volatile("csrr %0, minstret" : "=r"(v)); return v; }
#endif

static ee_u32 start_cycles, stop_cycles, start_instret, stop_instret;

void start_time(void) { start_instret = rd_minstret(); start_cycles = rd_mcycle(); }
void stop_time(void)  { stop_cycles = rd_mcycle(); stop_instret = rd_minstret(); }
CORE_TICKS get_time(void) { return stop_cycles - start_cycles; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks / CLOCK_HZ; }

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    ee_u32 cyc = stop_cycles - start_cycles, ins = stop_instret - start_instret;
    /* CPI with 3 decimals, integer math only */
    ee_u32 milli = (ee_u32)(((unsigned long long)cyc * 1000u) / ins);
    ee_printf("Timed region: %u cycles, %u instructions, CPI %u.%03u\n", cyc, ins, milli / 1000, milli % 1000);
    p->portable_id = 0;
}
