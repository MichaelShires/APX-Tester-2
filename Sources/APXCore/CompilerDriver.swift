import Foundation

/// Handles invoking clang/LLVM for cross-compilation with APX flags.
public struct CompilerDriver: Sendable {
    public let clangPath: String
    public let target: String
    public let extraFlags: [String]

    public init(
        clangPath: String = "/usr/bin/clang",
        target: String = "x86_64-unknown-linux-gnu",
        extraFlags: [String] = []
    ) {
        self.clangPath = clangPath
        self.target = target
        self.extraFlags = extraFlags
    }

    /// Compile a C source file to assembly with APX flags enabled.
    public func compileToAssembly(
        source: URL,
        output: URL,
        optimizationLevel: OptimizationLevel = .o2,
        enableAPX: Bool = true
    ) throws -> ProcessResult {
        var args = [
            "-S",
            "--target=\(target)",
            optimizationLevel.flag,
            "-o", output.path,
            source.path,
        ]

        if enableAPX {
            args.append("-mapxf")
        }

        args.append(contentsOf: extraFlags)

        return try run(clangPath, arguments: args)
    }

    /// Compile and dump LLVM IR after all passes for analysis.
    public func dumpIRAfterAllPasses(
        source: URL,
        output: URL,
        optimizationLevel: OptimizationLevel = .o2,
        enableAPX: Bool = true
    ) throws -> ProcessResult {
        var args = [
            "-S",
            "-emit-llvm",
            "--target=\(target)",
            optimizationLevel.flag,
            "-mllvm", "-print-after-all",
            "-o", output.path,
            source.path,
        ]

        if enableAPX {
            args.append("-mapxf")
        }

        args.append(contentsOf: extraFlags)

        return try run(clangPath, arguments: args)
    }

    private func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

public enum OptimizationLevel: String, CaseIterable, Sendable {
    case o0 = "O0"
    case o1 = "O1"
    case o2 = "O2"
    case o3 = "O3"

    public var flag: String { "-\(rawValue)" }
}

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}
