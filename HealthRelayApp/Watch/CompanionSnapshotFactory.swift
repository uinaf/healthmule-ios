import Foundation
import HealthRelayCompanion

enum CompanionSnapshotFactory {
    static func make(
        readiness: SyncReadiness,
        operationState: OperationState,
        summary: SyncSummary,
        now: Date = .now
    ) -> CompanionSyncSnapshot {
        CompanionSyncSnapshot(
            generatedAt: now,
            readiness: companionReadiness(for: readiness),
            activity: companionActivity(
                for: operationState,
                summary: summary
            ),
            canRequestSync: readiness.canSync && !operationState.isWorking,
            lastSuccessfulSyncAt: summary.lastSuccessfulSyncAt,
            pendingUploadCount: summary.pendingUploadCount,
            retryableUploadCount: summary.retryableUploadCount,
            permanentFailureCount: summary.permanentFailureCount
        )
    }

    private static func companionReadiness(
        for readiness: SyncReadiness
    ) -> CompanionSyncSnapshot.Readiness {
        switch readiness {
        case .ready:
            .ready
        case .checkingConnections:
            .checking
        case .healthReviewRecommended:
            .attention
        case .healthStatusUnavailable(let canSync):
            canSync ? .attention : .setupRequired
        case
            .googleTemporarilyUnavailable,
            .googleReauthorizationRequired,
            .googleDriveUnavailable:
            .attention
        case .localStorageUnavailable, .healthUnavailable:
            .unavailable
        case
            .healthRequestRequired,
            .googleNotConfigured,
            .googleDisconnected,
            .googleDriveSetupRequired:
            .setupRequired
        }
    }

    private static func companionActivity(
        for operationState: OperationState,
        summary: SyncSummary
    ) -> CompanionSyncSnapshot.Activity {
        switch operationState {
        case .working(.sync, _):
            return .syncing
        case .succeeded(.sync, _):
            return .synced
        case .warning(.sync, _), .failed(.sync, _):
            return .attention
        case .idle, .working, .warning, .succeeded, .failed:
            return summary.permanentFailureCount > 0 ? .attention : .idle
        }
    }
}
