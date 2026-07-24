import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDisconnectConfirmation = false

    var body: some View {
        Form {
            metricsSection
            diagnosticsSection
            googleSection
            resetSection
            OperationBanner(state: model.operationState)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(HealthRelayStyle.canvas)
        .accessibilityIdentifier("settings-screen")
        .confirmationDialog(
            "Disconnect Google?",
            isPresented: $isShowingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Google", role: .destructive) {
                Task {
                    await model.disconnectGoogle()
                }
            }
        } message: {
            Text("Existing files in Google Drive will not be deleted.")
        }
        .confirmationDialog(
            "Reset local sync state?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Local State", role: .destructive) {
                Task {
                    await model.resetLocalState()
                }
            }
        } message: {
            Text(
                "Local anchors, staged records, and retry state will be cleared. Saved day boundaries, stable Drive IDs, and existing files will be kept."
            )
        }
    }

    private var metricsSection: some View {
        Section {
            ForEach(HealthMetric.allCases) { metric in
                Toggle(
                    metric.title,
                    isOn: Binding(
                        get: { model.enabledMetrics.contains(metric) },
                        set: { model.setMetric(metric, enabled: $0) }
                    )
                )
                .disabled(model.operationState.isWorking)
            }
        } header: {
            Text("Included metrics")
        } footer: {
            Text(
                "Disabled metrics are not queried and are cleared from managed daily records. Enabling a new type may require reviewing read-only Apple Health access."
            )
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            Button("Prepare Diagnostics") {
                Task {
                    await model.prepareDiagnosticsExport()
                }
            }
            .disabled(model.operationState.isWorking)

            if let diagnosticsURL = model.diagnosticsURL {
                ShareLink(item: diagnosticsURL) {
                    Text("Share Diagnostics")
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text(
                "The export contains lifecycle events, counts, durations, and error codes—never health values, file contents, or OAuth tokens."
            )
        }
    }

    @ViewBuilder
    private var googleSection: some View {
        if model.googleConnection.canDisconnect {
            Section {
                Button("Disconnect Google", role: .destructive) {
                    isShowingDisconnectConfirmation = true
                }
                .disabled(model.operationState.isWorking)
            } footer: {
                Text("Disconnecting revokes the app’s Google authorization.")
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Local Sync State", role: .destructive) {
                isShowingResetConfirmation = true
            }
            .disabled(model.operationState.isWorking)
        } footer: {
            Text(
                "Deleting Drive data is intentionally a separate action and is not available in this version."
            )
        }
    }
}
