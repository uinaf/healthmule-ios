import SwiftUI

struct SyncView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OperationBanner(state: model.operationState)
                syncHero
                queueCard

                VStack(spacing: 12) {
                    SectionHeading(title: "Repair")
                    VStack(spacing: 10) {
                        SyncActionRow(
                            title: "Retry pending uploads",
                            subtitle: "Without rebuilding them.",
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
                            title: "Rebuild last 3 days",
                            subtitle: "Recompute the rolling window.",
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

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(
                        "Opening the app reconciles automatically. iOS controls background timing."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            needsAttention: syncPresentation.needsAttention,
            progress: model.syncProgress
        ) {
            syncHeroAction
        }
    }

    @ViewBuilder
    private var syncHeroAction: some View {
        if model.syncReadiness.canSync {
            Button {
                Task {
                    await model.reconcile(trigger: .manual)
                }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(model.operationState.isWorking)
            .accessibilityIdentifier("sync-now-action")
        } else if let setupActionLabel {
            NavigationLink(value: HomeRoute.setup) {
                Label(setupActionLabel, systemImage: "arrow.right")
            }
            .accessibilityIdentifier("sync-setup-action")
        }
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Queue")
                .font(HealthMuleStyle.Text.cardTitle)

            SyncFactsRow(summary: model.syncSummary)
        }
        .healthMuleCard(padding: 16)
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
        if model.operationState.isFailure(.sync) {
            return SyncPresentation(
                badge: "Needs attention",
                tone: .danger,
                title: "Sync needs another look",
                message: "Your local copies are safe. Try the pending work again."
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
            badge: "Queue clear",
            tone: .success,
            title: "Everything is staged and current",
            message: Self.defaultSyncMessage
        )
    }

    private static let defaultSyncMessage =
        "Changed days, the latest three days, and any missing backfill."

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

struct SyncDayProgressView: View {
    let progress: SyncProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(progress.presentationText)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            ProgressView(
                value: Double(progress.completedUnits),
                total: Double(progress.totalUnits)
            )
            .tint(HealthMuleStyle.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reconciliation progress")
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityIdentifier("sync-day-progress")
    }
}

private struct SyncPresentation {
    let badge: String
    let tone: StatusTone
    let title: String
    let message: String

    var needsAttention: Bool {
        tone == .warning || tone == .danger
    }

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
