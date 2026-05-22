# Synchronous FIFO Design & Verification

## 1. Project Overview
This repository contains an RTL design and verification project for a **parameterized 8-bit synchronous FIFO buffer** with overflow/underflow protection and early-warning status flags.

The project demonstrates a complete mini verification flow for digital design:
- Implementing a synthesizable, parameterizable synchronous FIFO in SystemVerilog.
- Verifying functional correctness with both directed and class-based constrained-random OOP testbench methodology.
- Self-checking output using a scoreboard reference model with mailbox-based communication.
- Measuring verification quality through functional coverage metrics.
- Runtime invariant checking via SVA assertions.

---

## 2. Project Scope and Objectives
The implemented FIFO targets the following objectives:
- Build a working single-clock circular-buffer FIFO with configurable data width and depth.
- Support deterministic read/write sequencing with explicit status signaling.
- Validate functional correctness for:
  - basic write and read ordering (FIFO property),
  - full/empty flag assertion and deassertion at correct entry counts,
  - overflow protection — write attempts when full are silently blocked,
  - underflow protection — read attempts when empty are silently blocked,
  - simultaneous read and write in the same cycle,
  - early-warning flags (`almost_full`, `almost_empty`) within ±2 entries of boundary,
  - clean state restoration after synchronous reset.

---

## 3. RTL Design Architecture

### 3.1 `sync_fifo`
The FIFO is implemented as a single-clock circular buffer driven by `clk` with a synchronous active-low reset `rst_n`.

**Internal structure:**
- `mem [0:DEPTH-1]`: register array of `DATA_WIDTH`-bit words.
- `wr_ptr`: write pointer, advances on every accepted write.
- `rd_ptr`: read pointer, advances on every accepted read.
- `count`: entry count — one extra bit wide to safely represent the value `DEPTH` without aliasing with 0.

**Parameters:**

| Parameter    | Default | Constraint           | Description                     |
|-------------|---------|----------------------|---------------------------------|
| `DATA_WIDTH` | 8       | ≥ 1                  | Width of each data word (bits)  |
| `DEPTH`      | 16      | Power of 2, ≥ 2      | Number of entries in the FIFO   |

**Protocol behavior:**
- Write is accepted when `wr_en = 1` and `full = 0`; otherwise silently ignored.
- Read pointer advances when `rd_en = 1` and `empty = 0`; otherwise silently ignored.
- Simultaneous read and write (`wr_en = 1`, `rd_en = 1`, `!full`, `!empty`) is fully supported — count remains unchanged while both pointers advance.
- `dout` is combinatorial (`dout = mem[rd_ptr]`) — no additional read latency.
- `almost_full` asserts when `count >= DEPTH - 2`, providing two cycles of advance warning before the full boundary.
- `almost_empty` asserts when `count <= 2` and the FIFO is not empty.

**Status flag logic (combinatorial):**
```
full         = (count == DEPTH)
empty        = (count == 0)
almost_full  = (count >= DEPTH - 2)
almost_empty = (count <= 2) && !empty
```

**Flag behavior summary:**

| wr_en | rd_en | full | empty | Behavior                           | count Δ |
|:-----:|:-----:|:----:|:-----:|------------------------------------|:-------:|
| 0     | 0     | X    | X     | Idle                               | 0       |
| 1     | 0     | 0    | X     | Write accepted                     | +1      |
| 1     | 0     | 1    | X     | Write blocked (overflow protect)   | 0       |
| 0     | 1     | X    | 0     | Read accepted                      | −1      |
| 0     | 1     | X    | 1     | Read blocked (underflow protect)   | 0       |
| 1     | 1     | 0    | 0     | Simultaneous R/W                   | 0       |
| 1     | 1     | 1    | 0     | Only read executes                 | −1      |
| 1     | 1     | 0    | 1     | Only write executes                | +1      |

---

## 4. Module Diagram

