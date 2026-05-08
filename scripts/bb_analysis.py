#!/usr/bin/env python3
"""
Basic block length analysis for APX vs non-APX SPEC assembly.

Theory: APX predication (CCMP, CFCMOV) reduces the absolute count of
conditional branches, lowering branch predictor pressure. APX instructions
are counted as weight-2 (they fuse two prior-gen instructions), letting us
measure "useful work done per branch".

NOTE on confounding factors:
  EGPR (r16-r31 extended GPRs) eliminates ~25-30% of register-to-register
  MOV instructions (spill/reload) independently of predication. This makes
  raw basic block lengths go DOWN with APX (fewer MOVs per block), which
  is the opposite of the predication prediction. To isolate predication,
  we report both raw and weighted metrics, plus absolute branch counts.

Counting rule:
  APX fused instructions (CCMP, CFCMOV, PUSH2/POP2, NDD 3-op CMOV) = weight 2
  All other instructions = weight 1

Basic block boundary detection uses LLVM's explicit labels (LBBx_y:) and
function entry labels. Terminators: jcc, jmp, ret, ud2.
"""

import re
import sys
import os
from pathlib import Path
from collections import defaultdict, Counter
from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------------------
# Instruction classification
# ---------------------------------------------------------------------------

APX_FUSED_PATTERNS = re.compile(r"""
    ^\s*(
        ccmp[a-z]* | ctest[a-z]* |       # CCMP/CTEST: fuses two compares
        cfcmov[a-z]* |                    # CFCMOV: fuses branch + mem access
        push2[a-z]* | pop2[a-z]*          # PUSH2/POP2: fuses two push/pop
    )\b
""", re.VERBOSE)

# Conditional branch mnemonics (distinct from jmp/ret)
COND_BRANCH = re.compile(r"""
    ^\s*
    j(?:e|ne|z|nz|l|le|g|ge|a|ae|b|be|s|ns|o|no|p|np|cxz|ecxz|rcxz)[qlw]?
    \b
""", re.VERBOSE)

UNCOND_BRANCH = re.compile(r'^\s*jmp[a-z]*\b')
RETURN = re.compile(r'^\s*ret[ql]?\b')
TERMINATOR = re.compile(r"""
    ^\s*(
        jmp[a-z]* |
        j(?:e|ne|z|nz|l|le|g|ge|a|ae|b|be|s|ns|o|no|p|np|cxz|ecxz|rcxz)[qlw]? |
        ret[ql]? |
        ud2 |
        loop[a-z]*
    )\b
""", re.VERBOSE)

SKIP_LINE = re.compile(r'^\s*$|^\s*##|^\s*\.')
DATA_PSEUDO = re.compile(r'^\s*\.(byte|long|quad|word|short|zero|ascii|asciz|space|fill)\b')
IS_INSTR = re.compile(r'^\s+[a-z]')
BB_LABEL = re.compile(r'^(L[A-Za-z0-9_]+|_?[A-Za-z_][A-Za-z0-9_.]*):')


def is_ndd_cmov(line: str) -> bool:
    m = re.match(r'^\s*(cmov[a-z]+)\s+(.+)', line)
    if not m:
        return False
    cleaned = re.sub(r'\([^)]*\)', '()', m.group(2))
    return cleaned.count(',') >= 2


def classify(line: str) -> tuple[int, str]:
    """
    Returns (weight, category) for a line.
    weight: 0=non-instruction, 1=normal, 2=APX-fused
    category: 'none', 'normal', 'apx', 'cond_branch', 'uncond_branch', 'ret'
    """
    if SKIP_LINE.match(line) or DATA_PSEUDO.match(line):
        return 0, 'none'
    if not IS_INSTR.match(line):
        return 0, 'none'

    if COND_BRANCH.match(line):
        return 1, 'cond_branch'
    if UNCOND_BRANCH.match(line):
        return 1, 'uncond_branch'
    if RETURN.match(line):
        return 1, 'ret'

    if APX_FUSED_PATTERNS.match(line):
        return 2, 'apx'
    if re.match(r'^\s*cmov[a-z]+\b', line) and is_ndd_cmov(line):
        return 2, 'apx'

    return 1, 'normal'


