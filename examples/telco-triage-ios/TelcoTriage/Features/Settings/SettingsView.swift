import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.brand) private var brand

    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                kbSection
                modelsSection
                sessionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Reset session?", isPresented: $showResetConfirm) {
                Button("Reset", role: .destructive, action: resetSession)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears the token ledger, latency stats, and PII counts. Conversation history is not affected.")
            }
        }
    }

    private var modeSection: some View {
        Section(header: Text("Experience mode")) {
            Picker("Mode", selection: $appState.appMode) {
                Text("Customer").tag(AppMode.customer)
                Text("Engineering").tag(AppMode.engineering)
            }
            .pickerStyle(.segmented)
            Text(appState.appMode == .customer
                 ? "Clean chat experience. Traces and confidence scores are hidden."
                 : "Full instrumentation. Trace rows, tool cards, and latency counters visible.")
                .font(.caption).foregroundStyle(brand.textSecondary)
        }
    }

    private var kbSection: some View {
        Section(header: Text("Composer RAG")) {
            LabeledContent("Status", value: appState.ragStatus.isLive ? "Live" : "Degraded")
            LabeledContent("Corpus", value: "rag-units-v1.json")
            LabeledContent(
                "Units",
                value: appState.ragStatus.corpusUnitCount.map(String.init) ?? "—"
            )
            LabeledContent("Retriever", value: "BM25 hierarchy")
            LabeledContent("Answer layer", value: "Deterministic composer")
            if let reason = appState.ragStatus.degradedReason {
                LabeledContent("Reason", value: reason)
            }
            Text("Normal demo answers use the canonical composer corpus and render only approved `vzhome://` links. The legacy 34-entry keyword KB is kept as a fallback for degraded builds.")
                .font(.caption).foregroundStyle(brand.textSecondary)
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if appState.appMode == .engineering {
            Section(header: Text("On-device models")) {
                LabeledContent("Base", value: TelcoModelBundle.baseModelName)
                LabeledContent(
                    "Legacy decision heads",
                    value: TelcoModelBundle.sharedClfAdapterPath() == nil
                        ? "not active"
                        : TelcoModelBundle.sharedClfAdapterName
                )
                LabeledContent(
                    "Legacy chat router",
                    value: TelcoModelBundle.chatModeRouterAdapterPath() == nil
                        ? "not bundled"
                        : TelcoModelBundle.chatModeRouterAdapterName
                )
                LabeledContent("Tool selector", value: TelcoModelBundle.toolAdapterName)
                Text("Customer Q&A uses the composer path. Legacy understanding adapters are shown only for degraded builds and opt-in experiments.")
                    .font(.caption).foregroundStyle(brand.textSecondary)
            }

            Section(header: Text("Legacy Stage B probe")) {
                NavigationLink {
                    VerizonRAGTestView()
                } label: {
                    LabeledContent(
                        "Stage B generator",
                        value: TelcoModelBundle.verizonStageBGeneratorPath() == nil
                            ? "not bundled"
                            : TelcoModelBundle.verizonStageBGeneratorName
                    )
                }
                .disabled(TelcoModelBundle.verizonStageBGeneratorPath() == nil)
                Text("Optional evaluation surface only. The normal answer path is BM25HierarchyRetriever plus the deterministic composer; Stage B is not required for grounded answers.")
                    .font(.caption).foregroundStyle(brand.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        if appState.appMode == .engineering {
            Section(header: Text("Session")) {
                LabeledContent("Tokens kept on-device", value: "\(appState.tokenLedger.totalTokensSaved)")
                LabeledContent("On-device answers", value: "\(appState.tokenLedger.messagesOnDevice)")
                LabeledContent("Tool deflections", value: "\(appState.tokenLedger.messagesDeflected)")
                Button("Reset metrics", role: .destructive) { showResetConfirm = true }
            }
        }
    }

    private var aboutSection: some View {
        Section(header: Text("About")) {
            LabeledContent("Build", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"))")
            LabeledContent("App", value: "\(brand.appName) \(brand.appSubtitle)")
            Text("Liquid Telco Triage runs LFM2.5-350M on-device for routing, safe action decisions, and private support flows. Grounded Q&A uses BM25 composer RAG over canonical support units with explicit confirmation before supported actions.")
                .font(.caption).foregroundStyle(brand.textSecondary)
        }
    }

    private func resetSession() {
        appState.tokenLedger.reset()
        appState.sessionStats.reset()
    }
}
