import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @ScaledMetric(relativeTo: .subheadline) private var metricIconWidth: CGFloat = 22
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDisconnectConfirmation = false
    @State private var isShowingTrashConfirmation = false

    var body: some View {
        Form {
            overviewSection
            metricsSection
            diagnosticsSection
            googleSection
            driveExportsSection
            resetSection
            OperationBanner(state: model.operationState)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .formStyle(.grouped)
        .listSectionSpacing(24)
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(HealthMuleStyle.canvas)
        .accessibilityIdentifier("settings-screen")

    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export preferences")
                    .font(HealthMuleStyle.Text.sectionTitle)
                Text(
                    "\(model.enabledMetrics.count) of \(HealthMetric.allCases.count) health data types included"
                )
                .font(HealthMuleStyle.Text.cardBody)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var metricsSection: some View {
        Section {
            ForEach(HealthMetric.allCases) { metric in
                Toggle(isOn: Binding(
                    get: { model.enabledMetrics.contains(metric) },
                    set: { model.setMetric(metric, enabled: $0) }
                )) {
                    Label {
                        Text(metric.title)
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: metric.settingsSystemImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: metricIconWidth)
                    }
                }
                .disabled(model.operationState.isWorking)
            }
        } header: {
            Text("Included metrics")
        } footer: {
            Text(
                "Disabled metrics are not queried and are cleared from managed daily records. Enabling a new type may require reviewing read-only Apple Health access."
            )
        }
        .listRowBackground(HealthMuleStyle.surface)
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            Button {
                Task {
                    await model.prepareDiagnosticsExport()
                }
            } label: {
                Label("Prepare Diagnostics", systemImage: "doc.badge.gearshape")
            }
            .disabled(model.operationState.isWorking)

            if let diagnosticsURL = model.diagnosticsURL {
                ShareLink(item: diagnosticsURL) {
                    Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text(
                "The export contains lifecycle events, counts, durations, and error codes. It never contains health values, file contents, or OAuth tokens."
            )
        }
        .listRowBackground(HealthMuleStyle.surface)
    }

    @ViewBuilder
    private var googleSection: some View {
        if model.googleConnection.canDisconnect {
            Section {
                Button(role: .destructive) {
                    isShowingDisconnectConfirmation = true
                } label: {
                    Label("Disconnect Google", systemImage: "link")
                }
                .disabled(model.operationState.isWorking)
                .alert("Disconnect Google?", isPresented: $isShowingDisconnectConfirmation) {
                    Button("Disconnect Google", role: .destructive) {
                        Task {
                            await model.disconnectGoogle()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Existing files in Google Drive will not be deleted.")
                }
            } footer: {
                Text("Disconnecting revokes the app’s Google authorization. Drive exports are kept.")
            }
            .listRowBackground(HealthMuleStyle.surface)
        }
    }

    @ViewBuilder
    private var driveExportsSection: some View {
        if model.googleConnection.account != nil {
            Section {
                Button(role: .destructive) {
                    isShowingTrashConfirmation = true
                } label: {
                    Label("Move Drive Exports to Trash", systemImage: "trash")
                }
                .disabled(model.operationState.isWorking)
                .alert("Move Drive exports to Trash?", isPresented: $isShowingTrashConfirmation) {
                    Button("Move to Trash", role: .destructive) {
                        Task {
                            await model.trashDriveExports()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Accessible HealthMule exports will move to Google Drive Trash. Google will be disconnected to prevent re-upload. Local records and Apple Health data are kept. Folders and unrelated files are kept."
                    )
                }
            } footer: {
                Text("Only HealthMule exports this Google connection can access are moved. Other files are kept.")
            }
            .listRowBackground(HealthMuleStyle.surface)
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                isShowingResetConfirmation = true
            } label: {
                Label("Reset Local Sync State", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.operationState.isWorking)
            .alert("Reset local sync state?", isPresented: $isShowingResetConfirmation) {
                Button("Reset Local State", role: .destructive) {
                    Task {
                        await model.resetLocalState()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Local anchors, staged records, and retry state will be cleared. Saved day boundaries, stable Drive IDs, and existing files will be kept."
                )
            }
        } footer: {
            Text("Clears local sync progress. Apple Health data and existing Drive exports are kept.")
        }
        .listRowBackground(HealthMuleStyle.surface)
    }
}

private extension HealthMetric {
    var settingsSystemImage: String {
        switch self {
        case .bodyMass:
            "scalemass"
        case .stepCount:
            "figure.walk"
        case .activeEnergy:
            "flame"
        case .restingEnergy:
            "bolt.heart"
        case .restingHeartRate:
            "heart"
        case .hrvSDNN:
            "waveform.path.ecg"
        case .vo2Max:
            "lungs"
        case .sleep:
            "bed.double"
        case .workouts:
            "figure.run"
        }
    }
}
