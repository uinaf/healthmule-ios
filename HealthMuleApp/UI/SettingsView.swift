import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var draftRange: BackfillRange?
    @State private var draftCustomStart: Date?
    @State private var isShowingDisconnectConfirmation = false

    var body: some View {
        Form {
            exportSection
            driveSection
            Section {
                NavigationLink("Advanced", value: HomeRoute.advanced)
                    .accessibilityIdentifier("advanced-link")
            }
        }
        .pageStyle()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings-screen")
    }

    // MARK: Export

    private var shownRange: BackfillRange {
        draftRange ?? model.backfillRange
    }

    private var shownCustomStart: Date {
        draftCustomStart ?? model.customBackfillStart
    }

    private var hasExportDraft: Bool {
        (draftRange != nil || draftCustomStart != nil)
            && model.backfillSelectionChanges(
                range: shownRange,
                customStart: shownCustomStart
            )
    }

    private var exportSection: some View {
        Section {
            Picker(
                "History",
                selection: Binding(
                    get: { shownRange },
                    set: { draftRange = $0 }
                )
            ) {
                ForEach(BackfillRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("backfill-range-picker")

            if shownRange == .custom {
                DatePicker(
                    "Start date",
                    selection: Binding(
                        get: { shownCustomStart },
                        set: { draftCustomStart = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }

            if hasExportDraft {
                Button("Apply and Sync") {
                    model.applyBackfillSelection(
                        range: shownRange,
                        customStart: shownCustomStart
                    )
                    discardExportDraft()
                }
                .disabled(model.blocksSettingsChanges)
                .accessibilityIdentifier("backfill-apply-action")
                Button("Cancel", role: .cancel) {
                    discardExportDraft()
                }
                .accessibilityIdentifier("backfill-discard-action")
            }

            NavigationLink(value: HomeRoute.metrics) {
                LabeledContent(
                    "Metrics",
                    value: "\(model.enabledMetrics.count) of \(HealthMetric.allCases.count)"
                )
            }
            .accessibilityIdentifier("metrics-link")
        } header: {
            Text("Export")
        } footer: {
            if let exportFooter {
                Text(exportFooter)
            }
        }
    }

    private var exportFooter: String? {
        guard hasExportDraft else { return nil }
        let start = shownRange.startDate(customDate: shownCustomStart)
            .formatted(date: .abbreviated, time: .omitted)
        return model.operationState.isWorking(.sync)
            ? "The current sync stops and a new one exports from \(start)."
            : "Exports from \(start)."
    }

    private func discardExportDraft() {
        draftRange = nil
        draftCustomStart = nil
    }

    // MARK: Drive

    @ViewBuilder
    private var driveSection: some View {
        if model.googleConnection.account != nil || model.googleConnection.canDisconnect {
            Section("Google Drive") {
                if let email = model.googleConnection.account?.email {
                    if case .connected(let connection) = model.googleConnection {
                        LabeledContent(email, value: connection.folderName)
                    } else {
                        Text(email)
                    }
                }
                if
                    case .connected(let connection) = model.googleConnection,
                    let folderURL = connection.folderURL
                {
                    Button("Open in Drive") {
                        openURL(folderURL)
                    }
                }
                Button("Disconnect Google", role: .destructive) {
                    isShowingDisconnectConfirmation = true
                }
                .disabled(model.blocksSettingsChanges)
                .alert("Disconnect Google?", isPresented: $isShowingDisconnectConfirmation) {
                    Button("Disconnect Google", role: .destructive) {
                        Task { await model.disconnectGoogle() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Files in Drive stay.")
                }
            }
        }
    }
}
