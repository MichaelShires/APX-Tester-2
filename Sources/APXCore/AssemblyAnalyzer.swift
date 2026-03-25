import Foundation

/// Parses assembly output and searches for APX instruction usage.
public struct AssemblyAnalyzer: Sendable {

    public init() {}

    /// Scan an assembly file for occurrences of target APX instructions.
    public func findAPXInstructions(in assemblyFile: URL) throws -> [InstructionMatch] {
        let content = try String(contentsOf: assemblyFile, encoding: .utf8)
        return findAPXInstructions(in: content, source: assemblyFile.lastPathComponent)
    }

    /// Scan assembly text for occurrences of target APX instructions.
    public func findAPXInstructions(in assembly: String, source: String = "<input>") -> [InstructionMatch] {
        var matches: [InstructionMatch] = []
        let lines = assembly.components(separatedBy: .newlines)

        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("."), !trimmed.hasSuffix(":") else {
                continue
            }

            // Check simple prefix-based instructions
            for instruction in [APXInstruction.ccmp, .ctest, .cfcmov, .push2, .pop2] {
                if trimmed.hasPrefix(instruction.rawValue) {
                    matches.append(InstructionMatch(
                        instruction: instruction,
                        line: lineNumber + 1,
                        text: trimmed,
                        source: source
                    ))
                }
            }

            // NDD CMOV: 3-operand cmov (cmovXX %reg, %reg, %reg)
            if trimmed.hasPrefix("cmov") {
                let parts = trimmed.split(separator: ",")
                if parts.count == 3 {
                    // Verify all three operands are registers
                    let allRegs = parts.allSatisfy { $0.trimmingCharacters(in: .whitespaces).contains("%") }
                    if allRegs {
                        matches.append(InstructionMatch(
                            instruction: .nddCmov,
                            line: lineNumber + 1,
                            text: trimmed,
                            source: source
                        ))
                    }
                }
            }
        }

        return matches
    }

    /// Summarize APX instruction counts from a list of matches.
    public func summarize(_ matches: [InstructionMatch]) -> [APXInstruction: Int] {
        var counts: [APXInstruction: Int] = [:]
        for inst in APXInstruction.allCases {
            counts[inst] = 0
        }
        for match in matches {
            counts[match.instruction, default: 0] += 1
        }
        return counts
    }

    /// Scan a directory of assembly files and return aggregate results.
    public func scanDirectory(_ directory: URL) throws -> ScanResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return ScanResult(files: 0, matches: [], counts: [:])
        }

        var allMatches: [InstructionMatch] = []
        var fileCount = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "s" else { continue }
            fileCount += 1
            let matches = try findAPXInstructions(in: fileURL)
            allMatches.append(contentsOf: matches)
        }

        return ScanResult(
            files: fileCount,
            matches: allMatches,
            counts: summarize(allMatches)
        )
    }
}

public struct InstructionMatch: Sendable, Identifiable {
    public let id = UUID()
    public let instruction: APXInstruction
    public let line: Int
    public let text: String
    public let source: String
}

public struct ScanResult: Sendable {
    public init(files: Int, matches: [InstructionMatch], counts: [APXInstruction: Int]) {
        self.files = files
        self.matches = matches
        self.counts = counts
    }

    public let files: Int
    public let matches: [InstructionMatch]
    public let counts: [APXInstruction: Int]

    public var totalInstructions: Int {
        counts.values.reduce(0, +)
    }
}
