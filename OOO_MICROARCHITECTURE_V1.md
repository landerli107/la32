# Small-window out-of-order microarchitecture v1

## 1. Fixed scope

This document defines the implementation target approved for branch
`architecture/small-window-ooo-v1`.  The branch starts from the online-proven
dual-issue baseline commit `9339a1a`.

External contracts are fixed:

- `myCPU_top` and the SRAM/AXI/cache-maintenance interfaces do not change.
- The official Vivado Tcl flow and synthesis/implementation strategies do not
  change.
- The core remains a two-wide machine and retires strictly in program order.
- Branch recovery, CSR serialization and cache maintenance must be preserved.
- The present RTL has no architectural exception/ERTN/TLB pipeline.  This
  project does not invent one during the performance work; if that ISA scope is
  added later, exception metadata must be carried to ROB head before use.
- A D-cache L1 hit must not gain a mandatory cycle and the hit path must retain
  a sustained throughput of one request per cycle.

The online baseline implementation is the timing and resource reference:

| Metric | Baseline |
| --- | ---: |
| Clock | 105.469 MHz / 9.481 ns |
| WNS / TNS | +0.075 ns / 0 ns |
| WHS / THS | +0.034 ns / 0 ns |
| LUT / FF | 12,831 / 6,129 |
| BRAM / DSP | 20.5 / 0 |

The baseline worst setup path is from the fetch PC through the instruction
buffer hit/response control to an IF/ID queue clock-enable pin.  It is 8.939 ns,
12 logic levels, with 6.500 ns of routing delay.  No new rename, ROB or issue
logic may be added to that path.

## 2. End-state pipeline

The target data flow is:

```
F0 request/predict
  -> F1 elastic fetch response
  -> D decode
  -> R rename and ROB allocation
  -> Q dispatch / registered issue selection
  -> X execute or address generation
  -> M ordered LSU / cache
  -> W result broadcast
  -> C in-order commit
```

Every boundary is an elastic ready/valid boundary.  Back-pressure terminates at
the closest boundary register; it must not be recomputed through the complete
pipeline in one combinational cycle.

The first implementation does not execute the whole architecture at once.
Each phase below leaves the branch functional and independently reversible.

## 3. Front end and phase-1 timing boundary

### 3.1 Elastic fetch response slice

Insert a one-packet elastic response slice between `if_run` and the existing
ordered IF/ID queue.  A packet contains:

```
valid0                 1
valid1                 1
slot0 payload        160
slot1 payload        160
------------------------
total                 322 bits
```

The slice supports simultaneous pop and push.  Therefore, after initial fill,
it can accept one cache response packet and deliver one packet every cycle.
The response slice, not the ID queue, drives `inst_resp_ready`.

Rules:

1. A response is acknowledged only when the complete one- or two-instruction
   packet can enter the slice.
2. A redirect clears the slice and the downstream packet queue in the same
   cycle.
3. A wrong-path cache response may be acknowledged and discarded, but must
   never set a valid bit.
4. If the slice is full and the consumer is stalled, payload and valid bits are
   stable and the cache response is not acknowledged.
5. Simultaneous pop/push replaces the packet atomically; it must not create a
   bubble on a continuous L0 I-cache hit stream.

This removes the direct `inst_data_ok -> ID queue CE` dependency.  It does not
register the D-cache hit response and does not touch the D-cache state machine.

### 3.2 Performance observation

Simulation-only counters are retained or added under `ifndef SYNTHESIS` so they
cannot affect implementation timing or resources.  Per workload, record:

- total cycles and retired instructions;
- slot-0/slot-1 issue and commit counts;
- pair-block reasons;
- front-end empty/full cycles;
- fetch fast-hit responses, registered/refill responses and I-cache misses;
- D-cache load hits, load misses, store accepts and D-cache wait cycles;
- AXI read requests and read-wait cycles;
- redirects and flushed instructions.

No performance estimate is accepted without these counters or exact benchmark
cycle counts.

## 4. Rename and reorder buffer

### 4.1 ROB organization

The ROB has 16 entries and allocates up to two consecutive entries per cycle.
Every dependency tag is five bits: `{generation, index[3:0]}`.  The generation
bit toggles when an index is reused, preventing a stale canceled result from
completing a new occupant of that index.

