import HealthRelayCompanion
import SwiftUI

struct CompanionStatusView: View {
    let model: CompanionAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusHeader

                if let snapshot = model.snapshot {
                    summary(snapshot)
                    if snapshot.canRequestSync {
                        syncButton(snapshot)
                    }
                } else {
                    waitingForPhone
                }

                if model.deliveryState != .idle {
                    deliveryNote
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .navigationTitle("Health Mule")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.activate()
        }
        .accessibilityIdentifier("watch-status-screen")
    }

    private var statusHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: statusPresentation.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(statusPresentation.color)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(statusPresentation.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let detail = statusPresentation.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var waitingForPhone: some View {
        ProgressView()
            .controlSize(.small)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func summary(
        _ snapshot: CompanionSyncSnapshot
    ) -> some View {
        Group {
            if snapshot.permanentFailureCount > 0 {
                Label(
                    "\(snapshot.permanentFailureCount.formatted()) blocked",
                    systemImage: "exclamationmark.circle"
                )
            } else if snapshot.retryableUploadCount > 0 {
                Label(
                    "\(snapshot.retryableUploadCount.formatted()) retrying",
                    systemImage: "arrow.clockwise.circle"
                )
            } else if snapshot.pendingUploadCount > 0 {
                Label(
                    "\(snapshot.pendingUploadCount.formatted()) pending",
                    systemImage: "arrow.up.circle"
                )
            } else if let lastSync = snapshot.lastSuccessfulSyncAt {
                Text(
                    "Last sync \(lastSync.formatted(date: .omitted, time: .shortened))"
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func syncButton(
        _ snapshot: CompanionSyncSnapshot
    ) -> some View {
        Button {
            model.requestSync()
        } label: {
            if model.deliveryState == .sending || snapshot.activity == .syncing {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canRequestSync)
        .accessibilityLabel(
            snapshot.activity == .syncing ? "Syncing" : "Sync"
        )
        .accessibilityIdentifier("watch-sync-action")
    }

    @ViewBuilder
    private var deliveryNote: some View {
        switch model.deliveryState {
        case .idle:
            EmptyView()
        case .sending:
            Text("Sending…")
        case .accepted:
            Text("Sync started")
        case .failed:
            Text("Try again")
        }
    }

    private var statusPresentation: StatusPresentation {
        guard let snapshot = model.snapshot else {
            return StatusPresentation(
                title: "Connecting",
                detail: nil,
                systemImage: "iphone.and.arrow.forward",
                color: .primary
            )
        }

        if snapshot.activity == .syncing {
            return StatusPresentation(
                title: "Syncing",
                detail: nil,
                systemImage: "arrow.triangle.2.circlepath",
                color: .primary
            )
        }

        if snapshot.activity == .attention {
            return StatusPresentation(
                title: "Needs Attention",
                detail: "Open iPhone app",
                systemImage: "exclamationmark.triangle.fill",
                color: .primary
            )
        }

        switch snapshot.readiness {
        case .checking:
            return StatusPresentation(
                title: "Checking",
                detail: nil,
                systemImage: "ellipsis.circle.fill",
                color: .primary
            )
        case .ready:
            return StatusPresentation(
                title: snapshot.activity == .synced ? "Up to Date" : "Ready",
                detail: nil,
                systemImage: "checkmark.circle.fill",
                color: .primary
            )
        case .setupRequired:
            return StatusPresentation(
                title: "Finish Setup",
                detail: "Open iPhone app",
                systemImage: "iphone.badge.exclamationmark",
                color: .primary
            )
        case .unavailable:
            return StatusPresentation(
                title: "Unavailable",
                detail: "Open iPhone app",
                systemImage: "exclamationmark.octagon.fill",
                color: .red
            )
        case .attention:
            return StatusPresentation(
                title: "Needs Attention",
                detail: "Open iPhone app",
                systemImage: "exclamationmark.triangle.fill",
                color: .primary
            )
        }
    }
}

private struct StatusPresentation {
    let title: String
    let detail: String?
    let systemImage: String
    let color: Color
}
