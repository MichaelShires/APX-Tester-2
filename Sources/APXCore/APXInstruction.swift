import Foundation

/// Represents the APX instructions we are analyzing.
public enum APXInstruction: String, CaseIterable, Sendable {
    case ccmp = "ccmp"
    case ctest = "ctest"
    case cfcmov = "cfcmov"
    case push2 = "push2"
    case pop2 = "pop2"

    /// Human-readable description of what this instruction does.
    public var description: String {
        switch self {
        case .ccmp:
            return "Conditional compare — chains comparisons without branching"
        case .ctest:
            return "Conditional test — conditional bitwise test with flag updates"
        case .cfcmov:
            return "Conditional fused move — flag-preserving conditional move"
        case .push2:
            return "Push two registers in a single instruction"
        case .pop2:
            return "Pop two registers in a single instruction"
        }
    }
}
