# APX Tester — Project Plan

## Thesis

As hardware manufacturers introduce novel instruction set extensions, optimizing compilers
may fail to emit new instructions because upstream optimization passes transform the IR
enough that the instruction selector no longer recognizes the original source-level patterns.
We use Intel APX as a proof-of-concept to study this phenomenon in LLVM.

## Target Instructions

| Instruction | Pattern | Why it's interesting |
|---|---|---|
| **CCMP/CTEST** | Compound conditionals (`if (a > x && b < y)`) | Jump threading / SimplifyCFG can restructure compound conditionals into separate basic blocks before instruction selection |
| **CFCMOV** | Conditional assignment (`x = cond ? a : b`) | Tests whether APX's flag-preserving conditional move is exploited, and whether GVN/LICM break the pattern |
| **PUSH2/POP2** | Function prologue/epilogue with multiple callee-saved registers | Tests whether inlining eliminates function boundaries and therefore PUSH2/POP2 opportunities |

## Toolchain

- **Compiler**: LLVM/Clang with `-mapxf` flag
- **Target**: `x86_64-unknown-linux-gnu` (cross-compiled from Apple Silicon)
- **Emulation**: Intel SDE for running APX-compiled binaries
- **Random program generation**: CSmith
- **Analysis app**: Swift Package with shared `APXCore` library, CLI (`apx-tester`), and macOS GUI

## Phases

### Phase 1 — SPEC Baseline & Archetypal Functions (Week 1)
**Goal**: Establish that LLVM can emit APX instructions and measure real-world usage.

- [ ] Diff existing SPEC assembly outputs (APX vs non-APX) to count CCMP, CTEST, CFCMOV, PUSH2, POP2 usage
- [ ] Build summary statistics: instruction counts per benchmark, per instruction type
- [ ] Write archetypal C functions for each target instruction (self-enclosed, minimal)
- [ ] Confirm each archetypal function emits the expected APX instruction when compiled in isolation
- [ ] Compile archetypes at O0, O1, O2, O3 — document where each instruction first appears/disappears

### Phase 2 — CSmith Pipeline (Weeks 2–3)
**Goal**: Test whether surrounding program context prevents APX instruction emission.

- [ ] Set up CSmith integration (generate random C programs)
- [ ] Build insertion mechanism: splice archetypal functions into CSmith-generated programs
- [ ] Compile each combined program at O2 with and without `-mapxf`
- [ ] Scan assembly output for presence/absence of target APX instructions
- [ ] Record pass/fail rate per instruction across N generated programs
- [ ] Supplement with targeted contexts: hot loops, aliasing pointers, partial redundancies

### Phase 3 — Pass-Level Analysis (Weeks 3–4)
**Goal**: Identify which LLVM optimization passes break APX instruction patterns.

- [ ] For 3–5 interesting missed opportunities (from SPEC or CSmith), extract the function
- [ ] Compile in isolation (confirm instruction is emitted) vs in context (confirm it's missing)
- [ ] Use `-print-after-all` to dump IR after every pass in both cases
- [ ] Diff corresponding pass outputs to find the first point of divergence
- [ ] Document: which pass, what transformation, why the pattern was destroyed
- [ ] Compile at O0/O1/O2/O3 to isolate the optimization level responsible

### Phase 4 — GUI & Polish (Ongoing)
**Goal**: Build a macOS-native Swift GUI for controlling the analysis pipeline.

- [ ] Implement `APXCore` library with all analysis logic (compile, scan, diff, report)
- [ ] Wire up CLI subcommands (analyze, scan, batch, report)
- [ ] Build SwiftUI app target that drives the same `APXCore` logic
- [ ] Results display: table of instruction matches, pass diffs, summary stats

### Phase 5 — Writeup (Week 4+)
**Goal**: Produce a defensible graduate-level report.

- [ ] Introduction: ISA evolution vs compiler adoption lag
- [ ] Methodology: archetypal functions, SPEC analysis, CSmith experiments, pass identification
- [ ] Results: quantitative (instruction counts, pass/fail rates) and qualitative (case studies)
- [ ] Threats to validity: CSmith generates semantically meaningless code, cross-compilation differences, LLVM version specificity
- [ ] Conclusion: which instructions/patterns are robust, which are fragile, and why

## Project Structure

```
APX_Tester_2/
├── Package.swift
├── Sources/
│   ├── APXCore/            # Shared library — all analysis logic
│   │   ├── APXCore.swift
│   │   ├── APXInstruction.swift
│   │   ├── AssemblyAnalyzer.swift
│   │   └── CompilerDriver.swift
│   ├── APXTesterCLI/       # CLI executable (what gets submitted)
│   │   └── Main.swift
│   └── APXTesterApp/       # macOS SwiftUI app (personal use)
├── Tests/
│   └── APXCoreTests/
│       └── AssemblyAnalyzerTests.swift
├── PROJECT_PLAN.md         # This file
└── .gitignore
```

## Key Decisions

- LLVM only (no GCC) — allows deeper pass-level analysis with LLVM infrastructure
- NDD forms excluded — register allocation story, not instruction selection
- CSmith + SPEC together provide both experimental control and ecological validity
- CLI is the submittable artifact; GUI is a personal tool built on the same core
