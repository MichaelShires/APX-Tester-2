import Foundation
import ArgumentParser
import APXCore

@main
struct APXTesterCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apx-tester",
        abstract: "Analyze compiler APX instruction emission across optimization levels.",
        version: APXCore.version,
        subcommands: [
            Analyze.self,
            Scan.self,
        ],
        defaultSubcommand: Analyze.self
    )
}

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compile a C source file and check for APX instruction usage."
    )

    @Argument(help: "Path to the C source file.")
    var sourceFile: String

    @Option(name: .shortAndLong, help: "Optimization level (O0, O1, O2, O3).")
    var optimization: String = "O2"

    @Flag(name: .long, help: "Disable APX flags (compile without -mapxf).")
    var noApx: Bool = false

    @Option(name: .long, help: "Path to clang.")
    var clang: String = "/usr/bin/clang"

    func run() throws {
        print("APX Tester v\(APXCore.version)")
        print("Source: \(sourceFile)")
        print("Optimization: -\(optimization)")
        print("APX enabled: \(!noApx)")
        print()
        print("⚠ Analysis pipeline not yet implemented — skeleton only.")
    }
}

struct Scan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan an existing assembly file for APX instructions."
    )

    @Argument(help: "Path to the assembly file to scan.")
    var assemblyFile: String

    func run() throws {
        let url = URL(fileURLWithPath: assemblyFile)
        let analyzer = AssemblyAnalyzer()
        let matches = try analyzer.findAPXInstructions(in: url)

        if matches.isEmpty {
            print("No APX instructions found in \(assemblyFile)")
        } else {
            print("Found \(matches.count) APX instruction(s) in \(assemblyFile):")
            for match in matches {
                print("  [\(match.instruction.rawValue)] line \(match.line): \(match.text)")
            }
        }
    }
}
