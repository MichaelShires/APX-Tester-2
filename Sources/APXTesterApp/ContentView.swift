import SwiftUI
import APXCore

enum SidebarItem: Hashable {
    case instruction(APXInstruction)
    case compileAnalyze
    case scanAssembly
    case specResults
}

struct ContentView: View {
    @State private var selection: SidebarItem? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .instruction(let inst):
                InstructionDetailView(instruction: inst)
            case .compileAnalyze:
                CompileAnalyzeView()
            case .scanAssembly:
                ScanAssemblyView()
            case .specResults:
                SPECResultsView()
            case nil:
                WelcomeView()
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("APX Instructions") {
                ForEach(APXInstruction.allCases, id: \.self) { instruction in
                    Label(instruction.displayName, systemImage: "cpu")
                        .tag(SidebarItem.instruction(instruction))
                }
            }

            Section("Tools") {
                Label("Compile & Analyze", systemImage: "hammer")
                    .tag(SidebarItem.compileAnalyze)
                Label("Scan Assembly", systemImage: "doc.text.magnifyingglass")
                    .tag(SidebarItem.scanAssembly)
                Label("SPEC Results", systemImage: "chart.bar")
                    .tag(SidebarItem.specResults)
            }
        }
        .navigationTitle("APX Tester")
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("APX Tester")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("v\(APXCore.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Select an instruction or tool from the sidebar.")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