Each entry contains at least:

| Field | Bits | Purpose |
| --- | ---: | --- |
| valid | 1 | allocated entry |
| complete | 1 | result/side effects are ready |
| pc | 32 | exception/debug/recovery PC |
| instruction class | 4 | ALU/branch/load/store/mul-div/CSR-serial |
| architectural rd | 5 | commit destination |
| writes rd | 1 | suppresses x0/non-writing instructions |
| result | 32 | data-carrying ROB result |
| branch checkpoint valid/id | 1 + 2 | branch recovery association |
| store valid/index | 1 + 2 | committed store association |
| serial index | 14 | CSR number or zero-extended CACOP code |
| serial operand 0 | 32 | CSR source or CACOP effective address |
| serial operand 1 | 32 | CSR mask/value operand |

The packed entry is 160 bits.  Normal ALU/branch/load/store operations tie the
unused serial fields to zero.  The ROB is implemented as entry-local registers
with explicit per-entry enables in the first version; this avoids asynchronous
multiport BRAM inference and keeps allocation, completion and commit writes
separate.

### 4.2 RAT and source tags

The rename allocation table has 32 entries.  Entry zero is permanently
unmapped and reads as zero.  Each other entry contains `{mapped, rob_tag}`.

For each source operand at rename:

- If RAT says unmapped, read the committed architectural register file.
- If mapped and the producer ROB entry is complete, copy its value.
- If mapped and incomplete, dispatch the ROB tag as an unresolved dependency.
- Same-cycle slot-0 to slot-1 RAW is represented by slot-0's newly allocated
  ROB tag.

Destination allocation updates RAT in program order: slot 0 first, slot 1
second.  This naturally removes WAR and WAW hazards.

The first version uses a data-carrying ROB plus operand-carrying issue entries,
not a 48-entry four-read/two-write physical register file.  This avoids a large
multiported FPGA read mux.  Rename-to-ROB value selection is a registered stage
and is not combined with issue selection or execution.

### 4.3 Commit

Commit is at most two instructions per cycle and always starts at ROB head.

- Slot 1 may commit only if slot 0 commits and slot 0 has no redirect or
  serializing action.
- Register state is written only at commit.
- A RAT mapping is cleared only when it still points to the committing tag;
  a younger mapping to the same architectural register is retained.
- Stores update architectural memory only after reaching the head.
- CSR and cache-maintenance operations execute serially after all older
  instructions have committed and before any younger side effect is allowed.
- No non-existent exception path is added to the current core.  A future
  exception extension must stop at ROB head and may not reuse branch recovery
  implicitly.

## 5. Dynamic issue

### 5.1 Integer issue queue

The integer issue queue has eight entries.  Each entry carries:

- valid and age/ROB tag;
- operation class and immediate/control metadata;
- source-0 `{ready, value, tag}`;
- source-1 `{ready, value, tag}`;
- destination ROB tag;
- branch checkpoint association.

Two registered result broadcasts update ready bits and operand values.  Issue
selection chooses up to two oldest compatible ready entries:

- two ALU operations;
- one ALU plus one branch;
- one ALU plus one multiply when the multiplier accepts;
- at most one LSU operation through the separate LSQ.

Wakeup and selection are not allowed to feed execution in the same cycle.
Selection is registered, operand muxing occurs in the following stage, and
execution results are broadcast in a later stage.  This is the principal FPGA
timing rule for the out-of-order backend.

### 5.2 Functional units

- Two simple integer ALUs.
- One branch unit, sharing an issue port with ALU0 if required by timing.
- One LSU/address-generation path.
- Existing multiply/divide path with explicit busy/ready handshake.

No functional unit writes the architectural register file directly.  All
results complete their destination ROB entry, then commit in order.

## 6. Branch recovery

Support four unresolved branch checkpoints.  A checkpoint stores:

- RAT snapshot;
- ROB tail after the branch;
- issue-queue and LSQ younger-entry boundary or branch mask;
- free checkpoint state;
- predicted next PC needed for validation.

On correct prediction, release the checkpoint.  On misprediction:

