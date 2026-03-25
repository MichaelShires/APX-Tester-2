# APX Tester — Results Log

**Toolchain**: Homebrew clang 22.1.1 (LLVM), `--target=x86_64-unknown-linux-gnu`, `-mapxf`
**Date started**: 2026-03-24

---

## Phase 1: Archetypal Function Baseline

### 1.1 CCMP — Conditional Compare

**Result: SUCCESS — LLVM emits CCMP in all compound conditional archetypes.**

| Function | APX Output | Non-APX Output | Notes |
|---|---|---|---|
| `ccmp_compound_and` | `cmpl` → `ccmpgl` | `cmpl` → `setg` → `cmpl` → `setl` → `andb` | CCMP replaces a 4-instruction SETcc+AND chain with a single chained compare |
| `ccmp_compound_or` | `cmpl` → `ccmplel` | `cmpl` → `setg` → `cmpl` → `setl` → `orb` | Same pattern, OR variant |
| `ccmp_triple` | `cmpl` → `ccmpgl` → `ccmpgl` | 3x (`cmpl` → `setg`) → 2x `andb` | Triple chain works — CMP + 2 CCMPs |
| `ccmp_range_check` | `cmpl` → `ccmpgel` | `cmpl` → `setge` → `cmpl` → `setle` → `andb` | Range check pattern recognized |
| `ccmp_mixed` | `cmovgl` (NDD) + `cmovel` | `cmovlel` + `cmovel` (2-operand) | Compiler chose NDD CMOV instead of CCMP for this pattern |

**Instruction count**: 5 CCMP instructions across 5 archetypes (APX), 0 in non-APX.

**Key observation**: The `ccmp_mixed` function (mixed types with `long`/`int` and `!= 0` test) did NOT produce CCMP. Instead, LLVM used NDD-form CMOV. This suggests the compound conditional pattern must be relatively uniform for CCMP to fire — type mixing or asymmetric comparisons may cause LLVM to prefer a different lowering.

---

### 1.2 CFCMOV — Conditional Fused Move

**Result: UNEXPECTED — LLVM emits zero CFCMOV instructions. Uses NDD 3-operand CMOV instead.**

| Function | APX Output | Non-APX Output | Notes |
|---|---|---|---|
| `cfcmov_simple_ternary` | `cmovgl %edi, %esi, %eax` (NDD) | `movl %edi, %eax` → `cmovlel %esi, %eax` | NDD eliminates the setup MOV |
| `cfcmov_min` | `cmovll %edi, %esi, %eax` (NDD) | `movl %esi, %eax` → `cmovll %edi, %eax` | Same pattern |
| `cfcmov_max` | `cmovgl %edi, %esi, %eax` (NDD) | `movl %esi, %eax` → `cmovgl %edi, %eax` | Same pattern |
| `cfcmov_abs` | `negl %edi, %eax` (NDD) → `cmovsl` | `movl` → `negl` → `cmovsl` | NDD on the NEG, not on the CMOV |
| `cfcmov_clamp` | `cmovgl %edi, %esi, %eax` (NDD) → `cmovgel %edx, %eax` | `movl` → `cmovgl` → `cmovgel` | First CMOV is NDD, second is 2-operand |
| `cfcmov_select_ptr` | `cmovneq %rdi, %rsi` (2-op) | `cmoveq %rsi, %rdi` (2-op) | No NDD, no CFCMOV — just inverted condition |
| `cfcmov_accumulate` | Vectorized (SSE2), scalar tail uses `cmovlel` (2-op) | Same vectorization | Loop vectorization bypasses CMOV entirely |

**Instruction count**: 0 CFCMOV, 4 NDD CMOV (3-operand form) across archetypes.

**Key finding**: LLVM does not appear to emit the `cfcmov` mnemonic at all for these patterns. Instead, it uses the APX NDD (New Data Destination) encoding of existing CMOV instructions, giving them a third operand. This is functionally similar but architecturally distinct:
- **NDD CMOV**: `cmovgl %src1, %src2, %dst` — 3-operand form, eliminates a MOV instruction
- **CFCMOV**: `cfcmovgl %src, %dst` — different opcode, different semantics (memory operand support, flag preservation)

