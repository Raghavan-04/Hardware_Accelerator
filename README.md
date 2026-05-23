

# 2-Stage Pipelined Hardware Accelerator with Synchronous FIFOs

A high-frequency, 2-stage pipelined hardware accelerator designed to optimize the multiply-accumulate (MAC) critical path by decoupling 16-bit signed multiplication from 32-bit accumulation. This design is built for high-throughput, real-time data streaming using signed integer arithmetic and synchronous input queues.

## Key Features

* **2-Stage Pipelining:** Decouples 16-bit signed multiplication from 32-bit accumulation, shortening the critical path to maximize maximum clock frequency ($F_{max}$).
* **Two's Complement Arithmetic:** Fully implemented using 16-bit signed integer logic to easily handle positive and negative data streams natively.
* **FIFO-Buffered Inputs:** Integrated dual synchronous input FIFOs (`fifo_a` and `fifo_b`) to decouple host data ingestion from core computational execution.
* **High Throughput:** Achieves a sustained throughput of 1 result per clock cycle execution retirement after initial pipeline latency.
* **Active Saturation Guarding:** Engineered with active overflow mitigation logic that dynamically locks the 32-bit accumulator at maximum positive (`32'h7FFFFFFF`) or negative (`32'h80000000`) bounds if limits are breached.
* **Verilator Simulation Environment:** Fully verified using a modern C++ cycle-accurate simulation environment via Verilator and VCD timing tracing.

---

## Hardware Architecture & Pipeline Structure

The architecture isolates the multiplication delay from the accumulation loop feedback path to prevent timing violations at higher operational frequencies.

```text
       ┌─────────┐     ┌─────────┐
A_in ──┤ FIFO_A  ├────►│         │     ┌──────────┐     ┌────────────┐
       └─────────┘     │ Signed  ├────►│ Pipeline ├────►│  32-bit    ├──► Out
       ┌─────────┐     │  Mult   │     │ Register │     │ Accumulator│
B_in ──┤ FIFO_B  ├────►│         │     └──────────┘     └─────▲──────┘
       └─────────┘     └─────────┘                            │
                                └───────── Stage 1 ───────────┴─── Stage 2 ──┘

```

### Pipeline Stages

| Stage | Operation | Bit-Width | Description |
| --- | --- | --- | --- |
| **Stage 1** | Signed Multiplication | 16-bit × 16-bit → 32-bit | Pulls from FIFOs, calculates product, and latches to `mult_reg`. |
| **Stage 2** | Accumulation | 32-bit + 32-bit → 32-bit | Accumulates product into `acc_reg` with hard saturation overflow handling. |

---

## Simulation & Waveform Analysis

Verification is handled via a cycle-accurate Verilator testbench environment. The testcases isolate the behavior of the input buffers before streaming data into the core execution engine.

### 1. FIFO Ingestion & Buffer Queuing

Before processing begins, the testbench loads data vectors sequentially into the input FIFOs.

* **FIFO A Population:** Shows `fifo_a.din` receiving data values (`0x000a`, `0x0014`, `0x001e`, etc.) matching the write pointer (`wr_ptr`) increments. `fifo_a.empty` drops low once data is registered.
* **FIFO B Population:** Simultaneously buffers operand pairs (`0x0002`, `0x0003`, `0x0004`, etc.) into `fifo_b.mem`.

### 2. Computational Pipeline & MAC Execution

Once the execution unit is enabled (`processor.en = 1`), data streams out of the FIFOs into the processing core.

```text
                                MAC Waveform Verification
                __    __    __    __    __    __    __    __    __    __    __
processor.clk  |  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__
                      ┌──────────────────────────────────────────────────────────
processor.en   _______|
                      ┌───────┬───────┬───────┬───────┐
processor.a_in _______╳ 0x000a ╳ 0x0014 ╳ 0x001e ╳ 0x0028 ╳───────────────────────
                      ┌───────┬───────┬───────┬───────┐
processor.b_in _______╳ 0x0002 ╳ 0x0003 ╳ 0x0004 ╳ 0x0005 ╳───────────────────────
                              ┌───────┬───────┬───────┬──────────────────────────
mult_reg       ────────_______╳ 0x0014 ╳ 0x003C ╳ 0x0078 ╳ 0x00C8 ...
                                      ┌───────┬───────┬──────────────────────────
processor.out  ────────────────_______╳ 0x0014 ╳ 0x0050 ╳ 0x00C8 ...
                                      (20)    (80)    (200)

```

#### Mathematical Proof of Correctness (From Waves):

The hardware dynamically evaluates a streaming vector dot-product equation:

$$\text{Output} = \sum_{i=0}^{n} (A_i \times B_i)$$

#### Tracing the Cycle Transitions:

* **Cycle 1:** `processor.a_in = 10` (`0x000a`) and `processor.b_in = 2` (`0x0002`). The initial multiplication calculation ($20$) completes asynchronously within Stage 1.
* **Cycle 2:** Stage 1 latches the calculated product to `mult_reg` ($20$, `0x0014`) while Stage 2 begins preparing to accumulate it. Simultaneously, the next input pair arrives at the execution core: $20$ (`0x0014`) $\times 3$ (`0x0003`) = $60$.
* **Cycle 3:** The accumulator register updates to $20$. The new product of $60$ (`0x003C`) is latched into `mult_reg`. The next dataset streams in: $30$ (`0x001e`) $\times 4$ (`0x0004`) = $120$.
* **Retirement:** The system moves data down the pipeline step-by-step, verifying both multi-cycle execution latency and structural pipeline integrity under a continuous active data flow.

---

## Verifying Locally

### Prerequisites

Ensure your development environment has your required C++ toolchain and Verilator installed. On macOS, you can use Homebrew:

```bash
brew install verilator gtkwave

```

### Running the Testbench

To compile the underlying hardware code and execute the simulation tracking wave trace file, run the root Makefile:

```bash
make clean && make


To visually audit the hardware trace signals yourself, load the exported data directly inside GTKWave:

```bash
make view

