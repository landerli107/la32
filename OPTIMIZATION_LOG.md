# Optimization Log

| Item | Result |
| --- | --- |
| Status | `FULLY_VERIFIED` |
| Branch | `experiment/20260801-stable-parallel-branch-redirect` |
| Stable baseline | `codex/stable-verified-20260731` at `4cc9f3505b5e1551dbb0eddeb6e00cb661128ac9` |
| Optimization target | Remove the second 32-bit comparison from the conditional-branch redirect path without changing branch decisions, resolved PC, pipeline latency, or CPI. |
| Modified files | `src/soc/BranchUnit.v`, `OPTIMIZATION_LOG.md` |
| Rationale | Compare `pred_PC` with the branch target and fallthrough PC in parallel with the branch condition, then select one-bit match results instead of comparing `pred_PC` after the 32-bit resolved-PC mux. |
| Functional impact | Intended to be combinationally equivalent. No state, protocol, hazard, forwarding, cache, or clock behavior changes. |
| Risks | A branch-op polarity/default mismatch could redirect incorrectly; synthesis may duplicate comparators or route match signals poorly and provide no timing gain. |
| Quick validation | `git diff --check`: PASS. Candidate `BranchUnit.v` is byte-identical to the previously proven RTL; its parent `BranchUnit.v` is also byte-identical to that proof's parent, so the existing Yosys result applies (`33/33` `$equiv` cells proven, no latches). Vivado 2019.2 `xvlog -d SIMULATION` and `xelab`: PASS. Official A/D/G/R: PASS at `166824` cycles, identical to the stable baseline. |
| Local implementation | PASS at `105.46875 MHz`: WNS `+0.074 ns`, TNS `0`, WHS `+0.087 ns`, THS `0`. Worst setup path is `dc_meta_ram/meta_reg_0 -> dc_meta_ram/meta_reg_1/ADDRBWRADDR[10]`, `8.620 ns`, 9 logic levels (`3.070 ns` logic, `5.550 ns` route). |
| Resources | `7332 LUT`, `3715 FF`, `20.5 BRAM Tile`, `0 DSP`; versus stable baseline: `+19 LUT`, unchanged FF/BRAM/DSP. |
| Full validation | PASS. Official-reference XSim: Crypto `29403752`, Matrix `6537565`, Mixed `437237`, Stream `5155474`; total `41534028` cycles, identical to stable. Online pipeline `#14235` / job `#14971` passed for fixed RTL `5a0d15c`: WNS `+0.074 ns`, TNS `0`, routed WHS `+0.086 ns`, THS `0`. Local implementation independently passed with WNS `+0.074 ns`, TNS `0`, WHS `+0.087 ns`, THS `0`. |
| Current conclusion | `FULLY_VERIFIED`. The combinational rewrite is formally equivalent, preserves all four benchmark cycle counts, and improves both local and official online WNS by `0.071 ns` over stable. It is the current best verified cycle-neutral version and is eligible to advance the local stable branch. |

## Result history

- 2026-08-01: Local implementation met setup and hold timing with WNS `+0.074 ns`; branch naming was changed to the user-requested non-`codex` namespace. A non-skip documentation commit triggers the first official online implementation while four local benchmarks run on fixed RTL `5a0d15c`.
- 2026-08-01: Crypto, Matrix, Mixed and Stream all passed at the exact stable cycle counts. Online pipeline `#14235` independently passed timing and generated the bitstream; status advanced to `FULLY_VERIFIED`.