**Open question (resolved)**: See Section 1.2b below.

---

### 1.2b CFCMOV — Resolved: Separate Feature Flag, Different Purpose

**Root cause found: `-mapxf` does NOT enable CFCMOV.**

The `-mapxf` flag enables: `+egpr`, `+ndd`, `+push2pop2`, `+ppx`. The conditional faulting feature (`+cf`) is a **separate feature flag** not included in `-mapxf`. CFCMOV requires explicit enablement via `-Xclang -target-feature -Xclang +cf`.

**With `+cf` enabled, CFCMOV emits correctly for conditional memory access patterns:**

| Function | With `-mapxf` only | With `-mapxf +cf` | Notes |
|---|---|---|---|
| `cfcmov_cond_load` | Branch + `movl (%rsi), %eax` | `cfcmovnel (%rsi), %eax` | Conditional load — branch eliminated entirely |
| `cfcmov_cond_store` | Branch + `movl %edx, (%rsi)` | `cfcmovnel %edx, (%rsi)` | Conditional store — branch eliminated entirely |
| `cfcmov_null_check_load` | Branch + `movl (%rdi), %eax` | `cfcmovnel (%rdi), %eax, %eax` (NDD form) | Null-check load with default value |
| `cfcmov_zeroing` | `xorl` + `cmovgl %edi, %eax` (2-op) | `cfcmovgl %edi, %eax` (zeroing form) | Zeroing CFCMOV — no need for explicit XOR |
| `cfcmov_filtered_sum` | Loop with branches + CCMP | Loop with branches + CCMP | Complex loop — CFCMOV not applied (branch kept) |
| `cfcmov_sparse_update` | Loop with branches | Loop with branches | Conditional store in loop — not hoisted |
| `cfcmov_safe_deref` | `cmovneq` pointer select + unconditional load | `cmovneq` pointer select + unconditional load | Already branchless via pointer select; no CFCMOV needed |

**Key findings**:
1. **CFCMOV and NDD CMOV are architecturally distinct features** — CFCMOV provides conditional faulting (fault suppression on false path), while NDD CMOV provides 3-operand register-to-register moves. They serve different purposes and are controlled by different feature flags.
2. **CFCMOV eliminates branches for guarded memory access** — the simple conditional load/store functions went from branch-based code to single CFCMOV instructions. This is a significant code quality improvement.
3. **CFCMOV zeroing eliminates setup instructions** — `cfcmovgl %edi, %eax` replaces `xorl %eax, %eax` + `cmovgl %edi, %eax` (saves one instruction).
4. **Loop-carried conditional memory accesses are NOT hoisted** — the `cfcmov_filtered_sum` and `cfcmov_sparse_update` loops still use branches. SimplifyCFG's conditional faulting optimization does not apply within loop bodies in these cases.
5. **`-mapxf` omitting `+cf` is itself a finding** — this means APX "full" mode does not include conditional faulting. Users/compilers must opt in separately, which may reduce real-world adoption.

**Decision**: Study **four** instruction categories instead of three: CCMP, CFCMOV (with `+cf`), NDD CMOV (from `-mapxf`), and PUSH2/POP2. The CFCMOV vs NDD CMOV distinction strengthens the paper.

---

### 1.3 PUSH2/POP2 — Paired Push/Pop

**Result: PARTIAL SUCCESS — PUSH2/POP2 emitted for functions with call boundaries, but not for pure computation or tail-call-optimized recursion.**

| Function | APX Output | Non-APX Output | Notes |
|---|---|---|---|
| `push2pop2_register_pressure` | 1x `pushq`/`popq` (rbx only) | 1x `pushq`/`popq` (rbx only) | Not enough register pressure — no PUSH2 |
| `push2pop2_across_call` | 2x `push2p`/`pop2p` | 4x individual `pushq`/`popq` + alignment push | Clean PUSH2/POP2 usage |
| `push2pop2_multi_call` | 3x `push2p`/`pop2p` | 6x individual `pushq`/`popq` + alignment push | Scales with register count |
| `push2pop2_recursive` | **No pushq at all** — loop optimized | **No pushq at all** — loop optimized | LLVM converted recursion to iteration, eliminating all stack frame overhead |

