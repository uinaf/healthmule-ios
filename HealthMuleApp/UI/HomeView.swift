import GoogleSignInSwift
import SwiftUI
import UIKit

enum HomeRoute: Hashable {
    case metrics
    case advanced
}

struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var draftRange: BackfillRange?
    @State private var draftCustomStart: Date?
    @State private var isShowingDisconnectConfirmation = false

    var body: some View {
        Form {
            statusSection
            if showsSetup {
                setupSection
            }
            exportSection
            driveSection
            Section {
                NavigationLink("Advanced", value: HomeRoute.advanced)
                    .accessibilityIdentifier("advanced-link")
            } footer: {
                Text("No developer backend, analytics, or write access to Apple Health.")
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("HealthMule")
        .accessibilityIdentifier("home-screen")
        .refreshable {
            await model.applicationDidBecomeActive()
        }
    }

    // MARK: Status

    private var status: HomeStatus {
        HomeStatus(model: model)
    }

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.title)
                        .font(.headline)
                        .foregroundStyle(status.isProblem ? Color.red : .primary)
                        .accessibilityIdentifier("status-title")
                    if model.operationState.isWorking(.sync), model.syncProgress == nil {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(status.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("status-message")
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            if let progress = model.syncProgress, progress.totalUnits > 0 {
                SyncDayProgressView(progress: progress)
            }

            if let note = OperationNote(state: model.presentedOperationState) {
                note
            }

            if let action = status.action {
                statusAction(action)
            }

            if showsSyncFacts {
                LabeledContent("Last Drive sync", value: model.syncSummary.lastSyncText)
                    .accessibilityIdentifier("last-sync-fact")
                LabeledContent("Data through", value: model.syncSummary.latestExportedDayText)
                    .accessibilityIdentifier("data-through-fact")
                LabeledContent("To upload", value: model.syncSummary.pendingUploadCount.formatted())
                    .accessibilityIdentifier("pending-upload-count")
            }
        }
    }

    private var showsSyncFacts: Bool {
        model.initialLoadPhase == .loaded
            && (model.syncReadiness.canSync
                || model.syncSummary.lastSuccessfulSyncAt != nil)
    }

    @ViewBuilder
    private func statusAction(_ action: HomeStatus.Action) -> some View {
        switch action {
        case .sync(let title):
            Button {
                Task { await model.reconcile(trigger: .manual) }
            } label: {
                Label(title, systemImage: "arrow.triangle.2.circlepath")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.primary)
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("sync-now-action")
        case .retry:
            Button("Retry Uploads", systemImage: "arrow.clockwise") {
                Task { await model.retryFailedUploads() }
            }
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("retry-uploads-action")
        case .diagnostics:
            DiagnosticsButton(model: model)
        }
    }

    // MARK: Setup

    private var showsSetup: Bool {
        model.healthAuthorizationState != .requestCompleted
            || !model.googleConnection.isDriveReady
            || model.backgroundDeliveryAdvisory != nil
    }

    private var setupSection: some View {
        Section("Setup") {
            setupStep("Apple Health", healthStateText, isDone: model.healthAuthorizationState.allowsQueries)
                .accessibilityIdentifier("health-connection-row")
            healthAction
            setupStep("Google Drive", googleStateText, isDone: model.googleConnection.isDriveReady)
                .accessibilityIdentifier("google-connection-row")
            googleAction
            if let advisory = model.backgroundDeliveryAdvisory {
                VStack(alignment: .leading, spacing: 4) {
                    Text(advisory.title).font(.subheadline.weight(.semibold))
                    Text(advisory.message).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("background-delivery-advisory")
                checkHealthAgainButton
            }
        }
    }

    private func setupStep(_ title: String, _ state: String, isDone: Bool) -> some View {
        LabeledContent {
            Text(state)
        } label: {
            Label(title, systemImage: isDone ? "checkmark.circle.fill" : "circle.dashed")
        }
    }

    private var healthStateText: String {
        switch model.healthAuthorizationState {
        case .unavailable: "Unavailable"
        case .checking: "Checking"
        case .statusUnavailable: "Check failed"
        case .notRequested: "Not requested"
        case .reviewRequired: "Review needed"
        case .requestCompleted: "Requested"
        }
    }

    @ViewBuilder
    private var healthAction: some View {
        switch model.healthAuthorizationState {
        case .notRequested, .reviewRequired:
            Button(
                model.healthAuthorizationState == .reviewRequired
                    ? "Review Health Access"
                    : "Request Health Access",
                systemImage: "heart"
            ) {
                Task { await model.requestHealthAuthorization() }
            }
            .disabled(!model.isHealthKitAvailable || model.operationState.isWorking)
            .accessibilityIdentifier("health-authorization-action")
        case .statusUnavailable:
            checkHealthAgainButton
        case .unavailable, .checking, .requestCompleted:
            EmptyView()
        }
    }

    private var checkHealthAgainButton: some View {
        Button("Check Apple Health Again") {
            Task { await model.retryHealthStatus() }
        }
        .disabled(model.operationState.isWorking)
        .accessibilityIdentifier("health-check-again-action")
    }

    private var googleStateText: String {
        switch model.googleConnection {
        case .notConfigured: "Not configured"
        case .restoring: "Checking"
        case .disconnected: "Not connected"
        case .temporarilyUnavailable: "Unavailable"
        case .reauthorizationRequired: "Reconnect"
        case .authorized: "Finishing setup"
        case .driveUnavailable: "Drive unavailable"
        case .connected: "Connected"
        }
    }

    @ViewBuilder
    private var googleAction: some View {
        switch model.googleConnection {
        case .disconnected, .reauthorizationRequired:
            GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light) {
                Task { await model.connectGoogle() }
            }
            .disabled(model.operationState.isWorking)
            .accessibilityLabel(
                model.googleConnection == .disconnected
                    ? "Connect Google Drive"
                    : "Reconnect Google Drive"
            )
        case .temporarilyUnavailable, .driveUnavailable:
            Button("Try Drive Again") {
                Task { await model.retryGoogleRestore() }
            }
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("google-retry-action")
        case .notConfigured, .restoring, .authorized, .connected:
            EmptyView()
        }
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
                "Start",
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
            } else if let applied = model.appliedBackfillStart {
                LabeledContent(
                    "Exporting from",
                    value: applied.formatted(date: .abbreviated, time: .omitted)
                )
                .accessibilityIdentifier("backfill-applied-start")
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
            Text(exportFooter)
        }
    }

    private var exportFooter: String {
        guard hasExportDraft else {
            return "Changes start a sync only after Apply."
        }
        let start = shownRange.startDate(customDate: shownCustomStart)
            .formatted(date: .abbreviated, time: .omitted)
        return model.operationState.isWorking(.sync)
            ? "The current sync stops and a new one exports from \(start)."
            : "HealthMule will sync from \(start)."
    }

    private func discardExportDraft() {
        draftRange = nil
        draftCustomStart = nil
    }

    // MARK: Drive

    @ViewBuilder
    private var driveSection: some View {
        if let account = model.googleConnection.account {
            Section("Google Drive") {
                if let email = account.email {
                    LabeledContent("Account", value: email)
                }
                if case .connected(let connection) = model.googleConnection {
                    LabeledContent("Folder", value: connection.folderName)
                    if let folderURL = connection.folderURL {
                        Button("Open in Google Drive") {
                            openURL(folderURL)
                        }
                    }
                }
                disconnectButton
            }
        } else if model.googleConnection.canDisconnect {
            Section("Google Drive") {
                disconnectButton
            }
        }
    }

    private var disconnectButton: some View {
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
            Text("Existing files in Google Drive will not be deleted.")
        }
    }
}

