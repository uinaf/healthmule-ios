import Foundation

public struct CompanionSyncSnapshot: Codable, Equatable, Sendable {
    public struct Semantics: Equatable, Sendable {
        public let schemaVersion: Int
        public let readiness: Readiness
        public let activity: Activity
        public let canRequestSync: Bool
        public let lastSuccessfulSyncAt: Date?
        public let pendingUploadCount: Int
        public let retryableUploadCount: Int
        public let permanentFailureCount: Int
    }

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

    /// Orders snapshots from one phone install. WatchConnectivity can deliver
    /// an older user-info transfer after a newer application context, and the
    /// phone clock can move backward, so `generatedAt` cannot order them.
    public struct Revision: Codable, Equatable, Sendable {
        public let publisherID: UUID
        public let sequence: Int

        public init(publisherID: UUID, sequence: Int) {
            self.publisherID = publisherID
            self.sequence = sequence
        }
    }

    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let revision: Revision?
    public let readiness: Readiness
    public let activity: Activity
    public let canRequestSync: Bool
    public let lastSuccessfulSyncAt: Date?
    public let pendingUploadCount: Int
    public let retryableUploadCount: Int
    public let permanentFailureCount: Int

    public var semantics: Semantics {
        Semantics(
            schemaVersion: schemaVersion,
            readiness: readiness,
            activity: activity,
            canRequestSync: canRequestSync,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            pendingUploadCount: pendingUploadCount,
            retryableUploadCount: retryableUploadCount,
            permanentFailureCount: permanentFailureCount
        )
    }

    /// True unless both snapshots come from the same publisher and this one
    /// is not newer. Snapshots without a revision always apply.
    public func supersedes(_ current: CompanionSyncSnapshot?) -> Bool {
        guard
            let revision,
            let currentRevision = current?.revision,
            revision.publisherID == currentRevision.publisherID
        else {
            return true
        }
        return revision.sequence > currentRevision.sequence
    }

    public func revised(_ revision: Revision) -> CompanionSyncSnapshot {
        CompanionSyncSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            revision: revision,
            readiness: readiness,
            activity: activity,
            canRequestSync: canRequestSync,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            pendingUploadCount: pendingUploadCount,
            retryableUploadCount: retryableUploadCount,
            permanentFailureCount: permanentFailureCount
        )
    }

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        revision: Revision? = nil,
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
        self.revision = revision
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

public enum CompanionPayloadError: Error, Equatable, Sendable {
    case missingPayload
    case unsupportedSchema
    case invalidCounts
}

public enum CompanionPayloadCodec {
    public static let snapshotKey = "healthMuleSnapshot"
    public static let syncRequestKey = "healthMuleSyncRequest"
    public static let acceptedKey = "healthMuleAccepted"

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