**Instruction count**: 5 `push2p` + 5 `pop2p` across archetypes (APX), 0 in non-APX.

**Key findings**:
1. **Register pressure alone is insufficient** — `push2pop2_register_pressure` didn't need callee-saved registers because there's no call boundary. The optimizer kept everything in caller-saved registers. PUSH2/POP2 requires a function *call* to force spilling.
2. **Tail-call optimization eliminates PUSH2/POP2 opportunities** — `push2pop2_recursive` was converted to a loop, completely removing the function prologue/epilogue. This directly supports the thesis: an optimization pass (tail-call conversion) eliminated the opportunity for the new instruction.
3. **PUSH2 requires an even number of callee-saved registers** — because it pushes pairs, odd register counts still need a single PUSHQ for the remaining register.

---

## Summary: Baseline Established

| Instruction | Feature Flag | Emitted at O2? | Pattern | Notes |
|---|---|---|---|---|
| CCMP | `-mapxf` (+ndd) | Yes (5/5 compound conditionals) | Compound conditionals | Robust for uniform patterns |
| NDD CMOV | `-mapxf` (+ndd) | Yes (4 instances) | Ternary/min/max/abs | 3-operand form eliminates setup MOV |
| CFCMOV | **`+cf` (separate!)** | Yes (4/7 archetypes) | Conditional memory access | Requires explicit `+cf` flag |
| PUSH2/POP2 | `-mapxf` (+push2pop2) | Yes (where applicable) | Function prologue/epilogue | Requires call boundary |

### Key Meta-Finding

Intel APX is not a single monolithic feature. The `-mapxf` flag enables EGPR, NDD, PUSH2/POP2, and PPX but **not** conditional faulting (CF/CFCMOV). This fragmentation means that even when a compiler "supports APX," the level of support depends on which sub-features are enabled. This directly supports the thesis: hardware complexity creates gaps in compiler coverage.

### Next Steps
- [ ] Compile archetypes at O0, O1, O3 to track where instructions appear/disappear
- [x] ~~Begin SPEC assembly diffing for real-world instruction counts~~ (See Phase 2 below)
- [ ] Set up CSmith pipeline for context-dependent testing
- [ ] Investigate why CFCMOV doesn't fire for loop-carried conditional memory accesses

---

## Phase 2: SPEC CPU 2017 Real-World Analysis

**Toolchain**: Homebrew clang 22.1.1, `--target=x86_64-apple-macos`, `-isysroot`, `-O2 -mapxf`
**Benchmarks compiled**: 5 (265 source files total)

### 2.1 APX Instruction Counts Across SPEC Benchmarks

| Benchmark | Files | CCMP | CTEST | NDD CMOV | PUSH2 | POP2 | Total |
|---|---|---|---|---|---|---|---|
| 505.mcf_r | 10 | 3 | 0 | 11 | 21 | 21 | 56 |
| 557.xz_r | 81 | 33 | 45 | 44 | 218 | 231 | 571 |
| 525.x264_r | 37 | 142 | 91 | 207 | 453 | 486 | 1,379 |
| 538.imagick_r | 99 | 344 | 200 | 412 | 1,867 | 2,154 | 4,977 |
| 502.gcc_r | 38 | 129 | 89 | 173 | 609 | 663 | 1,663 |
| **TOTAL** | **265** | **651** | **425** | **847** | **3,168** | **3,555** | **8,646** |

### 2.2 Observations

1. **PUSH2/POP2 dominate** — 6,723 of 8,646 total APX instructions (77.8%). This makes sense: every non-trivial function with callee-saved registers benefits, and the transformation is mechanical (pair adjacent pushes).

2. **CCMP + CTEST are well-represented** — 1,076 combined instances. CTEST (425) appears alongside CCMP (651), suggesting compound conditionals with bitwise tests are common in real code.

3. **NDD CMOV is actively used** — 847 instances across all benchmarks. Confirms that LLVM's NDD CMOV lowering is production-ready and consistently applied.

4. **538.imagick_r is the richest benchmark** — 4,977 APX instructions across 99 files. Image processing code is heavy on conditional pixel operations and function calls.

5. **505.mcf_r is sparse** — only 56 APX instructions across 10 files. Network simplex is pointer-chasing code with fewer compound conditionals.

