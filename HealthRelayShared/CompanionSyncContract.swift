import Foundation

public struct CompanionSyncSnapshot: Codable, Equatable, Sendable {
    public enum Readiness: String, Codable, Sendable {
        case checking
        case ready
        case setupRequired
        case unavailable
        case attention
    }

    public enum Activity: String, Codable, Sendable {
        case idle
        case syncing
        case synced
        case attention
    }

    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let readiness: Readiness
    public let activity: Activity
    public let canRequestSync: Bool
    public let lastSuccessfulSyncAt: Date?
    public let pendingUploadCount: Int
    public let retryableUploadCount: Int
    public let permanentFailureCount: Int

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        readiness: Readiness,
        activity: Activity,
        canRequestSync: Bool,
        lastSuccessfulSyncAt: Date?,
        pendingUploadCount: Int,
        retryableUploadCount: Int,
        permanentFailureCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.readiness = readiness
        self.activity = activity
        self.canRequestSync = canRequestSync
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.pendingUploadCount = pendingUploadCount
        self.retryableUploadCount = retryableUploadCount
        self.permanentFailureCount = permanentFailureCount
    }

}

public struct CompanionSyncRequest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let requestedAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        requestedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.requestedAt = requestedAt
    }
}

enum CompanionPayloadError: Error, Equatable {
    case missingPayload
    case unsupportedSchema
    case invalidCounts
}

public enum CompanionPayloadCodec {
    public static let snapshotKey = "healthRelaySnapshot"
    public static let syncRequestKey = "healthRelaySyncRequest"
    public static let acceptedKey = "healthRelayAccepted"

    public static func message(
        snapshot: CompanionSyncSnapshot
    ) throws -> [String: Any] {
        [snapshotKey: try JSONEncoder().encode(snapshot)]
    }

    public static func snapshot(
        from message: [String: Any]
    ) throws -> CompanionSyncSnapshot {
        guard let data = message[snapshotKey] as? Data else {
            throw CompanionPayloadError.missingPayload
        }
        let snapshot = try JSONDecoder().decode(
            CompanionSyncSnapshot.self,
            from: data
        )
        guard snapshot.schemaVersion == CompanionSyncSnapshot.currentSchemaVersion else {
            throw CompanionPayloadError.unsupportedSchema
        }
        guard
            snapshot.pendingUploadCount >= 0,
            snapshot.retryableUploadCount >= 0,
            snapshot.permanentFailureCount >= 0
        else {
            throw CompanionPayloadError.invalidCounts
        }
        return snapshot
    }

    public static func message(
        syncRequest: CompanionSyncRequest
    ) throws -> [String: Any] {
        [syncRequestKey: try JSONEncoder().encode(syncRequest)]
    }

    public static func syncRequest(
        from message: [String: Any]
    ) throws -> CompanionSyncRequest {
        guard let data = message[syncRequestKey] as? Data else {
            throw CompanionPayloadError.missingPayload
        }
        let request = try JSONDecoder().decode(
            CompanionSyncRequest.self,
            from: data
        )
        guard request.schemaVersion == CompanionSyncRequest.currentSchemaVersion else {
            throw CompanionPayloadError.unsupportedSchema
        }
        return request
    }

    public static func acknowledgement(accepted: Bool) -> [String: Any] {
        [acceptedKey: accepted]
    }

    public static func isAccepted(_ message: [String: Any]) -> Bool {
        message[acceptedKey] as? Bool == true
    }
}
