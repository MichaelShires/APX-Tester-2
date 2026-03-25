# APX Tester — Project Plan

---

# Part I: APX Instruction Emission Analysis

## Thesis

As hardware manufacturers introduce novel instruction set extensions, optimizing compilers
may fail to emit new instructions because upstream optimization passes transform the IR
enough that the instruction selector no longer recognizes the original source-level patterns.
We use Intel APX as a proof-of-concept to study this phenomenon in LLVM.

## Target Instructions

| Instruction | Feature Flag | Pattern |
|---|---|---|
| **CCMP/CTEST** | `-mapxf` | Compound conditionals (`if (a > x && b < y)`) |
| **NDD CMOV** | `-mapxf` | Conditional assignment (`x = cond ? a : b`) — 3-operand form |
| **CFCMOV** | `+cf` (separate) | Conditional memory access with fault suppression |
| **PUSH2/POP2** | `-mapxf` | Paired push/pop in function prologues/epilogues |

## Completed Phases

### Phase 1 — Archetypal Functions & Baseline (COMPLETE)
- [x] Wrote archetypal C functions for CCMP, NDD CMOV, CFCMOV, PUSH2/POP2
- [x] Confirmed each emits expected APX instruction in isolation
- [x] Discovered CFCMOV requires separate `+cf` flag (not in `-mapxf`)
- [x] Discovered NDD CMOV is distinct from CFCMOV (architectural difference)
- [x] O0-O3 sweep: all APX patterns activate at O1, stable through O3

### Phase 2 — SPEC CPU 2017 Analysis (COMPLETE)
- [x] Compiled 265 files across 5 benchmarks with/without APX
- [x] Counted 8,646 APX instructions with `-mapxf`, 9,708 with `+cf`
- [x] Missed opportunity analysis: CCMP ~105% conversion, NDD CMOV 100%, PUSH2 48-89%
- [x] CFCMOV impact: 1,120 instructions, 634 branches eliminated, 45% of files benefit

### Phase 3 — CSmith Context Sensitivity (COMPLETE)
- [x] 500 CSmith programs tested across O2/O3 with noinline, inlineable, force-inlined
- [x] 100% pass rate — APX patterns robust against random context
- [x] Identified that CSmith uses scalar parameters (explains 100% rate)

### Phase 4 — Adversarial Context Testing (COMPLETE)
- [x] 23 adversarial functions across 5 categories
- [x] 52% failure rate — memory operands, volatile, switch, setjmp break patterns
- [x] CCMP is register-only: pointer dereferences prevent pattern recognition
- [x] CFCMOV most resilient (designed for memory access)

### Phase 5 — CFCMOV Deep Dive (COMPLETE)
- [x] Traced transformation through SimplifyCFGPass using `-print-after-all`
- [x] Identified `TTI.hasConditionalLoadStoreForType()` as the gatekeeper
- [x] CFCMOV requires IR-level transformation (not just ISel), unlike CCMP/NDD CMOV

### GUI & Infrastructure (COMPLETE)
- [x] Swift Package with APXCore library, CLI, and macOS SwiftUI app
- [x] All compilation and analysis scripts in `scripts/`

---

# Part II: Differential Fuzzing for APX Correctness

## Thesis

When a compiler emits new APX instructions (CFCMOV, CCMP, NDD CMOV) in place of
traditional instruction sequences, the transformation must preserve program semantics.
Using differential fuzzing, we test whether APX-compiled code produces identical output
to non-APX code across randomly generated programs. Semantic mismatches indicate
compiler bugs — potential security vulnerabilities.

## Methodology

1. Generate random C programs (CSmith)
2. Compile each program twice: with APX flags and without
3. Run both binaries through Intel SDE (APX emulation)
4. Compare outputs — any mismatch is a potential miscompilation bug
5. For mismatches: minimize the test case and identify the responsible APX transformation

## Phases

### Phase 6 — Differential Fuzzing Infrastructure
**Goal**: Build automated pipeline to compile, run, and compare APX vs non-APX outputs.

- [ ] Set up Intel SDE runner for APX-compiled binaries
- [ ] Build differential fuzzing harness: CSmith → compile (APX/no-APX) → SDE → compare
- [ ] Handle timeouts, crashes, and undefined behavior
- [ ] Automate result collection and triage

### Phase 7 — Fuzzing Campaign
**Goal**: Run large-scale differential fuzzing to find APX miscompilations.

- [ ] Run N programs through the differential fuzzer
- [ ] Classify results: match, mismatch, crash, timeout, UB
- [ ] For any mismatches: reduce test case and identify root cause
- [ ] Test across O1, O2, O3 and with/without +cf

### Phase 8 — Final Writeup
**Goal**: Produce a graduate-level report covering both parts.

- [ ] Part I: instruction emission analysis (findings from Phases 1-5)
- [ ] Part II: differential fuzzing (methodology and results from Phases 6-7)
- [ ] Threats to validity
- [ ] Conclusion: how hardware ISA extensions interact with compiler correctness

## Toolchain

- **Compiler**: LLVM/Clang 22.1.1 with `-mapxf` and `+cf`
- **Target**: `x86_64-apple-macos` (cross-compiled from Apple Silicon)
- **Emulation**: Intel SDE for APX instruction execution
- **Fuzzer**: CSmith for random C program generation
- **Analysis app**: Swift Package (APXCore library, CLI, macOS GUI)

## Key Decisions

- LLVM only (no GCC) — deeper pass-level analysis
- NDD CMOV included (discovered to be distinct from CFCMOV)
- CSmith + SPEC + adversarial = three complementary test strategies
- Differential fuzzing extends CSmith work into correctness testing
- CLI is the submittable artifact; GUI is a personal tool