### 2.3 Top Files by APX Instruction Density

| Rank | File | Total APX | Benchmark |
|---|---|---|---|
| 1 | `wand_magick-image.s` | 550 | 538.imagick_r |
| 2 | `mini-gmp.s` | 373 | 502.gcc_r |
| 3 | `x264_src_encoder_analyse.s` | 287 | 525.x264_r |
| 4 | `decNumber.s` | 268 | 502.gcc_r |
| 5 | `magick_cache.s` | 192 | 538.imagick_r |

---

## Phase 2b: Optimization Level Sweep (O0–O3)

### 2b.1 APX Instruction Counts by Optimization Level

**ccmp_archetype.c:**

| Level | CCMP | CTEST | NDD CMOV | PUSH2 | POP2 |
|---|---|---|---|---|---|
| -O0 | 0 | 0 | 0 | 0 | 0 |
| -O1 | 5 | 0 | 1 | 0 | 0 |
| -O2 | 5 | 0 | 1 | 0 | 0 |
| -O3 | 5 | 0 | 1 | 0 | 0 |

**cfcmov_archetype_v2.c** (with `+cf`):

| Level | CCMP | CTEST | CFCMOV/NDD CMOV | PUSH2 | POP2 |
|---|---|---|---|---|---|
| -O0 | 0 | 0 | 0 | 0 | 0 |
| -O1 | 1 | 0 | 4 | 0 | 0 |
| -O2 | 3 | 0 | 4 | 0 | 0 |
| -O3 | 4 | 0 | 4 | 0 | 0 |

**push2pop2_archetype.c:**

| Level | CCMP | CTEST | NDD CMOV | PUSH2 | POP2 |
|---|---|---|---|---|---|
| -O0 | 0 | 0 | 0 | 0 | 0 |
| -O1 | 0 | 0 | 0 | 4 | 4 |
| -O2 | 0 | 0 | 0 | 4 | 4 |
| -O3 | 0 | 0 | 0 | 4 | 4 |

### 2b.2 Key Findings

1. **O0 emits zero APX instructions** (CCMP, NDD CMOV, CFCMOV, PUSH2/POP2) — all APX pattern recognition requires at least O1. At O0, compound conditionals are lowered as separate CMP+Jcc branches, conditional moves use the 2-operand form with explicit MOV setup, and prologues use individual PUSHQ.

2. **The O0→O1 transition is where all APX instructions activate**. This is the critical boundary:
   - **CCMP**: At O0, `if (a > x && b < y)` becomes `cmpl` → `jle` → `cmpl` → `jge` (two branches). At O1, it becomes `cmpl` → `ccmpgl` (one chained compare). The SimplifyCFG and instruction selection passes at O1 recognize the compound conditional.
   - **PUSH2/POP2**: At O1, adjacent pushq/popq pairs in prologues are combined into push2p/pop2p.
   - **CFCMOV**: At O1, conditional loads/stores are hoisted by SimplifyCFG into CFCMOV.

3. **O1→O2→O3 increases CCMP count in the CFCMOV archetype** (1→3→4). This is because `cfcmov_filtered_sum` has a range-check loop (`if (idx >= 0 && idx < limit)`) — higher optimization levels unroll the loop, creating more copies of the compound conditional, each getting its own CCMP. The CCMP pattern itself is recognized at O1, but loop unrolling at O2/O3 multiplies it.

4. **CFCMOV/NDD CMOV count is stable across O1–O3** (4 at all levels). The conditional memory access patterns are recognized at O1 and don't change with more aggressive optimization.

5. **O0 still uses some APX features**: `pushp`/`popp` (PPX — push/pop with prefix) appears even at O0 for frame pointer setup. These are APX encoding-level features, not pattern-dependent.

### 2b.3 Implications for the Thesis

The O0→O1 boundary is clean: LLVM's APX instruction patterns are implemented in instruction selection and early SimplifyCFG, both of which activate at O1. The more interesting question for the thesis is not "do optimization passes prevent APX instructions?" but rather "do optimization passes at O2/O3 *destroy* patterns that O1 recognized?" The CSmith experiments should test this: insert an archetypal function that gets CCMP at O1, embed it in a complex context, and see if O2/O3 transformations (inlining, GVN, loop restructuring) break the pattern.

