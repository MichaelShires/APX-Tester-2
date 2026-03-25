import SwiftUI
import APXCore

struct InstructionDetailView: View {
    let instruction: APXInstruction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text(instruction.displayName)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(instruction.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Details
                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(label: "Assembly mnemonic", value: instruction.rawValue == "ndd_cmov" ? "cmovXX %r, %r, %r" : instruction.rawValue)
                        DetailRow(label: "Required flag", value: instruction.requiredFlag)
                        DetailRow(label: "Pattern type", value: patternType)
                    }
                    .padding(8)
                }

                // Source pattern
                GroupBox("Source Code Pattern") {
                    Text(sourcePattern)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Key findings
                GroupBox("Key Findings from Analysis") {
                    Text(findings)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .navigationTitle(instruction.displayName)
    }

    private var patternType: String {
        switch instruction {
        case .ccmp: return "Compound conditionals (&&, ||)"
        case .ctest: return "Compound conditionals with bitwise test"
        case .cfcmov: return "Conditional memory access (guarded load/store)"
        case .nddCmov: return "Conditional assignment (ternary, min/max)"
        case .push2: return "Function prologue (callee-saved register spill)"
        case .pop2: return "Function epilogue (callee-saved register restore)"
        }
    }

    private var sourcePattern: String {
        switch instruction {
        case .ccmp:
            return """
            // Compound AND
            if (a > x && b < y)
                return 1;

            // Range check
            if (val >= lo && val <= hi)
                return 1;
            """
        case .ctest:
            return """
            // Compound conditional with bitwise test
            if (flags & MASK && value > threshold)
                return 1;
            """
        case .cfcmov:
            return """
            // Conditional load (requires +cf flag)
            if (cond)
                return *ptr;  // CFCMOV rm

            // Conditional store
            if (cond)
                *ptr = val;   // CFCMOV mr
            """
        case .nddCmov:
            return """
            // Ternary (3-operand: cmovgl %src1, %src2, %dst)
            return cond > 0 ? a : b;

            // Min/Max
            return a < b ? a : b;
            """
        case .push2:
            return """
            // Automatically generated in function prologues
            // when 2+ callee-saved registers need saving
            void func_with_calls(long a, long b, long c) {
                long r1 = a + b;
                long r2 = b + c;
                external_call(r1);  // forces spill
                return r1 + r2;
            }
            """
        case .pop2:
            return """
            // Paired with PUSH2 in function epilogues
            // Restores callee-saved registers in pairs
            """
        }
    }

    private var findings: String {
        switch instruction {
        case .ccmp:
            return """
            - 651 CCMP instructions across 265 SPEC files
            - Conversion rate ~105% (also converts branch-based compound conditionals)
            - Activated at O1, stable through O3
            - 500/500 CSmith programs: pattern always survived
            """
        case .ctest:
            return """
            - 425 CTEST instructions across 265 SPEC files
            - Companion to CCMP for bitwise test patterns
            - Same activation behavior as CCMP
            """
        case .cfcmov:
            return """
            - NOT enabled by -mapxf (requires separate +cf flag)
            - With +cf: 1,120 CFCMOV across 119 files (45%)
            - Eliminates 634 conditional branches in SPEC
            - Reduces NDD CMOV count by 66 (subsumes conditional loads)
            - Top file: x264_src_encoder_analyse.s (87 CFCMOVs)
            """
        case .nddCmov:
            return """
            - 847 NDD CMOV instructions across 265 SPEC files
            - 100% conversion rate: zero missed MOV+CMOV pairs
            - Architecturally distinct from CFCMOV
            - Eliminates setup MOV instruction before conditional move
            """
        case .push2:
            return """
            - 3,168 PUSH2 instructions across 265 SPEC files
            - Pairing rate: 48-89% depending on benchmark
            - Limited by: odd register counts, alignment pushes, frame pointers
            - Tail-call optimization can eliminate opportunities
            """
        case .pop2:
            return """
            - 3,555 POP2 instructions across 265 SPEC files
            - Always paired with corresponding PUSH2 in prologues
            """
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