1. restore the checkpointed RAT and ROB tail;
2. invalidate all younger IQ and LSQ entries using the branch mask/tag;
3. clear fetch/decode/rename packets;
4. redirect the front end exactly once;
5. retain the branch itself for normal in-order commit.

If all four checkpoints are occupied, dispatch stops at the next branch.  It
must not silently run a branch without recoverable state.

## 7. Ordered load/store queue

Use four load entries and four store entries in phase 4.

Store rules:

- address and data may become ready out of order;
- a store writes D-cache/store buffer only when it is the oldest committing ROB
  instruction;
- an exception or branch flush invalidates younger stores before any side
  effect occurs.

Load rules:

- a load may issue only after every older store has a known address;
- compare against all older valid stores;
- forward from the youngest matching older store when its data is ready;
- wait if a matching store has no data;
- access D-cache only when no older address match exists.

The first LSQ version permits only one cache miss transaction.  Two MSHRs are a
separate phase-5 change and require request tags plus ordered response handling.

## 8. Cache invariants

The phase-1 through phase-4 work preserves the v1 D-cache protocol:

- synchronous D-cache lookup launches in `S_IDLE` and hit completion occurs in
  `S_DTAG`;
- continuous hit traffic remains capable of one accepted request per cycle;
- no unconditional `S_DRESP` hop is inserted for hits;
- response skid/FIFO logic may assert back-pressure only when actually full;
- direct AXI/critical-word responses retain their earliest architecturally safe
  forwarding point.

A monolithic 1 MiB L1 is excluded.  A banked 256/512 KiB L2, prefetching or two
MSHRs is selected only after measured phase-4 stall data.

## 9. Timing budget

The safe signoff target for the first complete out-of-order core is 110 MHz.
The stretch target is 115 MHz.  At the selected online clock:

- WNS must be at least +0.30 ns;
- TNS and THS must be zero;
- no new unconstrained synchronous path is allowed;
- the default official synthesis and implementation strategies are used.

Combinational path budgets at 110 MHz are:

| Path | Budget |
| --- | ---: |
| fetch request to response-slice input | 7.5 ns |
| decode to rename register | 6.5 ns |
| RAT/ROB lookup to dispatch register | 7.0 ns |
| IQ wakeup/select to selection register | 6.5 ns |
| selected operand mux to execute register | 6.5 ns |
| ALU/branch to result register | 6.5 ns |
| LSQ compare/forward decision | 7.0 ns |
| commit selection to architectural state | 6.5 ns |

The budgets deliberately leave routing and clock uncertainty margin inside the
9.091 ns clock period.

## 10. Phase gates

Every phase is an independent Git commit.  A phase may advance only after:

1. `git diff --check` and HDL lint pass without new actionable warnings.
2. All affected directed tests pass, including simultaneous push/pop, stalls,
   redirects, same-cycle dependencies, x0, wraparound and flush cases.
3. The existing full functional suite and four official-reference workloads
   pass.
4. Exact cycles and counters are recorded.  Total cycles may not regress by
   more than 1%, and no workload may regress by more than 3%, unless the change
   is an explicitly approved measurement-only stage.
5. Vivado XSIM smoke testing passes for front-end, memory or control changes.
6. Default-flow Vivado implementation has TNS=0, THS=0 and WNS at or above the
   phase target.

Phase targets:

| Phase | Functional target | Timing target |
| --- | --- | --- |
| 1 | response slice + counters, identical architectural trace | baseline clock, WNS >= +0.30 ns |
| 2 | 16-entry ROB/RAT, still ordered issue, exact commit/serial trace | 105.469 MHz, WNS >= +0.20 ns |
| 3 | integer out-of-order issue, exact in-order commit trace | 110 MHz, WNS >= +0.30 ns |
| 4 | conservative LSQ, memory-order directed tests | 110 MHz, WNS >= +0.30 ns |
| 5 | measured memory-latency optimization | 110-115 MHz, WNS >= +0.30 ns |

If a phase fails correctness, cycle or timing gates, the phase is not patched by
changing unrelated logic.  It is reverted to its boundary and redesigned from
the failed interface or path report.