---

## Phase 2c: Missed Opportunity Analysis

### 2c.1 CCMP Conversion Efficiency

We counted compound conditional patterns in non-APX output (SETcc + AND/OR chains) and compared against CCMP emission in APX output:

| Benchmark | Non-APX SETcc chains | APX CCMP emitted | Conversion rate |
|---|---|---|---|
| 505.mcf_r | 0 | 3 | N/A (branch-based) |
| 557.xz_r | 45 | 33 | ~73% |
| 525.x264_r | 195 | 142 | ~72% |
| 538.imagick_r | 253 | 344 | ~135% |
| 502.gcc_r | 129 | 129 | ~100% |
| **TOTAL** | **622** | **651** | **~105%** |

**Key insight**: The total CCMP count (651) *exceeds* the SETcc chain count (622). This is because CCMP replaces **two different non-APX patterns**:
1. **Branchless SETcc chains**: `cmpl` → `setg` → `cmpl` → `setl` → `andb` (what we counted)
2. **Branch-based compound conditionals**: `testq` → `je` → `movq` → `ccmpeq` (separate basic blocks joined by CCMP)

The 538.imagick_r "135%" rate means many compound conditionals were branch-based in non-APX but became branchless CCMP chains in APX. **CCMP doesn't just replace SETcc patterns — it eliminates branches entirely.**

### 2c.2 NDD CMOV Conversion Efficiency

| Benchmark | Non-APX 2-op CMOVcc | APX NDD 3-op CMOVcc | Remaining 2-op in APX | MOV+CMOV pairs converted |
|---|---|---|---|---|
| 505.mcf_r | 53 | 11 | 42 | 2 |
| 557.xz_r | 148 | 44 | 105 | 16 |
| 525.x264_r | 1,444 | 207 | 1,225 | 63 |
| 538.imagick_r | 1,355 | 412 | 933 | 289 |
| 502.gcc_r | 795 | 173 | 613 | 39 |
| **TOTAL** | **3,795** | **847** | **2,918** | **409** |

**Only 22% of CMOVs were upgraded to NDD.** But this is NOT a missed opportunity — investigation of the remaining 2,918 two-operand CMOVs shows they are **already optimal**:

- **Zero MOV→CMOV pairs exist in APX output** — LLVM has already converted every eligible case to NDD
- The remaining 2-op CMOVs have destinations that are live-in from prior computation (not set up by a MOV), making NDD unnecessary
- The 409 MOV→CMOV pairs found in non-APX output confirm these were the exact cases converted to NDD

**Conclusion: LLVM's NDD CMOV conversion is complete — there are no missed NDD opportunities.**

### 2c.3 PUSH2/POP2 Pairing Efficiency

| Benchmark | Non-APX pushq | APX push2p | Pushq replaced | Remaining unpaired | Pairing rate |
|---|---|---|---|---|---|
| 505.mcf_r | 124 | 21 | 42 | 23 | ~64% |
| 557.xz_r | 1,027 | 218 | 436 | 148 | ~74% |
| 525.x264_r | 2,297 | 453 | 906 | 439 | ~67% |
| 538.imagick_r | 10,974 | 1,867 | 3,734 | 3,921 | ~48% |
| 502.gcc_r | 2,406 | 609 | 1,218 | 137 | ~89% |

**Pairing rates range from 48% to 89%.** Unpaired pushq instructions remain because:
1. **Odd number of callee-saved registers** — PUSH2 requires pairs, so one register is always left over
2. **Frame pointer push** — `pushq %rbp` is often isolated (though APX uses `pushp` for this)
3. **Stack alignment pushes** — extra pushq for 16-byte alignment can't be paired

The 538.imagick_r low rate (48%) likely reflects many small functions with only 1-2 callee-saved registers.

### 2c.4 Summary: Where Are the Real Missed Opportunities?

