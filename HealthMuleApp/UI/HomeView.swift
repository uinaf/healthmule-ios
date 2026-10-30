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
                NavigationLink(value: HomeRoute.advanced) {
                    Label("Advanced", systemImage: "gearshape")
                }
                .accessibilityIdentifier("advanced-link")
            }
        }
        .pageStyle()
        .navigationTitle("HealthMule")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("home-screen")
        .refreshable {
            // Return at once: the launch sync can run for minutes, and the
            // status section already shows its progress.
            Task { await model.applicationDidBecomeActive() }
        }
    }

    // MARK: Status

    private var status: HomeStatus {
        HomeStatus(model: model)
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: status.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(status.tint)
                    .symbolEffect(.rotate, isActive: status.isWorking)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("status-title")
                    if let message = status.message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("status-message")
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .listRowSeparator(.hidden)

            if let progress = model.syncProgress, progress.totalUnits > 0 {
                SyncDayProgressView(progress: progress)
            }

            if let note = OperationNote(state: model.presentedOperationState) {
                note
            }

            if let action = status.action {
                statusAction(action)
            }

        }
        if showsSyncFacts {
            Section {
                LabeledContent {
                    Text(model.syncSummary.lastSyncText)
                } label: {
                    Label("Last sync", systemImage: "clock")
                }
                .accessibilityIdentifier("last-sync-fact")
                LabeledContent {
                    Text(model.syncSummary.latestExportedDayText)
                } label: {
                    Label("Data through", systemImage: "calendar")
                }
                .accessibilityIdentifier("data-through-fact")
            }
        }
    }

    private var showsSyncFacts: Bool {
        model.initialLoadPhase == .loaded
            && model.syncSummary.lastSuccessfulSyncAt != nil
    }

    @ViewBuilder
    private func statusAction(_ action: HomeStatus.Action) -> some View {
        switch action {
        case .sync(let title):
            Button {
                Task { await model.reconcile(trigger: .manual) }
            } label: {
                Text(title)
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
                selection: Binding(
                    get: { shownRange },
                    set: { draftRange = $0 }
                )
            ) {
                ForEach(BackfillRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            } label: {
                Label("History", systemImage: "calendar.badge.clock")
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
                LabeledContent {
                    Text("\(model.enabledMetrics.count) of \(HealthMetric.allCases.count)")
                } label: {
                    Label("Metrics", systemImage: "heart.text.square")
                }
            }
            .accessibilityIdentifier("metrics-link")
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
        if let account = model.googleConnection.account {
            Section("Google Drive") {
                if let email = account.email {
                    Label(email, systemImage: "person.crop.circle")
                }
                if case .connected(let connection) = model.googleConnection {
                    if let folderURL = connection.folderURL {
                        Button {
                            openURL(folderURL)
                        } label: {
                            LabeledContent {
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(connection.folderName, systemImage: "folder")
                            }
                        }
                        .foregroundStyle(.primary)
                    } else {
                        Label(connection.folderName, systemImage: "folder")
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
            Text("Files in Drive stay.")
        }
    }
}

extension View {
    /// Neutral page grays shared with healthmule.uinaf.dev.
    func pageStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color("PageBackground"))
    }
}

/// Shows the latest user-visible operation message unless the status already says it.
struct OperationNote: View {
    let message: String
    let isFailure: Bool

    /// Home shows sync state in its status section; other screens pass `includesSync`.
    init?(state: OperationState, includesSync: Bool = false) {
        switch state {
        case .idle:
            return nil
        case .working(.sync, _) where !includesSync, .failed(.sync, _) where !includesSync:
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
        // Exports are snapshots, so preparing again captures later failures.
        Button(
            model.diagnosticsURL == nil ? "Prepare Diagnostics" : "Prepare Again",
            systemImage: "doc.badge.gearshape"
        ) {
            Task { await model.prepareDiagnosticsExport() }
        }
        .disabled(model.operationState.isWorking)
        .accessibilityIdentifier("diagnostics-action")
        if let diagnosticsURL = model.diagnosticsURL {
            ShareLink(item: diagnosticsURL) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("diagnostics-share-action")
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