```text
                    +-----------------------------------------------+
                    |                 sync_fifo                     |
                    |                                               |
  clk    --------->|                                               |
  rst_n  --------->|   +-----------------------------------+       |
  wr_en  --------->|   |  Circular Buffer                  |       |
  din    --------->|   |  logic [DATA_WIDTH-1:0]           |       |
                    |   |  mem [0:DEPTH-1]                  |       |
                    |   +-----------------------------------+       |
                    |         ^                   |                 |
                    |         | wr_ptr            | rd_ptr          |
                    |         |                   v                 |
                    |   +----------+       +----------+             |
                    |   | wr logic |       | rd logic |             |
                    |   +----------+       +----------+             |
                    |         |                   |                 |
                    |         +--------+----------+                 |
                    |                  |                            |
                    |              [ count ]                        |
                    |                  |                            |
                    |    +-------------+-------------+              |
                    |    |             |             |              |
  dout   <----------|----+          flags        warnings          |
  full   <----------|-----------  (full,       (almost_full,       |
  empty  <----------|-----------   empty)       almost_empty)       |
  al_full<----------|                                              |
  al_empty<---------|                                              |
                    +-----------------------------------------------+
```

---

## 5. Verification Methodology

### 5.1 OOP Class-Based Testbench Architecture

The testbench follows a **traditional OOP verification architecture** with separate, reusable components communicating via typed mailboxes.

```
 ┌────────────────────────────────────────────────────────────────┐
 │                   fifo_tb.sv (top-level)                       │
 │                                                                │
 │  ┌──────────────┐  gen2drv   ┌──────────────┐                 │
 │  │fifo_generator│─[mailbox]─►│ fifo_driver  │──► DUT pins     │
 │  └──────────────┘            └──────────────┘        │         │
 │         ↑ creates                                DUT outputs   │
 │  ┌──────┴──────┐             ┌──────────────┐        │         │
 │  │fifo_transact│             │ fifo_monitor │◄───────┘         │
 │  │    -ion     │             │  (passive)   │  @posedge        │
 │  └─────────────┘             └──────┬───────┘                  │
 │                                     │ mon2sb                   │
 │                                [mailbox]                       │
 │                                     │                          │
 │                             ┌───────▼──────┐                   │
 │                             │fifo_scoreboard│                  │
 │                             │  ref_q [$]   │                   │
 │                             └──────────────┘                   │
 │                                                                │
 │  ┌──────────────────┐  ┌─────────────────────┐                │
 │  │ fifo_coverage    │  │  fifo_assertions     │               │
 │  │ (module)         │  │  (module)            │               │
 │  │ covergroup       │  │  always @(posedge)   │               │
 │  └────────┬─────────┘  └──────────┬───────────┘               │
 │           └───── DUT signals ──────┘                           │
 └────────────────────────────────────────────────────────────────┘
```

**Components:**

| File | Type | Role |
|---|---|---|
| `fifo_transaction.sv` | Class | Randomized stimulus object — `rand` fields + `dist` constraint |
| `fifo_generator.sv` | Class | Transaction producer — 5 directed sequences + random |
| `fifo_driver.sv` | Class | Protocol-aware pin-level stimulus executor via `ref` params |
| `fifo_monitor.sv` | Class (×2) | `fifo_result` packet + passive output observer |
| `fifo_scoreboard.sv` | Class | Reference model (`ref_q [$]`) + PASS/FAIL checker |
| `fifo_coverage.sv` | Module | Functional coverage via `covergroup` + `cross` |
| `fifo_assertions.sv` | Module | Runtime SVA assertions using `$past()` |
| `fifo_tb.sv` | Module | Top-level: `include` classes, fork/join_none, control flow |

**Verification characteristics:**
- Constrained-random transaction generation with `dist` weighted distribution.
- Typed `mailbox` for inter-component communication — thread-safe, blocking `get()`.
- `fork/join_none` for concurrent Driver + Monitor + Scoreboard execution.
- Reference model with `push_back`/`pop_front` queue mirroring DUT FIFO order.
- Functional coverage with cross bins proving boundary scenarios were executed.
- `$past()` assertions catching overflow/underflow the cycle they occur.