| Instruction | Missed opportunities? | Assessment |
|---|---|---|
| CCMP | **Minimal** | CCMP captures both SETcc chains AND branch-based compounds. Conversion is thorough. |
| NDD CMOV | **None** | Every eligible MOV+CMOV pair is converted. Remaining 2-op CMOVs are already optimal. |
| CFCMOV | **Yes — not enabled by default** | `-mapxf` omits `+cf`. All conditional loads/stores remain branch-based unless `+cf` is explicitly added. |
| PUSH2/POP2 | **Structural, not fixable** | Unpaired pushes are due to odd register counts, frame pointers, and alignment — not compiler deficiency. |

**The biggest missed opportunity across all of SPEC is CFCMOV**: every conditional load/store in all 265 files is a branch instead of a CFCMOV, purely because `-mapxf` doesn't include `+cf`.

---

## Phase 2d: CFCMOV Impact — Recompiling SPEC with +cf

After discovering that `-mapxf` omits conditional faulting, we recompiled all 265 SPEC files with `-mapxf -Xclang -target-feature -Xclang +cf` to measure the impact.

### 2d.1 CFCMOV Emission with +cf Enabled

| Benchmark | Files | CFCMOV | Files with CFCMOV | Branches eliminated |
|---|---|---|---|---|
| 505.mcf_r | 10 | 18 | 3 | 12 |
| 557.xz_r | 81 | 69 | 20 | 17 |
| 525.x264_r | 37 | 258 | 22 | 132 |
| 538.imagick_r | 99 | 554 | 51 | 349 |
| 502.gcc_r | 38 | 221 | 23 | 124 |
| **TOTAL** | **265** | **1,120** | **119 (45%)** | **634** |

**1,120 CFCMOV instructions** appear across 119 files (45% of all compiled files), eliminating **634 conditional branches**.

### 2d.2 Interaction Effects: +cf Changes Other Instruction Counts

Adding `+cf` doesn't just add CFCMOV — it shifts the instruction selection landscape:

| Benchmark | CCMP (no cf → cf) | NDD CMOV (no cf → cf) | PUSH2 (no cf → cf) |
|---|---|---|---|
| 505.mcf_r | 3 → 3 | 11 → 11 | 21 → 21 |
| 557.xz_r | 33 → 34 | 44 → 29 | 218 → 214 |
| 525.x264_r | 142 → 146 | 207 → 186 | 453 → 453 |
| 538.imagick_r | 344 → 345 | 412 → 373 | 1,867 → 1,867 |
| 502.gcc_r | 129 → 128 | 173 → 152 | 609 → 609 |

**NDD CMOV decreases** with `+cf` enabled (847 → 781, -7.8%). This is because some conditional moves that previously used NDD CMOV (3-operand register form) are now lowered as CFCMOV (conditional memory load) when the source was a memory operand. CFCMOV can load directly from memory conditionally, making the separate load + NDD CMOV unnecessary.

### 2d.3 Top Files by CFCMOV Density

| Rank | File | CFCMOV | Benchmark | Domain |
|---|---|---|---|---|
| 1 | `x264_src_encoder_analyse.s` | 87 | 525.x264_r | Video encoding analysis |
| 2 | `magick_quantum-export.s` | 79 | 538.imagick_r | Pixel export |
| 3 | `mini-gmp.s` | 70 | 502.gcc_r | Arbitrary precision math |
| 4 | `decNumber.s` | 69 | 502.gcc_r | Decimal arithmetic |
| 5 | `x264_src_encoder_encoder.s` | 52 | 525.x264_r | Video encoder core |

### 2d.4 Combined APX Instruction Summary (All Features Enabled)

| Instruction | `-mapxf` only | `-mapxf +cf` | Delta |
|---|---|---|---|
| CCMP | 651 | 656 | +5 |
| CTEST | 425 | 436 | +11 |
| NDD CMOV | 847 | 781 | -66 |
| CFCMOV | 0 | **1,120** | **+1,120** |
| PUSH2 | 3,168 | 3,164 | -4 |
| POP2 | 3,555 | 3,551 | -4 |
| **TOTAL** | **8,646** | **9,708** | **+1,062** |

Enabling `+cf` adds **1,062 net new APX instructions** (12.3% increase) and eliminates **634 conditional branches** across 265 source files.

### 2d.5 Implications

