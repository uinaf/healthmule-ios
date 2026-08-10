import HealthMuleCompanion
import SwiftUI

struct CompanionStatusView: View {
    let model: CompanionAppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(model.status(at: context.date))
        }
        .navigationTitle("HealthMule")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.activate()
        }
        .accessibilityIdentifier("watch-status-screen")
    }

    private func content(_ status: CompanionStatusModel) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                statusCard(status)

                if hasFacts(status) {
                    facts(status)
                }

                if status.showsSyncAction {
                    syncAction(status)
                }
                if status.canRetryConnection {
                    retryConnectionAction
                }
                if status.deliveryNote != .none {
                    deliveryNote(status.deliveryNote)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func statusCard(_ status: CompanionStatusModel) -> some View {
        let presentation = headlinePresentation(status.headline)
        return VStack(spacing: 8) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(presentation.color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 48, height: 48)
                .background(
                    presentation.color.opacity(0.12),
                    in: Circle()
                )
                .accessibilityHidden(true)

            Text(presentation.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            connectionRow(status)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .multilineTextAlignment(.center)
    }

    private func connectionRow(_ status: CompanionStatusModel) -> some View {
        Label(
            connectionText(status),
            systemImage: connectionImage(status.connection)
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("watch-connection-status")
    }

    @ViewBuilder
    private func facts(_ status: CompanionStatusModel) -> some View {
        VStack(spacing: 6) {
            if let lastSuccess = status.lastSuccessfulSyncAt {
                datedFactRow(
                    title: "Last successful sync",
                    date: lastSuccess
                )
            }
            if status.pendingUploadCount > 0 {
                countFactRow(
                    title: "Pending",
                    count: status.pendingUploadCount
                )
            }
            if status.retryableUploadCount > 0 {
                countFactRow(
                    title: "Retryable",
                    count: status.retryableUploadCount
                )
            }
            if status.permanentFailureCount > 0 {
                countFactRow(
                    title: "Blocked",
                    count: status.permanentFailureCount
                )
            }
            if let updatedAt = status.updatedAt {
                datedFactRow(title: "Status updated", date: updatedAt)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(10)
        .background(
            Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func hasFacts(_ status: CompanionStatusModel) -> Bool {
        status.lastSuccessfulSyncAt != nil
            || status.pendingUploadCount > 0
            || status.retryableUploadCount > 0
            || status.permanentFailureCount > 0
            || status.updatedAt != nil
    }

    private func datedFactRow(title: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
            Spacer(minLength: 4)
            Text(date, style: .relative)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func countFactRow(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
            Spacer(minLength: 4)
            Text(count.formatted())
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func syncAction(_ status: CompanionStatusModel) -> some View {
        VStack(spacing: 4) {
            Button {
                model.requestSync()
            } label: {
                if status.deliveryNote == .sending {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!status.canRequestSync)
            .accessibilityLabel(
                status.deliveryNote == .sending
                    ? "Sending sync request"
                    : status.syncActionBlock == .syncInProgress
                    ? "Syncing"
                    : "Sync"
            )
            .accessibilityIdentifier("watch-sync-action")

            if let reason = syncActionReason(status.syncActionBlock) {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var retryConnectionAction: some View {
        Button {
            model.activate()
        } label: {
            Label("Retry iPhone", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Retry iPhone connection")
        .accessibilityIdentifier("watch-retry-connection-action")
    }

    private func deliveryNote(_ note: CompanionDeliveryNote) -> some View {
        Text(deliveryText(note))
            .font(.caption2)
            .foregroundStyle(note == .failed ? .red : .secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .accessibilityIdentifier("watch-delivery-note")
    }

    private func headlinePresentation(
        _ headline: CompanionStatusHeadline
    ) -> StatusPresentation {
        switch headline {
        case .waitingForPhone:
            StatusPresentation(
                title: "Waiting for iPhone",
                systemImage: "iphone.and.arrow.forward",
                color: .secondary
            )
        case .syncing:
            StatusPresentation(
                title: "Syncing",
                systemImage: "arrow.triangle.2.circlepath",
                color: .primary
            )
        case .needsAttention:
            StatusPresentation(
                title: "Needs Attention",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        case .finishSetup:
            StatusPresentation(
                title: "Finish Setup",
                systemImage: "iphone.badge.exclamationmark",
                color: .orange
            )
        case .phoneUnavailable:
            StatusPresentation(
                title: "Phone Unavailable",
                systemImage: "iphone.slash",
                color: .red
            )
        case .ready:
            StatusPresentation(
                title: "Ready",
                systemImage: "checkmark.circle",
                color: .primary
            )
        case .statusOutOfDate:
            StatusPresentation(
                title: "Status Out of Date",
                systemImage: "clock.badge.questionmark",
                color: .orange
            )
        case .statusTimeUnavailable:
            StatusPresentation(
                title: "Status Time Unknown",
                systemImage: "clock.badge.questionmark",
                color: .orange
            )
        case .upToDate:
            StatusPresentation(
                title: "Up to Date",
                systemImage: "checkmark.circle.fill",
                color: .green
            )
        }
    }

    private func connectionText(_ status: CompanionStatusModel) -> String {
        switch status.connection {
        case .connecting:
            "Connecting to iPhone"
        case .reachable:
            "iPhone reachable · status current"
        case .unreachable:
            "iPhone unreachable · showing last status"
        case .waitingForSnapshot:
            "Waiting for iPhone status"
        case .stale:
            status.freshness == .unknown
                ? "Status time unavailable"
                : "Last iPhone update is over \(Int(CompanionStatusModel.currentSnapshotInterval / 60)) minutes old"
        case .activationFailed:
            "iPhone connection failed"
        }
    }

    private func connectionImage(
        _ connection: CompanionConnectionStatus
    ) -> String {
        switch connection {
        case .connecting, .waitingForSnapshot:
            "iphone.and.arrow.forward"
        case .reachable:
            "iphone.radiowaves.left.and.right"
        case .unreachable, .activationFailed:
            "iphone.slash"
        case .stale:
            "clock.badge.questionmark"
        }
    }

    private func syncActionReason(
        _ reason: CompanionSyncActionBlock?
    ) -> String? {
        switch reason {
        case nil:
            nil
        case .activationIncomplete:
            "Connecting to iPhone"
        case .phoneUnreachable:
            "Bring the iPhone within reach"
        case .snapshotDisallows:
            "Open the iPhone app"
        case .syncInProgress:
            "Sync already in progress"
        case .requestInProgress:
            "Waiting for iPhone acknowledgement"
        }
    }

    private func deliveryText(_ note: CompanionDeliveryNote) -> String {
        switch note {
        case .none:
            ""
        case .sending:
            "Sending request…"
        case .accepted:
            "Sync request accepted"
        case .failed:
            "Sync request failed. Try again."
        }
    }
}

private struct StatusPresentation {
    let title: String
    let systemImage: String
    let color: Color
}
