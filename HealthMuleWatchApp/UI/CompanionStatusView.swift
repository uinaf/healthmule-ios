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
            VStack(spacing: 12) {
                statusHeader(status)
                connectionRow(status)
                facts(status)

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

    private func statusHeader(_ status: CompanionStatusModel) -> some View {
        let presentation = headlinePresentation(status.headline)
        return VStack(spacing: 6) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(presentation.color)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(presentation.title)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private func connectionRow(_ status: CompanionStatusModel) -> some View {
        Label(
            connectionText(status),
            systemImage: connectionImage(status.connection)
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("watch-connection-status")
    }

    @ViewBuilder
    private func facts(_ status: CompanionStatusModel) -> some View {
        VStack(spacing: 6) {
            if let lastSuccess = status.lastSuccessfulSyncAt {
                datedFactRow(
                    title: "Last confirmed",
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
                datedFactRow(title: "Updated", date: updatedAt)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
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
                status.syncActionBlock == .syncInProgress
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
                color: .primary
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
                color: .primary
            )
        case .finishSetup:
            StatusPresentation(
                title: "Finish Setup",
                systemImage: "iphone.badge.exclamationmark",
                color: .primary
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
        case .upToDate:
            StatusPresentation(
                title: "Up to Date",
                systemImage: "checkmark.circle.fill",
                color: .primary
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
                : "Status may be out of date"
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
