import SwiftUI

struct SyncView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isBackgroundDetailsExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: HealthMuleStyle.sectionSpacing) {
                syncHero
                uploadStatusCard

                VStack(spacing: 12) {
                    SectionHeading(title: "Fix a problem")
                    VStack(spacing: 10) {
                        SyncActionRow(
                            title: "Retry waiting uploads",
                            subtitle: "Try uploading prepared records again.",
                            systemImage: "arrow.clockwise",
                            isDisabled: model.operationState.isWorking
                                || !model.syncReadiness.canSync
                                || model.syncSummary.retryableUploadCount == 0
                        ) {
                            Task {
                                await model.retryFailedUploads()
                            }
                        }
                        .accessibilityIdentifier("retry-uploads-action")

                        SyncActionRow(
                            title: "Recheck recent health data",
                            subtitle: "Prepare the latest three days again.",
                            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                            isDisabled: model.operationState.isWorking
                                || !model.syncReadiness.canSync
                        ) {
                            Task {
                                await model.rebuildLastThreeDays()
                            }
                        }
                        .accessibilityIdentifier("rebuild-action")
                    }
                }

                backgroundDetailsCard

                HealthMuleNote(
                    text: "Opening the app reconciles automatically. iOS controls background timing.",
                    systemImage: "clock.badge.questionmark"
                )
            }
            .frame(maxWidth: HealthMuleStyle.contentWidth)
            .padding(.horizontal, HealthMuleStyle.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(HealthMuleStyle.canvas)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("sync-screen")
    }

    private var syncHero: some View {
        StatusHero(
            badge: syncPresentation.badge,
            tone: syncPresentation.tone,
            title: syncPresentation.title,
            message: syncPresentation.message,
            progress: model.syncProgress
        ) {
            syncHeroAction
        }
    }

    @ViewBuilder
    private var syncHeroAction: some View {
        if model.syncSummary.permanentFailureCount > 0 {
            if let diagnosticsURL = model.diagnosticsURL {
                ShareLink(item: diagnosticsURL) {
                    Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("sync-diagnostics-action")
            } else {
                Button {
                    Task {
                        await model.prepareDiagnosticsExport()
                    }
                } label: {
                    Label("Prepare Diagnostics", systemImage: "doc.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.operationState.isWorking)
                .accessibilityIdentifier("sync-diagnostics-action")
            }
        } else if model.syncReadiness.canSync {
            Button {
                Task {
                    await model.reconcile(trigger: .manual)
                }
            } label: {
                // The spinning glyph carries "in progress" so the label does
                // not have to restate a badge that already says Syncing.
                Label(syncActionLabel, systemImage: "arrow.triangle.2.circlepath")
                    .symbolEffect(
                        .rotate,
                        options: .repeating,
                        isActive: model.operationState.isWorking(.sync)
                    )
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("sync-now-action")
        } else if let setupActionLabel {
            NavigationLink(value: HomeRoute.setup) {
                Label(setupActionLabel, systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("sync-setup-action")
        }
    }

    private var syncActionLabel: String {
        model.presentedOperationState.isFailure(.sync)
            ? "Try Sync Again"
            : "Sync now"
    }

    private var uploadStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upload status")
                .font(HealthMuleStyle.Text.cardTitle)

            SyncFactsRow(summary: model.syncSummary)
        }
        .healthMuleCard(padding: 16)
    }

    private var backgroundDetailsCard: some View {
        DisclosureGroup(isExpanded: $isBackgroundDetailsExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                activityRow(
                    title: "Last automatic sync",
                    systemImage: "arrow.triangle.2.circlepath",
                    receipt: model.syncActivitySummary.latestAutomatic
                )
                .accessibilityIdentifier("automatic-activity-latest")

                Divider()
                    .padding(.leading, 44)

                activityRow(
                    title: "Last background refresh",
                    systemImage: "clock.arrow.circlepath",
                    receipt: model.syncActivitySummary.latestBackgroundRefresh
                )
                .accessibilityIdentifier("automatic-activity-background")

                Divider()
                    .padding(.leading, 44)

                scheduleRow(model.syncActivitySummary.schedule)
                    .accessibilityIdentifier("automatic-activity-schedule")

                SectionFooter(
                    text: "These are past attempts. iOS decides when background work runs."
                )
            }
            .padding(.top, 16)
        } label: {
            Text("Background details")
                .font(HealthMuleStyle.Text.cardTitle)
        }
        .healthMuleCard(padding: 16)
    }

    private func activityRow(
        title: String,
        systemImage: String,
        receipt: SyncActivityReceipt?
    ) -> some View {
        let status = receipt.map { $0.outcome.statusLabel }
            ?? "Never observed"
        let context = receipt?.trigger.activityLabel
        let timestamp = receipt.map {
            ($0.finishedAt ?? $0.startedAt).formatted(
                date: .abbreviated,
                time: .shortened
            )
        }
        return ActivityStatusRow(
            title: title,
            status: status,
            context: context,
            timestamp: timestamp,
            systemImage: systemImage,
            tone: receipt.map { $0.outcome.statusTone } ?? .neutral,
            accessibilityValue: activityText(receipt)
        )
    }

    private func scheduleRow(
        _ receipt: BackgroundRefreshScheduleReceipt?
    ) -> some View {
        let status: String
        let timestamp: String?
        if let receipt {
            status = scheduleResultLabel(receipt.result)
            timestamp = receipt.attemptedAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        } else {
            status = "Never requested"
            timestamp = nil
        }
        return ActivityStatusRow(
            title: "Schedule request",
            status: status,
            context: nil,
            timestamp: timestamp,
            systemImage: "calendar.badge.clock",
            tone: receipt.map { scheduleTone($0.result) } ?? .neutral,
            accessibilityValue: scheduleText(receipt)
        )
    }

    private func activityText(_ receipt: SyncActivityReceipt?) -> String {
        guard let receipt else { return "Never observed" }
        let timestamp = receipt.finishedAt ?? receipt.startedAt
        return "\(receipt.trigger.activityLabel) · "
            + "\(receipt.outcome.statusLabel) · "
            + timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    private func scheduleTone(
        _ result: BackgroundRefreshScheduleResult
    ) -> StatusTone {
        switch result {
        case .submitted, .existingRequestKept:
            .success
        case .failed:
            .danger
        }
    }

    private func scheduleText(
        _ receipt: BackgroundRefreshScheduleReceipt?
    ) -> String {
        guard let receipt else { return "Never requested" }
        return scheduleResultLabel(receipt.result) + " · "
            + receipt.attemptedAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
    }

    private func scheduleResultLabel(
        _ result: BackgroundRefreshScheduleResult
    ) -> String {
        switch result {
        case .submitted:
            "Submitted"
        case .existingRequestKept:
            "Existing request kept"
        case .failed(let reason):
            "Failed (\(scheduleFailureLabel(reason)))"
        }
    }

    private func scheduleFailureLabel(
        _ failure: BackgroundRefreshScheduleFailure
    ) -> String {
        switch failure {
        case .unavailable:
            "unavailable"
        case .tooManyPendingRequests:
            "too many pending requests"
        case .notPermitted:
            "not permitted"
        case .immediateRunIneligible:
            "immediate run ineligible"
        case .unknown:
            "unknown reason"
        }
    }

    private var syncPresentation: SyncPresentation {
        switch model.syncReadiness {
        case .localStorageUnavailable:
            return SyncPresentation(
                badge: "Storage error",
                tone: .danger,
                title: "Local sync storage is unavailable",
                message: "HealthMule could not prepare its protected staging area. No records can be staged or uploaded."
            )
        case .checkingConnections:
            return .connection(
                badge: "Checking",
                title: "Checking your connections",
                message: "HealthMule is restoring authorization state."
            )
        case .healthUnavailable:
            return .connection(
                badge: "Unavailable",
                title: "Apple Health is unavailable",
                message: "Sync requires a supported iPhone with Apple Health."
            )
        case .healthStatusUnavailable(let canSync):
            if !canSync {
                return .connection(
                    badge: "Check failed",
                    title: "Apple Health status is unavailable",
                    message: "Try the Health request check again from Setup."
                )
            }
            break
        case .healthRequestRequired:
            return .connection(
                badge: "Setup needed",
                title: "Request Apple Health access",
                message: "Complete the read-only Health request before syncing."
            )
        case .healthReviewRecommended:
            break
        case .googleNotConfigured:
            return .connection(
                badge: "Setup needed",
                title: "Configure Google Drive",
                message: "Add the local OAuth configuration before syncing."
            )
        case .googleDisconnected:
            return .connection(
                badge: "Setup needed",
                title: "Connect Google Drive",
                message: "Choose the Drive account that will own the export."
            )
        case .googleTemporarilyUnavailable:
            return .connection(
                badge: "Unavailable",
                title: "Google is temporarily unavailable",
                message: "Local records remain safe while the connection is restored."
            )
        case .googleReauthorizationRequired:
            return SyncPresentation(
                badge: "Reconnect",
                tone: .danger,
                title: "Google Drive needs approval",
                message: "Reconnect before retrying pending uploads."
            )
        case .googleDriveSetupRequired:
            return .connection(
                badge: "Finishing setup",
                title: "Preparing your Drive folder",
                message: "Google is authorized, but the managed folder is not ready."
            )
        case .googleDriveUnavailable:
            return .connection(
                badge: "Drive unavailable",
                title: "Drive folder setup needs a retry",
                message: "Local records are safe until the managed folder is verified."
            )
        case .ready:
            break
        }

        if model.operationState.isWorking(.sync) {
            return SyncPresentation(
                badge: "Syncing",
                tone: .accent,
                title: "Syncing your latest changes",
                message: Self.defaultSyncMessage
            )
        }
        if model.syncSummary.permanentFailureCount > 0 {
            return SyncPresentation(
                badge: "\(model.syncSummary.permanentFailureCount) blocked",
                tone: .danger,
                title: "Upload blocked",
                message: "Drive reported a non-retryable error. The local copy is safe; export diagnostics before resetting local sync state."
            )
        }
        if model.presentedOperationState.isFailure(.sync) {
            return SyncPresentation(
                badge: "Needs attention",
                tone: .danger,
                title: "Sync needs another look",
                message: syncFailureMessage
            )
        }
        if model.syncSummary.pendingUploadCount > 0 {
            return SyncPresentation(
                badge: "\(model.syncSummary.pendingUploadCount) pending",
                tone: .warning,
                title: "Uploads are waiting",
                message: Self.defaultSyncMessage
            )
        }
        if model.syncReadiness == .healthReviewRecommended {
            return SyncPresentation(
                badge: "Review suggested",
                tone: .warning,
                title: "Apple Health access needs review",
                message: "Existing readable types remain available to sync."
            )
        }
        if case .healthStatusUnavailable(canSync: true) = model.syncReadiness {
            return SyncPresentation(
                badge: "Check failed",
                tone: .warning,
                title: "Apple Health status could not be refreshed",
                message: "Previously readable data remains available to sync."
            )
        }
        if model.syncSummary.lastSuccessfulSyncAt == nil {
            return SyncPresentation(
                badge: "Ready",
                tone: .accent,
                title: "Ready for the first sync",
                message: Self.defaultSyncMessage
            )
        }
        return SyncPresentation(
            badge: "Uploads complete",
            tone: .success,
            title: "Your Drive export is current",
            message: "Recent changes and missing history have been checked."
        )
    }

    private static let defaultSyncMessage =
        "HealthMule checks recent changes and fills any missing history."

    private var syncFailureMessage: String {
        guard
            case .failed(.sync, let message) = model.presentedOperationState
        else {
            return "Sync could not finish. Try again."
        }
        return message
    }

    private var setupActionLabel: String? {
        switch model.syncReadiness {
        case
            .localStorageUnavailable,
            .checkingConnections,
            .healthUnavailable:
            nil
        case .healthStatusUnavailable(let canSync):
            canSync ? nil : "Check Health Again"
        case .healthRequestRequired:
            "Request Health Access"
        case .googleDisconnected:
            "Connect Drive"
        case .googleReauthorizationRequired:
            "Reconnect Drive"
        case .googleDriveUnavailable:
            "Retry Drive Setup"
        case
            .googleNotConfigured,
            .googleTemporarilyUnavailable,
            .googleDriveSetupRequired:
            "Review setup"
        case .healthReviewRecommended, .ready:
            nil
        }
    }

}

private struct ActivityStatusRow: View {
    let title: String
    let status: String
    let context: String?
    let timestamp: String?
    let systemImage: String
    let tone: StatusTone
    let accessibilityValue: String

    var body: some View {
        IconStatusRow(
            title: title,
            status: context.map { "\(status) · \($0)" } ?? status,
            detail: timestamp,
            systemImage: systemImage,
            tone: tone,
            accessibilityValue: accessibilityValue
        )
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
        .tint(HealthMuleStyle.tint)
        .animation(.default, value: progress.completedUnits)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sync progress")
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityIdentifier("sync-day-progress")
    }
}

private struct SyncPresentation {
    let badge: String
    let tone: StatusTone
    let title: String
    let message: String

    static func connection(
        badge: String,
        title: String,
        message: String
    ) -> SyncPresentation {
        SyncPresentation(
            badge: badge,
            tone: .warning,
            title: title,
            message: message
        )
    }
}

private struct SyncActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .healthMuleCard(padding: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