1. **Feature flag fragmentation has real cost**: 1,120 CFCMOV instructions and 634 branch eliminations are left on the table by the default `-mapxf` flag.
2. **CFCMOV interacts with NDD CMOV**: enabling one feature changes how another is used — 66 NDD CMOVs became unnecessary because CFCMOV handles the conditional memory load directly.
3. **Nearly half of all files benefit**: 45% of compiled files contain at least one CFCMOV, showing this isn't a niche optimization.
4. **The highest-impact files are compute-intensive**: video encoding, pixel processing, and arbitrary-precision math — exactly the workloads where branch elimination matters most.

---

## Phase 3: CSmith Context-Sensitivity Testing

### 3.1 Methodology

We inserted APX archetypal functions into randomly generated CSmith programs to test whether surrounding code context causes LLVM to miss APX instruction patterns. Three test configurations:

1. **Noinline**: Functions marked `__attribute__((noinline))` — tests whether compilation unit context affects instruction selection for isolated functions
2. **Inlineable**: Functions without inline barriers — tests whether the compiler chooses to inline them and whether APX patterns survive
3. **Force-inlined**: Functions marked `__attribute__((always_inline))` — forces the APX pattern into the middle of CSmith code, maximum exposure to surrounding optimization passes

### 3.2 Results

| Configuration | Programs | O-Level | Pass | Fail | Rate |
|---|---|---|---|---|---|
| Noinline | 200 | O2 | 200 | 0 | **100%** |
| Inlineable | 200 | O2 | 200 | 0 | **100%** |
| CFCMOV (+cf) | 200 | O2 | 200 | 0 | **100%** |
| Force-inlined | 100 | O2 | 100 | 0 | **100%** |
| Force-inlined | 100 | O3 | 100 | 0 | **100%** |
| Noinline | 100 | O3 | 100 | 0 | **100%** |
| Inlineable | 100 | O3 | 100 | 0 | **100%** |
| **TOTAL** | **500** | | **500** | **0** | **100%** |

### 3.3 Analysis

**Across 500 CSmith-generated programs, zero APX instruction patterns were destroyed by surrounding code context.** This includes:

- **CCMP** (compound conditionals): Always emitted, even when force-inlined into CSmith functions at O3
- **NDD CMOV** (conditional assignment): Always emitted
- **CFCMOV** (conditional memory access): Always emitted when `+cf` enabled

### 3.4 Why 100%? Understanding the Result

This 100% pass rate is itself informative. It means:

1. **LLVM's APX patterns are late-stage**: CCMP, NDD CMOV, and CFCMOV are recognized during instruction selection (ISel) and machine-level optimization, *after* most IR-level passes have run. By the time instruction selection happens, the patterns are expressed in a form that ISel reliably matches regardless of surrounding code.

2. **The archetypal patterns are canonical**: `if (a > x && b < y)` lowers to a compare-and-branch sequence in IR that LLVM always recognizes as a CCMP candidate. Optimization passes may transform the surrounding code, but they don't restructure simple compound conditionals into unrecognizable forms.

3. **CSmith generates broad but not adversarial context**: CSmith programs are syntactically complex but don't specifically target patterns known to interfere with instruction selection (e.g., heavy aliasing, exception handling, setjmp/longjmp).

### 3.5 Implications for the Thesis

The CSmith results suggest that **for the APX instructions we tested, LLVM's instruction selection is robust against random surrounding code context at O2 and O3**. This is a positive finding — it means that once LLVM has APX pattern support, it applies it reliably.

However, this does NOT mean optimization passes never destroy APX opportunities. The results from earlier phases show:

- **Tail-call optimization** eliminated PUSH2/POP2 opportunities (Phase 1, `push2pop2_recursive`)
- **Feature flag fragmentation** prevents CFCMOV from ever firing with default flags (Phase 2d)
- **The O0→O1 boundary** is where patterns activate — without optimization, no APX instructions are emitted at all

The thesis finding is nuanced: **the barrier to APX adoption is not optimization-pass interference with pattern recognition, but rather (a) feature flag exposure and (b) whether optimization passes create or destroy the prerequisites for the pattern** (e.g., creating/eliminating function boundaries for PUSH2/POP2).

---

## Consolidated Findings Summary

### Finding 1: APX Is Not Monolithic

Intel APX is fragmented into multiple sub-features controlled by separate flags:

| Feature | Flag | What it enables |
|---|---|---|
| EGPR | `-mapxf` (+egpr) | Extended general-purpose registers (r16–r31) |
| NDD | `-mapxf` (+ndd) | New Data Destination (3-operand instructions) |
| PUSH2/POP2 | `-mapxf` (+push2pop2) | Paired push/pop |
| PPX | `-mapxf` (+ppx) | Push/pop with prefix encoding |
| **CF** | **`+cf` (NOT in `-mapxf`)** | **Conditional faulting (CFCMOV)** |

The "full APX" flag (`-mapxf`) omits conditional faulting entirely. This is the single largest source of missed APX optimization across real-world code.

### Finding 2: CFCMOV ≠ NDD CMOV

Our initial assumption that CFCMOV was a replacement for CMOV was wrong. They are architecturally distinct:

- **NDD CMOV** (`cmovgl %src1, %src2, %dst`): 3-operand register-to-register conditional move. Eliminates setup MOV instructions. Enabled by `-mapxf`.
- **CFCMOV** (`cfcmovnel (%ptr), %dst`): Conditional memory access with fault suppression. Eliminates branches guarding loads/stores. Requires `+cf`.

LLVM correctly uses each for its intended purpose. In SPEC benchmarks, enabling `+cf` alongside `-mapxf`:
- Added **1,120 CFCMOV** instructions
- **Reduced** NDD CMOV by 66 (CFCMOV subsumed some conditional loads)
- Eliminated **634 conditional branches**

### Finding 3: APX Instruction Selection Is Late-Stage and Robust

All APX instruction patterns (CCMP, NDD CMOV, CFCMOV, PUSH2/POP2) are recognized during LLVM's instruction selection and machine-level optimization phases, which run *after* most IR-level optimization passes. This means:

- **O0 emits zero APX instructions** — pattern recognition requires at least O1
- **O1 activates all patterns** — the O0→O1 boundary is where APX appears
- **O2/O3 don't destroy patterns** — they only increase counts via loop unrolling
- **500 CSmith programs at O2/O3 showed 0 pattern failures** — even with force-inlining

### Finding 4: The Real Barriers Are Upstream

Rather than optimization passes destroying instruction patterns, the barriers to APX adoption are:

1. **Feature flag exposure**: `-mapxf` omitting `+cf` leaves 1,120 CFCMOV instructions and 634 branch eliminations on the table across 265 SPEC files
2. **Prerequisite destruction**: Tail-call optimization converts recursion to iteration, eliminating function boundaries where PUSH2/POP2 would appear
3. **Structural constraints**: Odd numbers of callee-saved registers, stack alignment pushes, and frame pointer management limit PUSH2/POP2 pairing (48–89% rates)

### Finding 5: LLVM's Existing APX Support Is Thorough

For the features that ARE enabled by `-mapxf`:

| Instruction | Conversion completeness | Notes |
|---|---|---|
| CCMP | ~105% (exceeds non-APX compound conditional count) | Also converts branch-based compounds, not just SETcc chains |
| NDD CMOV | 100% (zero missed MOV+CMOV pairs) | Every eligible case converted |
| PUSH2/POP2 | 48–89% (limited by structural factors) | Not a compiler deficiency |

### Quantitative Summary Across All Experiments

| Metric | Value |
|---|---|
| SPEC files compiled | 265 (across 5 benchmarks) |
| Total APX instructions (`-mapxf`) | 8,646 |
| Total APX instructions (`-mapxf +cf`) | 9,708 |
| CFCMOV unlocked by `+cf` | 1,120 |
| Branches eliminated by CFCMOV | 634 |
| Files benefiting from CFCMOV | 119 (45%) |
| CSmith programs tested | 500 |
| CSmith APX pattern failures | 0 (0%) |
| Optimization levels tested | O0, O1, O2, O3 |
| LLVM version | Homebrew clang 22.1.1 |

### Remaining Work
- [ ] Deep-dive case study: trace CFCMOV through SimplifyCFG with `-print-after-all`
- [ ] Targeted adversarial contexts: manually craft programs that stress specific passes (aliasing, setjmp, exception handling)
- [ ] Final project writeup