def is_label(line: str) -> bool:
    return bool(BB_LABEL.match(line.rstrip()))


# ---------------------------------------------------------------------------
# Per-file analysis
# ---------------------------------------------------------------------------

@dataclass
class BBStats:
    weight: int = 0
    raw_count: int = 0
    apx_count: int = 0
    cond_branches: int = 0


@dataclass
class FileStats:
    blocks: list = field(default_factory=list)    # list of BBStats
    total_instr: int = 0
    total_weight: int = 0
    total_cond_branches: int = 0
    total_uncond_branches: int = 0
    total_rets: int = 0
    total_apx: int = 0


def analyze_file(path: Path) -> FileStats:
    fstats = FileStats()
    current: Optional[BBStats] = None

    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.rstrip('\n')

            if is_label(line):
                if current is not None and current.raw_count > 0:
                    fstats.blocks.append(current)
                current = BBStats()
                continue

            if current is None:
                current = BBStats()

            w, cat = classify(line)
            if w == 0:
                continue

            fstats.total_instr += 1
            fstats.total_weight += w
            current.raw_count += 1
            current.weight += w

            if cat == 'apx':
                current.apx_count += 1
                fstats.total_apx += 1
            elif cat == 'cond_branch':
                current.cond_branches += 1
                fstats.total_cond_branches += 1
            elif cat == 'uncond_branch':
                fstats.total_uncond_branches += 1
            elif cat == 'ret':
                fstats.total_rets += 1

            if TERMINATOR.match(line):
                if current.raw_count > 0:
                    fstats.blocks.append(current)
                current = None

    if current is not None and current.raw_count > 0:
        fstats.blocks.append(current)

    return fstats


# ---------------------------------------------------------------------------
# Benchmark-level aggregation
# ---------------------------------------------------------------------------

@dataclass
class BenchStats:
    name: str
    variant: str
    total_blocks: int = 0
    total_weight: int = 0
    total_raw: int = 0
    total_apx: int = 0
    total_cond_branches: int = 0
    total_uncond_branches: int = 0
    total_rets: int = 0
    block_weights: list = field(default_factory=list)

    @property
    def avg_weight(self) -> float:
        return self.total_weight / self.total_blocks if self.total_blocks else 0

    @property
    def avg_raw(self) -> float:
        return self.total_raw / self.total_blocks if self.total_blocks else 0

    @property
    def total_branches(self) -> int:
        return self.total_cond_branches + self.total_uncond_branches + self.total_rets

    @property
    def weight_per_branch(self) -> float:
        return self.total_weight / self.total_cond_branches if self.total_cond_branches else 0

    @property
    def apx_pct(self) -> float:
        return self.total_apx / self.total_raw * 100 if self.total_raw else 0


