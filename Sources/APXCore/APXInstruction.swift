import Foundation

/// Represents the APX instructions we are analyzing.
public enum APXInstruction: String, CaseIterable, Sendable {
    case ccmp = "ccmp"
    case ctest = "ctest"
    case cfcmov = "cfcmov"
    case nddCmov = "ndd_cmov"
    case push2 = "push2"
    case pop2 = "pop2"

    /// Human-readable name.
    public var displayName: String {
        switch self {
        case .ccmp: return "CCMP"
        case .ctest: return "CTEST"
        case .cfcmov: return "CFCMOV"
        case .nddCmov: return "NDD CMOV"
        case .push2: return "PUSH2"
        case .pop2: return "POP2"
        }
    }

    /// Human-readable description of what this instruction does.
    public var description: String {
        switch self {
        case .ccmp:
            return "Conditional compare — chains comparisons without branching"
        case .ctest:
            return "Conditional test — conditional bitwise test with flag updates"
        case .cfcmov:
            return "Conditional fused move — conditional memory access with fault suppression"
        case .nddCmov:
            return "NDD CMOV — 3-operand conditional move eliminating setup MOV"
        case .push2:
            return "Push two registers in a single instruction"
        case .pop2:
            return "Pop two registers in a single instruction"
        }
    }

    /// The required feature flag for this instruction.
    public var requiredFlag: String {
        switch self {
        case .ccmp, .ctest, .nddCmov: return "-mapxf"
        case .cfcmov: return "-mapxf +cf"
        case .push2, .pop2: return "-mapxf"
        }
    }
}
