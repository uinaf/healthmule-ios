import SwiftUI

struct AdvancedView: View {
    @Bindable var model: AppModel
    @State private var isShowingResetConfirmation = false
    @State private var isShowingTrashConfirmation = false

    var body: some View {
        Form {
            if let note = OperationNote(state: model.presentedOperationState, includesSync: true) {
                Section { note }
            }

            Section {
                Button("Retry Waiting Uploads", systemImage: "arrow.clockwise") {
                    Task { await model.retryFailedUploads() }
                }
                .disabled(
                    model.operationState.isWorking
                        || !model.syncReadiness.canSync
                        || model.syncSummary.retryableUploadCount == 0
                )
                .accessibilityIdentifier("retry-uploads-action")

                Button("Recheck Last Three Days", systemImage: "clock.arrow.circlepath") {
                    Task { await model.rebuildLastThreeDays() }
                }
                .disabled(model.operationState.isWorking || !model.syncReadiness.canSync)
                .accessibilityIdentifier("rebuild-action")

                DiagnosticsButton(model: model)
            } header: {
                Text("Fix a problem")
            }

            Section {
                fact(
                    "Last automatic sync",
                    "bolt.horizontal",
                    receiptText(model.syncActivitySummary.latestAutomatic)
                )
                .accessibilityIdentifier("automatic-activity-latest")
                fact(
                    "Last background refresh",
                    "moon",
                    receiptText(model.syncActivitySummary.latestBackgroundRefresh)
                )
                .accessibilityIdentifier("automatic-activity-background")
                fact(
                    "Refresh requested",
                    "calendar.badge.clock",
                    scheduleText(model.syncActivitySummary.schedule)
                )
                .accessibilityIdentifier("automatic-activity-schedule")
            } header: {
                Text("Automatic sync")
            }

            Section {
                Button("Reset Local Sync State", systemImage: "arrow.counterclockwise", role: .destructive) {
                    isShowingResetConfirmation = true
                }
                .disabled(model.blocksSettingsChanges)
                .alert("Reset local sync state?", isPresented: $isShowingResetConfirmation) {
                    Button("Reset Local State", role: .destructive) {
                        Task { await model.resetLocalState() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Drive files stay.")
                }

                if model.googleConnection.account != nil {
                    Button("Move Drive Exports to Trash", systemImage: "trash", role: .destructive) {
                        isShowingTrashConfirmation = true
                    }
                    .disabled(model.blocksSettingsChanges)
                    .alert("Move Drive exports to Trash?", isPresented: $isShowingTrashConfirmation) {
                        Button("Move to Trash", role: .destructive) {
                            Task { await model.trashDriveExports() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Google disconnects so nothing uploads again.")
                    }
                }
            }
        }
        .pageStyle()
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("advanced-screen")
    }

    private func fact(_ title: String, _ symbol: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private func receiptText(_ receipt: SyncActivityReceipt?) -> String {
        guard let receipt else { return "None" }
        let time = (receipt.finishedAt ?? receipt.startedAt)
            .formatted(date: .abbreviated, time: .shortened)
        return "\(receipt.outcome.statusLabel) · \(time)"
    }

    private func scheduleText(_ receipt: BackgroundRefreshScheduleReceipt?) -> String {
        guard let receipt else { return "None" }
        let label = switch receipt.result {
        case .submitted: "Submitted"
        case .existingRequestKept: "Kept"
        case .failed: "Failed"
        }
        return "\(label) · \(receipt.attemptedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private extension SyncActivityOutcome {
    var statusLabel: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .pending: "Pending"
        case .skipped: "Skipped"
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        }
    }
}
