import SwiftUI
import APXCore

struct CompileAnalyzeView: View {
    @State private var sourceFile: String = ""
    @State private var clangPath: String = "/opt/homebrew/opt/llvm/bin/clang"
    @State private var selectedOptLevel: OptimizationLevel = .o2
    @State private var enableAPX = true
    @State private var enableCF = false
    @State private var isCompiling = false
    @State private var assemblyOutput: String = ""
    @State private var matches: [InstructionMatch] = []
    @State private var counts: [APXInstruction: Int] = [:]
    @State private var errorMessage: String?
    @State private var showFilePicker = false

    var body: some View {
        HSplitView {
            // Left panel — controls
            Form {
                Section("Source File") {
                    HStack {
                        TextField("Path to C source file", text: $sourceFile)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") { showFilePicker = true }
                    }
                }

                Section("Compiler Settings") {
                    TextField("clang path", text: $clangPath)
                        .textFieldStyle(.roundedBorder)

                    Picker("Optimization", selection: $selectedOptLevel) {
                        ForEach(OptimizationLevel.allCases, id: \.self) { level in
                            Text("-\(level.rawValue)").tag(level)
                        }
                    }

                    Toggle("Enable APX (-mapxf)", isOn: $enableAPX)
                    Toggle("Enable Conditional Faulting (+cf)", isOn: $enableCF)
                        .disabled(!enableAPX)
                }

                Section {
                    Button(action: compile) {
                        HStack {
                            if isCompiling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isCompiling ? "Compiling..." : "Compile & Analyze")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sourceFile.isEmpty || isCompiling)
                }

                if let error = errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                if !counts.isEmpty {
                    Section("APX Instruction Counts") {
                        ForEach(APXInstruction.allCases, id: \.self) { inst in
                            HStack {
                                Text(inst.displayName)
                                Spacer()
                                Text("\(counts[inst, default: 0])")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(counts[inst, default: 0] > 0 ? .primary : .tertiary)
                            }
                        }
                        HStack {
                            Text("Total")
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(counts.values.reduce(0, +))")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, maxWidth: 400)

            // Right panel — assembly output
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Assembly Output")
                        .font(.headline)
                    Spacer()
                    if !assemblyOutput.isEmpty {
                        Text("\(assemblyOutput.components(separatedBy: .newlines).count) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if assemblyOutput.isEmpty {
                    ContentUnavailableView(
                        "No Assembly",
                        systemImage: "doc.text",
                        description: Text("Compile a C source file to see assembly output.")
                    )
                } else {
                    ScrollView {
                        Text(highlightedAssembly)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle("Compile & Analyze")
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.cSource, .cPlusPlusSource]) { result in
            if case .success(let url) = result {
                sourceFile = url.path
            }
        }
    }

    private var highlightedAssembly: AttributedString {
        var result = AttributedString()
        for line in assemblyOutput.components(separatedBy: .newlines) {
            var attrLine = AttributedString(line + "\n")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("ccmp") || trimmed.hasPrefix("ctest") || trimmed.hasPrefix("cfcmov") {
                attrLine.foregroundColor = .green
                attrLine.font = .system(.caption, design: .monospaced).bold()
            } else if trimmed.hasPrefix("cmov") && trimmed.split(separator: ",").count == 3 {
                attrLine.foregroundColor = .blue
                attrLine.font = .system(.caption, design: .monospaced).bold()
            } else if trimmed.hasPrefix("push2") || trimmed.hasPrefix("pop2") {
                attrLine.foregroundColor = .orange
                attrLine.font = .system(.caption, design: .monospaced).bold()
            }

            result.append(attrLine)
        }
        return result
    }

    private func compile() {
        isCompiling = true
        errorMessage = nil
        matches = []
        counts = [:]
        assemblyOutput = ""

        let capturedClangPath = clangPath
        let capturedSourceFile = sourceFile
        let capturedOptLevel = selectedOptLevel
        let capturedEnableAPX = enableAPX
        let capturedEnableCF = enableCF

        Task.detached {
            do {
                let sysroot = try CompileAnalyzeView.getSysroot()
                var extraFlags = ["-isysroot", sysroot, "-w"]
                if capturedEnableCF {
                    extraFlags.append(contentsOf: ["-Xclang", "-target-feature", "-Xclang", "+cf"])
                }

                let driver = CompilerDriver(
                    clangPath: capturedClangPath,
                    target: "x86_64-apple-macos",
                    extraFlags: extraFlags
                )

                let sourceURL = URL(fileURLWithPath: capturedSourceFile)
                let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("apx_output.s")

                let result = try driver.compileToAssembly(
                    source: sourceURL,
                    output: outputURL,
                    optimizationLevel: capturedOptLevel,
                    enableAPX: capturedEnableAPX
                )

                if result.succeeded {
                    let asm = try String(contentsOf: outputURL, encoding: .utf8)
                    let analyzer = AssemblyAnalyzer()
                    let found = analyzer.findAPXInstructions(in: asm, source: sourceURL.lastPathComponent)
                    let summary = analyzer.summarize(found)

                    await MainActor.run {
                        assemblyOutput = asm
                        matches = found
                        counts = summary
                        isCompiling = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = result.stderr
                        isCompiling = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCompiling = false
                }
            }
        }
    }

    private static func getSysroot() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "macosx", "--show-sdk-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