/// Shows the latest user-visible operation message unless the status already says it.
struct OperationNote: View {
    let message: String
    let isFailure: Bool

    init?(state: OperationState) {
        switch state {
        case .idle, .working(.sync, _), .failed(.sync, _):
            return nil
        case .working(_, let message), .warning(_, let message), .succeeded(_, let message):
            self.message = message
            isFailure = false
        case .failed(_, let message):
            self.message = message
            isFailure = true
        }
    }

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(isFailure ? Color.red : .secondary)
            .accessibilityIdentifier("operation-status")
    }
}

struct DiagnosticsButton: View {
    let model: AppModel

    var body: some View {
        if let diagnosticsURL = model.diagnosticsURL {
            ShareLink(item: diagnosticsURL) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("diagnostics-action")
        } else {
            Button("Prepare Diagnostics", systemImage: "doc.badge.gearshape") {
                Task { await model.prepareDiagnosticsExport() }
            }
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("diagnostics-action")
        }
    }
}

struct SyncDayProgressView: View {
    let progress: SyncProgress

    var body: some View {
        ProgressView(
            value: Double(progress.completedUnits),
            total: Double(progress.totalUnits)
        ) {
            EmptyView()
        } currentValueLabel: {
            Text(progress.presentationText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .tint(.primary)
        .animation(.default, value: progress.completedUnits)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sync progress")
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityIdentifier("sync-day-progress")
    }
}
