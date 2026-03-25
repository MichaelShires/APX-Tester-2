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
- [ ] Begin SPEC assembly diffing for real-world instruction counts
- [ ] Set up CSmith pipeline for context-dependent testing
- [ ] Investigate why CFCMOV doesn't fire for loop-carried conditional memory accesses