def percentile(data: list, p: float) -> float:
    if not data:
        return 0.0
    s = sorted(data)
    idx = (len(s) - 1) * p / 100
    lo, hi = int(idx), min(int(idx) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (idx - lo)


def analyze_benchmark(bench_dir: Path, variant: str) -> BenchStats:
    variant_dir = bench_dir / variant
    stats = BenchStats(name=bench_dir.name, variant=variant)
    for asm_file in variant_dir.glob('*.s'):
        fstats = analyze_file(asm_file)
        stats.total_raw += fstats.total_instr
        stats.total_weight += fstats.total_weight
        stats.total_apx += fstats.total_apx
        stats.total_cond_branches += fstats.total_cond_branches
        stats.total_uncond_branches += fstats.total_uncond_branches
        stats.total_rets += fstats.total_rets
        for b in fstats.blocks:
            stats.total_blocks += 1
            stats.block_weights.append(b.weight)
    return stats


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

VARIANT_LABELS = {'noapx': 'No APX', 'apx': 'APX (-mapxf)', 'apx_cf': 'APX+CF'}
VARIANTS = ['noapx', 'apx', 'apx_cf']


def print_report(all_stats: dict):
    benchmarks = sorted(all_stats.keys())

    print("=" * 90)
    print("BASIC BLOCK & BRANCH ANALYSIS: APX vs NON-APX")
    print("=" * 90)
    print()
    print("METHODOLOGY NOTE:")
    print("  APX fused instructions (CCMP, CFCMOV, PUSH2/POP2, NDD CMOV) count as weight 2.")
    print("  EGPR (16 extra registers) independently reduces MOV instructions by ~25-30%,")
    print("  which confounds raw block-length comparisons. The key predication metric is")
    print("  'weighted work per conditional branch' — how much semantic work happens between")
    print("  conditional branches, counting APX instructions as double.")
    print()

    # --- Table 1: Block count and average length ---
    print("TABLE 1: BASIC BLOCK COUNTS AND AVERAGE LENGTH")
    print("-" * 90)
    print(f"{'Benchmark':<18} {'Variant':<14} {'Blocks':>8} {'AvgRaw':>8} {'AvgWt':>8} "
          f"{'APX%':>6}  {'p50Wt':>6} {'p90Wt':>6}")
    print("-" * 90)
    for bench in benchmarks:
        for i, v in enumerate(VARIANTS):
            s = all_stats[bench].get(v)
            if not s or s.total_blocks == 0: continue
            p50 = percentile(s.block_weights, 50)
            p90 = percentile(s.block_weights, 90)
            print(f"{bench if i==0 else '':<18} {VARIANT_LABELS[v]:<14} "
                  f"{s.total_blocks:>8,} {s.avg_raw:>8.2f} {s.avg_weight:>8.2f} "
                  f"{s.apx_pct:>5.1f}%  {p50:>6.1f} {p90:>6.1f}")
        print()

    # --- Table 2: Branch counts (the predication story) ---
    print("TABLE 2: CONDITIONAL BRANCH COUNTS — THE PREDICATION STORY")
    print("  (CCMP and CFCMOV eliminate conditional branches; fewer branches = less BP pressure)")
    print("-" * 90)
    print(f"{'Benchmark':<18} {'Variant':<14} {'CondBr':>8} {'Total Instr':>12} "
          f"{'CondBr%':>8} {'WtPerCondBr':>12}")
    print("-" * 90)

    for bench in benchmarks:
        no = all_stats[bench].get('noapx')
        for i, v in enumerate(VARIANTS):
            s = all_stats[bench].get(v)
            if not s or s.total_raw == 0: continue
            br_pct = s.total_cond_branches / s.total_raw * 100
            delta = ''
            if v != 'noapx' and no:
                d = s.total_cond_branches - no.total_cond_branches
                delta = f" ({d:+,})"
            print(f"{bench if i==0 else '':<18} {VARIANT_LABELS[v]:<14} "
                  f"{s.total_cond_branches:>8,}{delta:<10} {s.total_raw:>8,}     "
                  f"{br_pct:>6.1f}%  {s.weight_per_branch:>10.2f}")
        print()

    # --- Table 3: Aggregate summary ---
    print("TABLE 3: AGGREGATE ACROSS ALL BENCHMARKS")
    print("-" * 90)
    agg = {}
    for v in VARIANTS:
        c = BenchStats(name='ALL', variant=v)
        for bench in benchmarks:
            s = all_stats[bench].get(v)
            if not s: continue
            c.total_blocks += s.total_blocks
            c.total_weight += s.total_weight
            c.total_raw += s.total_raw
            c.total_apx += s.total_apx
            c.total_cond_branches += s.total_cond_branches
            c.total_uncond_branches += s.total_uncond_branches
            c.total_rets += s.total_rets
            c.block_weights.extend(s.block_weights)
        agg[v] = c

    no = agg['noapx']
    print(f"{'Variant':<14} {'CondBr':>8} {'BrDelta':>8} {'TotalInstr':>11} "
          f"{'InstrDelta':>11} {'WtPerCondBr':>12} {'WpBDelta':>9}")
    print("-" * 90)
    for v in VARIANTS:
        s = agg[v]
        br_delta = f"{s.total_cond_branches - no.total_cond_branches:+,}" if v != 'noapx' else '—'
        instr_delta = f"{s.total_raw - no.total_raw:+,}" if v != 'noapx' else '—'
        wpb_delta = f"{s.weight_per_branch - no.weight_per_branch:+.3f}" if v != 'noapx' else '—'
        print(f"{VARIANT_LABELS[v]:<14} {s.total_cond_branches:>8,} {br_delta:>8}  "
              f"{s.total_raw:>10,} {instr_delta:>11}  "
              f"{s.weight_per_branch:>11.3f} {wpb_delta:>9}")

    print()
    print("TABLE 4: WEIGHT-PER-CONDITIONAL-BRANCH LIFT (APX predication effect in isolation)")
    print("  AvgWt / CondBr = how much weighted work is done per conditional branch.")
    print("  This metric rises when predication fuses instructions AND eliminates branches.")
    print("-" * 90)
    print(f"{'Benchmark':<18}  {'NoAPX WpCB':>11}  {'APX WpCB':>10}  {'APX+CF WpCB':>12}  "
          f"{'APX lift':>9}  {'APX+CF lift':>12}")
    print("-" * 90)
    for bench in benchmarks:
        no = all_stats[bench].get('noapx')
        ap = all_stats[bench].get('apx')
        cf = all_stats[bench].get('apx_cf')
        if not no or no.weight_per_branch == 0: continue
        ap_lift = (ap.weight_per_branch / no.weight_per_branch - 1) * 100 if ap else 0
        cf_lift = (cf.weight_per_branch / no.weight_per_branch - 1) * 100 if cf else 0
        print(f"{bench:<18}  {no.weight_per_branch:>11.3f}  "
              f"{ap.weight_per_branch if ap else 0:>10.3f}  "
              f"{cf.weight_per_branch if cf else 0:>12.3f}  "
              f"{ap_lift:>+8.1f}%  {cf_lift:>+11.1f}%")

    no_a = agg['noapx']
    ap_a = agg['apx']
    cf_a = agg['apx_cf']
    ap_lift = (ap_a.weight_per_branch / no_a.weight_per_branch - 1) * 100
    cf_lift = (cf_a.weight_per_branch / no_a.weight_per_branch - 1) * 100
    print("-" * 90)
    print(f"{'ALL':<18}  {no_a.weight_per_branch:>11.3f}  {ap_a.weight_per_branch:>10.3f}  "
          f"{cf_a.weight_per_branch:>12.3f}  {ap_lift:>+8.1f}%  {cf_lift:>+11.1f}%")

    print()
    print("KEY:")
    print("  CondBr     = conditional branch count (jcc variants only)")
    print("  WtPerCondBr = total weighted instructions / conditional branches")
    print("               (APX instructions count as 2; higher = more work per branch)")
    print("  p50Wt/p90Wt = 50th/90th percentile of per-block weighted instruction count")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    asm_root = Path(__file__).parent.parent / 'SPEC' / 'asm'
    if not asm_root.exists():
        print(f"ERROR: {asm_root} not found", file=sys.stderr)
        sys.exit(1)

    benchmarks = sorted(p for p in asm_root.iterdir() if p.is_dir())

    all_stats = defaultdict(dict)
    for bench in benchmarks:
        print(f"Analyzing {bench.name}...", file=sys.stderr)
        for v in VARIANTS:
            if not (bench / v).exists():
                continue
            s = analyze_benchmark(bench, v)
            all_stats[bench.name][v] = s
            print(f"  {v}: {s.total_blocks:,} blocks, {s.total_cond_branches:,} cond-branches, "
                  f"wt/condBr={s.weight_per_branch:.2f}", file=sys.stderr)

    print_report(all_stats)


if __name__ == '__main__':
    main()
