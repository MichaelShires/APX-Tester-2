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

**Open question**: Does LLVM lack CFCMOV support entirely, or does it deliberately prefer NDD CMOV? This warrants investigation of the LLVM source (instruction selection patterns for APX).

**Decision**: Pivot to studying **NDD CMOV** as our third instruction category, while documenting the CFCMOV absence as a finding. The NDD form is what LLVM actually uses in practice.

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

| Instruction | Emitted at O2? | Pattern recognized? | Notes |
|---|---|---|---|
| CCMP | Yes (5/5 compound conditionals) | Yes | Robust for uniform compound conditionals |
| CFCMOV | **No** | N/A | LLVM prefers NDD CMOV instead |
| NDD CMOV | Yes (4 instances) | Yes | Used in place of CFCMOV |
| PUSH2/POP2 | Yes (where applicable) | Partial | Requires call boundary; optimization can eliminate opportunities |

### Next Steps
- [ ] Investigate LLVM source to determine if CFCMOV is unimplemented or intentionally avoided
- [ ] Compile archetypes at O0, O1, O3 to track where instructions appear/disappear
- [ ] Begin SPEC assembly diffing for real-world instruction counts
- [ ] Set up CSmith pipeline for context-dependent testing
