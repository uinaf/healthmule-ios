import Foundation
import HealthMuleCore

struct DriveArtifactDestination: ExportArtifactDestination {
    let driveClient: DriveAPIClient

    func upsert(_ artifact: ExportArtifact) async throws {
        do {
            let folders = try await driveClient
                .ensureAppFoldersForActiveAccount()
            switch artifact.id.kind {
            case .daily:
                guard let date = artifact.id.date else {
                    throw ExportDestinationError.permanent(
                        code: "missing_daily_date"
                    )
                }
                _ = try await driveClient.upsertJSON(
                    named: "\(date.rawValue).json",
                    parentID: folders.dailyID,
                    kind: "daily",
                    date: date.rawValue,
                    data: artifact.contents
                )
            case .manifest:
                _ = try await driveClient.upsertJSON(
                    named: "manifest.json",
                    parentID: folders.rootID,
                    kind: "manifest",
                    date: nil,
                    data: artifact.contents
                )
            }
        } catch let error as DriveAPIError {
            throw Self.destinationError(for: error)
        }
    }

    private static func destinationError(
        for error: DriveAPIError
    ) -> ExportDestinationError {
        switch error {
        case .reauthorizationRequired:
            .reauthorizationRequired(code: "drive_reauthorization_required")
        case .authenticationUnavailable:
            .transient(code: "google_token_refresh")
        case .accountNotReady:
            .transient(code: "drive_account_not_ready")
        case .destinationChanged:
            .transient(code: "drive_destination_changed")
        case .transport(let code):
            .transient(code: "transport_\(code.rawValue)")
        case .remote(let status, let reason, let retryable):
            if retryable {
                .transient(
                    code: "drive_\(status)_\(reason ?? "retryable")"
                )
            } else {
                .permanent(
                    code: "drive_\(status)_\(reason ?? "error")"
                )
            }
        case .invalidResponse:
            .permanent(code: "drive_invalid_response")
        }
    }
}
