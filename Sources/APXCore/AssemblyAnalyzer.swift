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
            // Skip comments and labels
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("."), !trimmed.hasSuffix(":") else {
                continue
            }

            for instruction in APXInstruction.allCases {
                if trimmed.hasPrefix(instruction.rawValue) {
                    matches.append(InstructionMatch(
                        instruction: instruction,
                        line: lineNumber + 1,
                        text: trimmed,
                        source: source
                    ))
                }
            }
        }

        return matches
    }
}

public struct InstructionMatch: Sendable {
    public let instruction: APXInstruction
    public let line: Int
    public let text: String
    public let source: String
}