### 5.2 Test Sequences

| # | Sequence | Type | What is Verified |
|:---:|---|:---:|---|
| 1 | `seq_fill_drain(16)` | Directed | FIFO order, full/empty flag transitions |
| 2 | `seq_overflow(16)` | Directed | Overflow protection, Assert 2 |
| 3 | `seq_underflow()` | Directed | Underflow protection, Assert 3 |
| 4 | `seq_simultaneous(16)` | Directed | Concurrent R/W, count stability |
| 5 | `seq_random(300, 16)` | Constrained Random | All paths, cross coverage bins, stress |

---

## 6. Assertions

Three runtime assertions checked every rising clock edge during normal operation:

| ID | Condition | Failure Indicates |
|:--:|---|---|
| 1 | `!(full && empty)` | count logic error — physically impossible state |
| 2 | Write into full (no read) → remains full next cycle | Overflow: `wr_ptr` advanced incorrectly |
| 3 | Read from empty (no write) → remains empty next cycle | Underflow: `rd_ptr` advanced incorrectly |

`$past()` is used to reference signal values from the previous clock cycle, avoiding race conditions with DUT output settling (NBA region).

**Why `module` not `class` for assertions?** `$past()` requires a procedural temporal context (always block in module). Classes in SV cannot host `$past()` without a virtual interface.

---

## 7. Functional Coverage

Coverage collected via `covergroup fifo_cg @(posedge clk iff rst_n)` — sampled only when out of reset.

**Coverpoints:**

| Coverpoint | What is Tracked |
|---|---|
| `cp_ops` | Operation type: `{wr_en, rd_en}` → wr_only / rd_only / both / idle |
| `cp_full` | `full` flag seen at both 0 and 1 |
| `cp_empty` | `empty` flag seen at both 0 and 1 |
| `cp_almost_full` | `almost_full` flag seen at both 0 and 1 |
| `cp_almost_empty` | `almost_empty` flag seen at both 0 and 1 |

**Cross coverage:**

| Cross | What it Proves |
|---|---|
| `cp_ops × cp_full` | Write-while-full (overflow attempt) was actually exercised |
| `cp_ops × cp_empty` | Read-while-empty (underflow attempt) was actually exercised |

**Coverage target:** ≥ 90% across all coverpoints and cross bins.

**Why cross coverage matters:** A single coverpoint only proves "write happened" and "FIFO was full" — independently. The cross proves "write happened **while** FIFO was full" — that is the overflow scenario.

---

## 8. Repository Structure

```text
Design_and_verify_FIFO_module/
├── rtl/
│   └── sync_fifo.sv              # DUT — parameterized synchronous FIFO
├── tb/
│   ├── fifo_transaction.sv       # Class: randomized stimulus object
│   ├── fifo_generator.sv         # Class: 5 directed + random sequences
│   ├── fifo_driver.sv            # Class: protocol-level DUT pin driver
│   ├── fifo_monitor.sv           # Class: fifo_result + passive observer
│   ├── fifo_scoreboard.sv        # Class: reference model + PASS/FAIL
│   ├── fifo_coverage.sv          # Module: covergroup + cross coverage
│   ├── fifo_assertions.sv        # Module: $past()-based SVA assertions
│   ├── fifo_tb.sv                # Module: top-level OOP testbench
│   └── fifo_tests.sv             # [DEPRECATED] — replaced by fifo_generator.sv
├── sim/
│   └── run.sh                    # ModelSim/QuestaSim compile & run script
├── DESIGN_SPEC.md                # RTL + TB design specification (detailed, with syntax explanations)
└── README.md
```

---

## 9. How to Run

### Option A — ModelSim / QuestaSim (local)

```bash
cd sim
bash run.sh
```

The script compiles in the correct order:
1. `sync_fifo.sv` (RTL)
2. `fifo_coverage.sv` (module — covergroup)
3. `fifo_assertions.sv` (module — SVA)
4. `fifo_tb.sv` (top — `include`s all class files internally)

### Option B — EDA Playground (no installation required)

