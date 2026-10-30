import GoogleSignInSwift
import SwiftUI
import UIKit

enum HomeRoute: Hashable {
    case settings
    case metrics
    case advanced
}

struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                    statusHero
                    Spacer(minLength: 0)
                    if showsSetup {
                        setupCard
                    }
                    bottomBar
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .refreshable {
                // Return at once: the launch sync can run for minutes, and the
                // status already shows its progress.
                Task { await model.applicationDidBecomeActive() }
            }
        }
        .background(Color("PageBackground"))
        .navigationTitle("HealthMule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: HomeRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settings-link")
            }
        }
        .accessibilityIdentifier("home-screen")
    }

    // MARK: Status

    private var status: HomeStatus {
        HomeStatus(model: model)
    }

    private var statusHero: some View {
        VStack(spacing: 12) {
            if let progress = model.syncProgress, progress.totalUnits > 0 {
                SyncDayProgressView(progress: progress)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(status.tint)
                    .symbolEffect(.rotate, isActive: status.isWorking)
                    .accessibilityHidden(true)
            }
            Text(status.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("status-title")
            if let subtitle {
                subtitle
            }
            if let note = OperationNote(state: model.presentedOperationState) {
                note.multilineTextAlignment(.center)
            }
        }
        .padding(.top, 24)
    }

    private var subtitle: AnyView? {
        if let message = status.message {
            return AnyView(
                Text(message)
                    .accessibilityIdentifier("status-message")
                    .modifier(SubtitleStyle())
            )
        }
        if let progress = model.syncProgress, progress.totalUnits > 0 {
            return AnyView(Text(progress.dayText).modifier(SubtitleStyle()))
        }
        if showsSyncFacts {
            return AnyView(
                Text("Last sync \(model.syncSummary.lastSyncText) · Data through \(model.syncSummary.latestExportedDayText)")
                    .accessibilityIdentifier("last-sync-fact")
                    .modifier(SubtitleStyle())
            )
        }
        return nil
    }

    private var showsSyncFacts: Bool {
        model.initialLoadPhase == .loaded
            && model.syncSummary.lastSuccessfulSyncAt != nil
            && !model.operationState.isWorking(.sync)
    }

    // MARK: Bottom

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if !showsSetup, model.initialLoadPhase == .loaded {
                HStack(spacing: 20) {
                    connectionDot("Apple Health", isReady: model.healthAuthorizationState.allowsQueries)
                    connectionDot("Google Drive", isReady: model.googleConnection.isDriveReady)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if showsSetup {
                setupAction
            }
            // Health review and a stale status check still allow syncing.
            if let action = status.action,
               !showsSetup || model.syncReadiness.canSync || action == .diagnostics {
                statusAction(action)
            }
        }
    }

    /// Every recovery that applies stays reachable: a failed Health check
    /// must not hide a Google reconnect, and the reverse.
    @ViewBuilder
    private var setupAction: some View {
        let needsHealthAction: Bool = switch model.healthAuthorizationState {
        case .notRequested, .reviewRequired, .statusUnavailable: true
        case .unavailable, .checking, .requestCompleted: false
        }
        let needsGoogleAction: Bool = switch model.googleConnection {
        case .disconnected, .reauthorizationRequired, .temporarilyUnavailable, .driveUnavailable: true
        case .notConfigured, .restoring, .authorized, .connected: false
        }
        if needsHealthAction {
            healthAction
        }
        if needsGoogleAction {
            googleAction
        }
        if !needsHealthAction, !needsGoogleAction, model.backgroundDeliveryAdvisory != nil {
            checkHealthAgainButton
        }
    }

    private func connectionDot(_ title: String, isReady: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isReady ? "Connected" : "Needs attention")
    }

    @ViewBuilder
    private func statusAction(_ action: HomeStatus.Action) -> some View {
        switch action {
        case .sync(let title):
            Button {
                Task { await model.reconcile(trigger: .manual) }
            } label: {
                Text(title).primaryActionLabel()
            }
            .primaryActionStyle()
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("sync-now-action")
        case .retry:
            Button {
                Task { await model.retryFailedUploads() }
            } label: {
                Text("Retry Uploads").primaryActionLabel()
            }
            .primaryActionStyle()
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

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            setupStep(1, "Apple Health", healthStateText, isDone: model.healthAuthorizationState.allowsQueries)
                .accessibilityIdentifier("health-connection-row")
            Divider()
            setupStep(2, "Google Drive", googleStateText, isDone: model.googleConnection.isDriveReady)
                .accessibilityIdentifier("google-connection-row")
            if let advisory = model.backgroundDeliveryAdvisory {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(advisory.title).font(.subheadline.weight(.semibold))
                    Text(advisory.message).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("background-delivery-advisory")
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func setupStep(_ number: Int, _ title: String, _ state: String, isDone: Bool) -> some View {
        LabeledContent {
            Text(state)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(isDone ? Color.green : .secondary)
            }
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
            let button = Button {
                Task { await model.requestHealthAuthorization() }
            } label: {
                Text(
                    model.healthAuthorizationState == .reviewRequired
                        ? "Review Health Access"
                        : "Connect Apple Health"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            Group {
                // Sync Now stays primary when Health only needs a review.
                if model.syncReadiness.canSync {
                    button.buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(.secondary)
                } else {
                    button.primaryActionStyle()
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
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
        Button {
            Task { await model.retryHealthStatus() }
        } label: {
            Text("Check Apple Health Again")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.secondary)
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
            GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide) {
                Task { await model.connectGoogle() }
            }
            .disabled(model.operationState.isWorking)
            .accessibilityLabel(
                model.googleConnection == .disconnected
                    ? "Connect Google Drive"
                    : "Reconnect Google Drive"
            )
        case .temporarilyUnavailable, .driveUnavailable:
            Button {
                Task { await model.retryGoogleRestore() }
            } label: {
                Text("Try Drive Again").primaryActionLabel()
            }
            .primaryActionStyle()
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("google-retry-action")
        case .notConfigured, .restoring, .authorized, .connected:
            EmptyView()
        }
    }
}

private struct SubtitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

private extension Text {
    func primaryActionLabel() -> some View {
        fontWeight(.semibold)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
    }
}

private extension View {
    func primaryActionStyle() -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.primary)
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

    /// Home shows sync state in its status; other screens pass `includesSync`.
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

/// A ring with the completed count; the full progress text stays for VoiceOver.
struct SyncDayProgressView: View {
    let progress: SyncProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.default, value: progress.completedUnits)
            VStack(spacing: 0) {
                Text(progress.completedUnits.formatted())
                    .font(.title2.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(progress.totalUnits.formatted())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sync progress")
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityIdentifier("sync-day-progress")
    }
}
