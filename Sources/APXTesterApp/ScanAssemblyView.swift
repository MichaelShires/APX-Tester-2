import SwiftUI
import APXCore

struct ScanAssemblyView: View {
    @State private var filePath: String = ""
    @State private var matches: [InstructionMatch] = []
    @State private var counts: [APXInstruction: Int] = [:]
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var scannedFileName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                TextField("Path to assembly file or directory", text: $filePath)
                    .textFieldStyle(.roundedBorder)

                Button("Browse") { showFilePicker = true }

                Button(action: scan) {
                    HStack {
                        if isScanning {
                            ProgressView().controlSize(.small)
                        }
                        Text("Scan")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(filePath.isEmpty || isScanning)
            }
            .padding()

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            if matches.isEmpty && !isScanning {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select an assembly file or directory to scan for APX instructions.")
                )
            } else {
                HSplitView {
                    // Summary
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Summary")
                            .font(.headline)

                        if !scannedFileName.isEmpty {
                            Text(scannedFileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(APXInstruction.allCases, id: \.self) { inst in
                            let count = counts[inst, default: 0]
                            HStack {
                                Circle()
                                    .fill(colorFor(inst))
                                    .frame(width: 10, height: 10)
                                Text(inst.displayName)
                                Spacer()
                                Text("\(count)")
                                    .font(.system(.title3, design: .monospaced))
                                    .foregroundStyle(count > 0 ? .primary : .tertiary)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Total")
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(counts.values.reduce(0, +))")
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.bold)
                        }

                        Spacer()
                    }
                    .padding()
                    .frame(minWidth: 200, maxWidth: 280)

                    // Match list
                    Table(matches) {
                        TableColumn("Instruction") { match in
                            HStack {
                                Circle()
                                    .fill(colorFor(match.instruction))
                                    .frame(width: 8, height: 8)
                                Text(match.instruction.displayName)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .width(min: 100, max: 140)

                        TableColumn("Line") { match in
                            Text("\(match.line)")
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(60)

                        TableColumn("Source") { match in
                            Text(match.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 100, max: 200)

                        TableColumn("Assembly") { match in
                            Text(match.text)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Scan Assembly")
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item, .folder]) { result in
            if case .success(let url) = result {
                filePath = url.path
            }
        }
    }

    private func colorFor(_ inst: APXInstruction) -> Color {
        switch inst {
        case .ccmp, .ctest: return .green
        case .cfcmov: return .purple
        case .nddCmov: return .blue
        case .push2, .pop2: return .orange
        }
    }

    private func scan() {
        isScanning = true
        errorMessage = nil
        matches = []
        counts = [:]

        Task.detached {
            do {
                let analyzer = AssemblyAnalyzer()
                let url = URL(fileURLWithPath: filePath)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir)

                let result: ScanResult
                let name: String

                if isDir.boolValue {
                    result = try analyzer.scanDirectory(url)
                    name = "\(result.files) files in \(url.lastPathComponent)/"
                } else {
                    let found = try analyzer.findAPXInstructions(in: url)
                    result = ScanResult(
                        files: 1,
                        matches: found,
                        counts: analyzer.summarize(found)
                    )
                    name = url.lastPathComponent
                }

                await MainActor.run {
                    matches = result.matches
                    counts = result.counts
                    scannedFileName = name
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isScanning = false
                }
            }
        }
    }
}