1. Go to [edaplayground.com](https://edaplayground.com) and create a free account.
2. In **Tools & Simulators**, select **Aldec Riviera-PRO 2022.04**.
3. Check ✅ **Open EPWave after run** to view waveforms.
4. Paste `rtl/sync_fifo.sv` into the **Design** panel (left).
5. Paste the following **merged** into the **Testbench** panel (right), in this order:
   - Remove all `` `include `` lines from `fifo_tb.sv`
   - Concatenate: `fifo_transaction.sv` → `fifo_generator.sv` → `fifo_driver.sv`
     → `fifo_monitor.sv` → `fifo_scoreboard.sv` → `fifo_coverage.sv`
     → `fifo_assertions.sv` → `fifo_tb.sv` (without `include`s)
6. Click ▶ **Run**.

---

## 10. Expected Simulation Output

```
[RESET] Done — empty=1 full=0

[GEN] ── TEST 1: Fill & Drain (N=16) ──
[SB PASS] exp=0x00  got=0x00
[SB PASS] exp=0x02  got=0x02
...
[SB PASS] exp=0x1E  got=0x1E

[GEN] ── TEST 2: Overflow Attempt ──
[SB PASS] exp=0xAA  got=0xAA
...

[GEN] ── TEST 3: Underflow Attempt ──

[GEN] ── TEST 4: Simultaneous R/W (pre_fill=8, rw=8) ──
[SB PASS] exp=0x10  got=0x10
...

[GEN] ── TEST 5: Constrained Random (300 txns) ──
[SB PASS] ...
...

[GEN] ── All sequences complete. Total sent: 368 ──

[GEN] Total transactions sent: 368
[DRV] Total transactions driven: 368
[MON] Observed — writes: 207  reads: 207

╔══════════════════════════════════════╗
║         SCOREBOARD REPORT            ║
╠══════════════════════════════════════╣
║  Writes  : 207                       ║
║  Reads   : 207                       ║
║  PASS    : 207                       ║
║  FAIL    : 0                         ║
╠══════════════════════════════════════╣
║  >>> ALL CHECKS PASSED ✓             ║
╚══════════════════════════════════════╝

[COV] Functional Coverage = 93.8%
```

---

## 11. Technical Notes

**Compile order is important:**
- `fifo_coverage.sv` and `fifo_assertions.sv` must be compiled **before** `fifo_tb.sv`
  because `fifo_tb` instantiates them as sub-modules.
- Class files (`fifo_transaction.sv`, etc.) are `` `include ``d by `fifo_tb.sv` in
  dependency order — they are NOT compiled separately.

**Why `ref` instead of `virtual interface`?**
- This project deliberately avoids virtual interfaces to keep the OOP structure
  accessible and self-contained. `ref` task arguments provide equivalent
  functionality for a single-module testbench.

**Why separate `module` for coverage and assertions?**
- `covergroup` needs real-time signal access with a clock event → requires module scope.
- `$past()` needs procedural temporal context → requires always block in module.
- Classes cannot host these constructs without virtual interfaces.

**Current limitations:**
- Single clock domain only; asynchronous FIFO (dual-clock) is not implemented.
- DEPTH must be a power of 2; arbitrary depths require gray-code pointer logic.
- No formal SVA `property`/`endproperty` declarations; assertions use `assert` statements.

**Potential next improvements:**
- Add formal SVA properties (e.g., `$rose(full) |-> $past(almost_full)`).
- Add virtual interface for cleaner class-to-DUT signal binding.
- Extend to an asynchronous dual-clock FIFO with gray-code pointer synchronization.
- Parameterized regression sweep across `DATA_WIDTH` and `DEPTH` configurations.
- Migrate to UVM base classes as a next step toward industry-standard methodology.

---

## 12. Important Notes
- The `sim/run.sh` script targets ModelSim/QuestaSim. Compilation flags may differ for VCS, Xcelium, or Riviera-PRO.
- For EDA Playground, manually concatenate all TB files in dependency order (see Section 9, Option B).
