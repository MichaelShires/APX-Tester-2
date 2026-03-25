import SwiftUI
import APXCore

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let name: String
    let files: Int
    let ccmp: Int
    let ctest: Int
    let nddCmov: Int
    let cfcmov: Int
    let push2: Int
    let pop2: Int

    var total: Int { ccmp + ctest + nddCmov + cfcmov + push2 + pop2 }
}

struct SPECResultsView: View {
    @State private var results: [BenchmarkResult] = SPECResultsView.defaultResults
    @State private var showCF = false

    private static let defaultResults: [BenchmarkResult] = [
        BenchmarkResult(name: "505.mcf_r", files: 10, ccmp: 3, ctest: 0, nddCmov: 11, cfcmov: 0, push2: 21, pop2: 21),
        BenchmarkResult(name: "557.xz_r", files: 81, ccmp: 33, ctest: 45, nddCmov: 44, cfcmov: 0, push2: 218, pop2: 231),
        BenchmarkResult(name: "525.x264_r", files: 37, ccmp: 142, ctest: 91, nddCmov: 207, cfcmov: 0, push2: 453, pop2: 486),
        BenchmarkResult(name: "538.imagick_r", files: 99, ccmp: 344, ctest: 200, nddCmov: 412, cfcmov: 0, push2: 1867, pop2: 2154),
        BenchmarkResult(name: "502.gcc_r", files: 38, ccmp: 129, ctest: 89, nddCmov: 173, cfcmov: 0, push2: 609, pop2: 663),
    ]

    private static let cfResults: [BenchmarkResult] = [
        BenchmarkResult(name: "505.mcf_r", files: 10, ccmp: 3, ctest: 0, nddCmov: 11, cfcmov: 18, push2: 21, pop2: 21),
        BenchmarkResult(name: "557.xz_r", files: 81, ccmp: 34, ctest: 45, nddCmov: 29, cfcmov: 69, push2: 214, pop2: 227),
        BenchmarkResult(name: "525.x264_r", files: 37, ccmp: 146, ctest: 93, nddCmov: 186, cfcmov: 258, push2: 453, pop2: 486),
        BenchmarkResult(name: "538.imagick_r", files: 99, ccmp: 345, ctest: 209, nddCmov: 373, cfcmov: 554, push2: 1867, pop2: 2154),
        BenchmarkResult(name: "502.gcc_r", files: 38, ccmp: 128, ctest: 89, nddCmov: 152, cfcmov: 221, push2: 609, pop2: 663),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Text("SPEC CPU 2017 APX Analysis")
                    .font(.headline)

                Spacer()

                Toggle("Include +cf (CFCMOV)", isOn: $showCF)
                    .toggleStyle(.switch)
                    .onChange(of: showCF) { _, newValue in
                        results = newValue ? SPECResultsView.cfResults : SPECResultsView.defaultResults
                    }
            }
            .padding()

            Divider()

            // Results table
            Table(results) {
                TableColumn("Benchmark") { r in
                    Text(r.name)
                        .fontWeight(.medium)
                }
                .width(min: 120, max: 160)

                TableColumn("Files") { r in
                    Text("\(r.files)")
                        .font(.system(.body, design: .monospaced))
                }
                .width(50)

                TableColumn("CCMP") { r in
                    CountCell(value: r.ccmp, color: .green)
                }
                .width(70)

                TableColumn("CTEST") { r in
                    CountCell(value: r.ctest, color: .green)
                }
                .width(70)

                TableColumn("NDD CMOV") { r in
                    CountCell(value: r.nddCmov, color: .blue)
                }
                .width(80)

                TableColumn("CFCMOV") { r in
                    CountCell(value: r.cfcmov, color: .purple)
                }
                .width(70)

                TableColumn("PUSH2") { r in
                    CountCell(value: r.push2, color: .orange)
                }
                .width(70)

                TableColumn("POP2") { r in
                    CountCell(value: r.pop2, color: .orange)
                }
                .width(70)

                TableColumn("Total") { r in
                    Text("\(r.total)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                }
                .width(70)
            }

            Divider()

            // Totals bar
            HStack(spacing: 24) {
                let totals = computeTotals()

                StatBadge(label: "Files", value: totals.files, color: .secondary)
                StatBadge(label: "CCMP", value: totals.ccmp, color: .green)
                StatBadge(label: "CTEST", value: totals.ctest, color: .green)
                StatBadge(label: "NDD CMOV", value: totals.nddCmov, color: .blue)
                StatBadge(label: "CFCMOV", value: totals.cfcmov, color: .purple)
                StatBadge(label: "PUSH2", value: totals.push2, color: .orange)
                StatBadge(label: "POP2", value: totals.pop2, color: .orange)

                Spacer()

                VStack(alignment: .trailing) {
                    Text("\(totals.total)")
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                    Text("Total APX")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("SPEC Results")
    }

    private func computeTotals() -> BenchmarkResult {
        BenchmarkResult(
            name: "TOTAL",
            files: results.reduce(0) { $0 + $1.files },
            ccmp: results.reduce(0) { $0 + $1.ccmp },
            ctest: results.reduce(0) { $0 + $1.ctest },
            nddCmov: results.reduce(0) { $0 + $1.nddCmov },
            cfcmov: results.reduce(0) { $0 + $1.cfcmov },
            push2: results.reduce(0) { $0 + $1.push2 },
            pop2: results.reduce(0) { $0 + $1.pop2 }
        )
    }
}

struct CountCell: View {
    let value: Int
    let color: Color

    var body: some View {
        Text("\(value)")
            .font(.system(.body, design: .monospaced))
            .foregroundColor(value > 0 ? color : .gray.opacity(0.4))
    }
}

struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(value > 0 ? color : .gray.opacity(0.4))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
