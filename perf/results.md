# CPI result: BHT off vs on

CoreMark (PERFORMANCE_RUN, same binary for both), zero memory wait states, plain SystemVerilog harness on Verilator. This is a CPI measurement, not an official CoreMark score (CoreMark's 10-second rule for a valid score is not met in simulation; its CRC self-checks pass).

| | BHT off (predict not taken) | BHT on (64 x 2-bit) |
|---|---|---|
| CPI, timed region (mcycle / minstret) | 1.310 | 1.233 |
| Cycles, timed region | 7,548,562 | 7,107,240 |
| Instructions, timed region | 5,761,343 | 5,761,343 |
| Conditional branches (whole run) | 1,067,027 | 1,067,027 |
| Branch mispredicts (whole run) | 590,112 | 97,158 |
| Mispredict rate | 55.3% | 9.1% |
| JAL / JALR (whole run) | 111,585 / 43,064 | 111,585 / 43,064 |
| CoreMark CRC self-check | passed | passed |

**CPI improves by 5.9%** with the BHT.

Why the gain is modest: a correctly predicted taken branch still costs 1 bubble with the BHT,
because the target is only known in ID (no branch target buffer). Without the BHT a taken
branch costs 2 bubbles. A wrongly predicted branch costs 2 bubbles either way. A BTB read
in IF would remove the last bubble.
